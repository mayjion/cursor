"""百度公开行情日K（东财限流时的免费回退源）。"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.collectors.eastmoney_quote import market_from_code
from app.config import SETTINGS
from app.db import store

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://gushitong.baidu.com/",
}


def _baidu_code(code: str) -> str:
    m = market_from_code(code)
    return f"{'sh' if m == 'sh' else 'sz'}{code}"


async def fetch_daily_bars(
    client: httpx.AsyncClient,
    code: str,
    *,
    limit: int = 320,
) -> list[dict[str, Any]]:
    uri = "https://finance.pae.baidu.com/vapi/v1/getquotation"
    params = {
        "srcid": "5353",
        "pointType": "string",
        "group": "quotation_kline_ab",
        "query": code,
        "code": _baidu_code(code),
        "market_type": "ab",
        "newFormat": "1",
        "is_kc": "0",
        "ktype": "day",
    }
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            resp = await client.get(uri, params=params, timeout=30.0)
            resp.raise_for_status()
            payload = resp.json()
            result = (payload.get("Result") or {}).get("newMarketData") or {}
            headers = result.get("headers") or []
            # marketData 是分号分隔的多行；也可能是 list
            raw = result.get("marketData")
            rows: list[str] = []
            if isinstance(raw, str):
                rows = [x for x in raw.split(";") if x.strip()]
            elif isinstance(raw, list):
                rows = raw
            # 解析表头索引
            idx = {h: i for i, h in enumerate(headers)}
            # 常见中文表头
            def col(*names: str) -> int | None:
                for n in names:
                    if n in idx:
                        return idx[n]
                return None

            i_date = col("时间", "date")
            i_open = col("开盘", "open")
            i_close = col("收盘", "close")
            i_high = col("最高", "high")
            i_low = col("最低", "low")
            i_vol = col("成交量", "volume")
            i_amt = col("成交额", "amount")
            i_chg = col("涨跌幅", "change_pct")
            out: list[dict[str, Any]] = []
            for line in rows:
                if isinstance(line, str):
                    parts = line.split(",")
                elif isinstance(line, (list, tuple)):
                    parts = [str(x) for x in line]
                else:
                    continue
                if i_date is None or i_close is None or i_date >= len(parts) or i_close >= len(parts):
                    continue
                try:
                    day = parts[i_date][:10]
                    close = float(parts[i_close])
                    open_ = float(parts[i_open]) if i_open is not None else close
                    high = float(parts[i_high]) if i_high is not None else close
                    low = float(parts[i_low]) if i_low is not None else close
                    vol = float(parts[i_vol]) if i_vol is not None and parts[i_vol] not in ("", "-") else None
                    amt = float(parts[i_amt]) if i_amt is not None and parts[i_amt] not in ("", "-") else None
                    chg = float(parts[i_chg]) if i_chg is not None and parts[i_chg] not in ("", "-") else None
                except ValueError:
                    continue
                out.append(
                    {
                        "code": code,
                        "trade_date": day,
                        "open": open_,
                        "close": close,
                        "high": high,
                        "low": low,
                        "volume": vol,
                        "amount": amt,
                        "change_pct": chg,
                    }
                )
            if out:
                out = out[-limit:]
            return out
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.5 * (attempt + 1))
    if last_err:
        raise last_err
    return []


async def refresh_bars(codes: list[str], *, limit: int = 320) -> int:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0 + 0.15
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
