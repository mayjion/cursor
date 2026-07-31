from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.collectors.eastmoney_quote import secid_from_code
from app.config import SETTINGS
from app.db import store

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.1 (personal research)",
    "Referer": "https://quote.eastmoney.com/",
}


async def fetch_daily_bars(
    client: httpx.AsyncClient,
    code: str,
    *,
    limit: int = 320,
) -> list[dict[str, Any]]:
    """东财公开日 K（前复权），带短暂重试。"""
    uri = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
    params = {
        "secid": secid_from_code(code),
        "fields1": "f1,f2,f3,f4,f5,f6",
        "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61",
        "klt": "101",
        "fqt": "1",
        "end": "20500101",
        "lmt": str(limit),
        "ut": "b2884a393a59ad64002292a3e90d46a5",
    }
    last_err: Exception | None = None
    data: dict[str, Any] = {}
    for attempt in range(4):
        try:
            resp = await client.get(uri, params=params, timeout=25.0)
            resp.raise_for_status()
            data = resp.json().get("data") or {}
            break
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.5 * (attempt + 1))
    else:
        if last_err:
            raise last_err
    klines = data.get("klines") or []
    out: list[dict[str, Any]] = []
    for line in klines:
        if not isinstance(line, str):
            continue
        parts = line.split(",")
        if len(parts) < 6:
            continue
        try:
            out.append(
                {
                    "code": code,
                    "trade_date": parts[0],
                    "open": float(parts[1]),
                    "close": float(parts[2]),
                    "high": float(parts[3]),
                    "low": float(parts[4]),
                    "volume": float(parts[5]) if parts[5] else None,
                    "amount": float(parts[6]) if len(parts) > 6 and parts[6] else None,
                    "change_pct": float(parts[8]) if len(parts) > 8 and parts[8] else None,
                }
            )
        except ValueError:
            continue
    return out


async def refresh_bars(codes: list[str], *, limit: int = 320) -> int:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
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
            if i + 1 < len(codes) and gap > 0:
                await asyncio.sleep(gap)
    store.set_meta("last_bars_at", store.utc_now_iso())
    return total
