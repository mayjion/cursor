"""新浪公开 A 股日K / 快照（东财限流时回退）。"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.config import SETTINGS
from app.db import store

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://finance.sina.com.cn/",
}


def sina_symbol(code: str) -> str:
    c = str(code).zfill(6)
    if c.startswith(("5", "6", "9")):
        return f"sh{c}"
    return f"sz{c}"


async def fetch_daily_bars(
    client: httpx.AsyncClient,
    code: str,
    *,
    limit: int = 320,
) -> list[dict[str, Any]]:
    params = {
        "symbol": sina_symbol(code),
        "scale": "240",
        "ma": "no",
        "datalen": str(max(limit, 60)),
    }
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            resp = await client.get(
                "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData",
                params=params,
                timeout=25.0,
            )
            resp.raise_for_status()
            data = resp.json()
            if not isinstance(data, list):
                return []
            out: list[dict[str, Any]] = []
            prev_close: float | None = None
            for row in data:
                if not isinstance(row, dict):
                    continue
                day = str(row.get("day") or "")[:10]
                try:
                    close = float(row["close"])
                    o = float(row["open"])
                    h = float(row["high"])
                    low = float(row["low"])
                except (TypeError, ValueError, KeyError):
                    continue
                chg = None
                if prev_close and prev_close > 0:
                    chg = (close / prev_close - 1.0) * 100.0
                try:
                    vol = float(row["volume"]) if row.get("volume") is not None else None
                except (TypeError, ValueError):
                    vol = None
                out.append(
                    {
                        "code": code,
                        "trade_date": day,
                        "open": o,
                        "close": close,
                        "high": h,
                        "low": low,
                        "volume": vol,
                        "amount": None,
                        "change_pct": chg,
                    }
                )
                prev_close = close
            if len(out) > limit:
                out = out[-limit:]
            return out
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.5 * (attempt + 1))
    if last_err:
        raise last_err
    return []


async def fetch_quotes(codes: list[str]) -> dict[str, dict[str, Any]]:
    if not codes:
        return {}
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    out: dict[str, dict[str, Any]] = {}
    # sina hq supports batch ~80
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for i in range(0, len(codes), 60):
            chunk = codes[i : i + 60]
            lst = ",".join(sina_symbol(c) for c in chunk)
            try:
                resp = await client.get(
                    "https://hq.sinajs.cn/list=" + lst,
                    timeout=20.0,
                )
                resp.raise_for_status()
                text = resp.text
            except Exception:  # noqa: BLE001
                continue
            for line in text.splitlines():
                # var hq_str_sh601318="name,open,prev,price,...";
                if "hq_str_" not in line or '="' not in line:
                    continue
                try:
                    sym = line.split("hq_str_")[1].split("=")[0]
                    payload = line.split('="', 1)[1].rsplit('";', 1)[0]
                except IndexError:
                    continue
                parts = payload.split(",")
                if len(parts) < 4:
                    continue
                code = sym[2:]
                try:
                    price = float(parts[3]) if parts[3] else None
                    prev = float(parts[2]) if parts[2] else None
                except ValueError:
                    price, prev = None, None
                chg = None
                if price is not None and prev and prev > 0:
                    chg = (price / prev - 1.0) * 100.0
                out[code] = {
                    "code": code,
                    "name": parts[0] or code,
                    "price": price,
                    "change_pct": chg,
                    "amount": None,
                    "updated_at": store.utc_now_iso(),
                    "raw_json": "{}",
                    "score": 50.0,
                    "signal": "yellow",
                }
            if gap:
                await asyncio.sleep(gap)
    return out


async def refresh_bars(codes: list[str], *, limit: int = 320) -> int:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0 + 0.05
    total = 0
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for i, code in enumerate(codes):
            try:
                bars = await fetch_daily_bars(client, code, limit=limit)
                if bars:
                    store.replace_bars(code, bars)
                    total += len(bars)
            except Exception:  # noqa: BLE001
                pass
            if i + 1 < len(codes) and gap:
                await asyncio.sleep(gap)
    return total
