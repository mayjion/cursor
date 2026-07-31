"""新浪公开基金净值序列（东财日K限流时的免费回退；用净值作价格代理）。"""
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


async def fetch_nav_bars(
    client: httpx.AsyncClient,
    code: str,
    *,
    limit: int = 320,
) -> list[dict[str, Any]]:
    uri = "https://stock.finance.sina.com.cn/fundInfo/api/openapi.php/CaihuiFundInfoService.getNav"
    params = {
        "symbol": code,
        "datefrom": "2020-01-01",
        "dateto": "2030-12-31",
        "page": "1",
        "num": str(max(limit, 400)),
    }
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            resp = await client.get(uri, params=params, timeout=30.0)
            resp.raise_for_status()
            data = (((resp.json() or {}).get("result") or {}).get("data") or {}).get("data") or []
            out: list[dict[str, Any]] = []
            for row in data:
                if not isinstance(row, dict):
                    continue
                day = str(row.get("fbrq") or "")[:10]
                nav = row.get("jjjz")
                if not day or nav is None:
                    continue
                try:
                    close = float(nav)
                except (TypeError, ValueError):
                    continue
                out.append(
                    {
                        "code": code,
                        "trade_date": day,
                        "open": close,
                        "close": close,
                        "high": close,
                        "low": close,
                        "volume": None,
                        "amount": None,
                        "change_pct": None,
                    }
                )
            # API 通常新→旧
            out.sort(key=lambda x: x["trade_date"])
            # 补 change_pct
            for i in range(1, len(out)):
                prev = out[i - 1]["close"]
                if prev:
                    out[i]["change_pct"] = (out[i]["close"] / prev - 1.0) * 100.0
            if len(out) > limit:
                out = out[-limit:]
            return out
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.5 * (attempt + 1))
    if last_err:
        raise last_err
    return []


async def refresh_bars(codes: list[str], *, limit: int = 320) -> int:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0 + 0.1
    total = 0
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for i, code in enumerate(codes):
            try:
                bars = await fetch_nav_bars(client, code, limit=limit)
                if bars:
                    store.replace_bars(code, bars)
                    total += len(bars)
            except Exception:  # noqa: BLE001
                pass
            if i + 1 < len(codes) and gap > 0:
                await asyncio.sleep(gap)
    store.set_meta("last_bars_at", store.utc_now_iso())
    store.set_meta("last_bars_source", "sina_nav")
    return total
