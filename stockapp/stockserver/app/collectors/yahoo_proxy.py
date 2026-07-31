"""公开外盘 / 商品代理序列（东财美股日K，零付费；Yahoo 在境内常 403）。"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.config import SETTINGS
from app.db import store

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://quote.eastmoney.com/",
}

# 因子 id → 东财美股代码（市场 105）；多代码取等权动量
PROXY_MAP: dict[str, list[str]] = {
    "sox_proxy": ["SMH"],
    "nasdaq_proxy": ["QQQ"],
    "xbi_proxy": ["XBI"],
    "aapl_proxy": ["AAPL"],
    "us_cloud_proxy": ["MSFT", "AMZN", "GOOGL"],
    "lme_proxy": ["CPER"],
    "usd_proxy": ["UUP"],
    "bond_yield_proxy": ["TLT"],
    "commodity_proxy": ["LIT"],
    "pmi_proxy": ["XLI"],
}


def ext_code(symbol: str) -> str:
    return f"Y:{symbol.upper()}"


def _secid(symbol: str) -> str:
    return f"105.{symbol.upper()}"


async def fetch_us_bars(
    client: httpx.AsyncClient,
    symbol: str,
    *,
    limit: int = 320,
) -> list[dict[str, Any]]:
    uri = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
    params = {
        "secid": _secid(symbol),
        "fields1": "f1,f2,f3,f4,f5,f6",
        "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61",
        "klt": "101",
        "fqt": "1",
        "end": "20500101",
        "lmt": str(limit),
        "ut": "b2884a393a59ad64002292a3e90d46a5",
    }
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            resp = await client.get(uri, params=params, timeout=30.0)
            resp.raise_for_status()
            data = resp.json().get("data") or {}
            klines = data.get("klines") or []
            out: list[dict[str, Any]] = []
            code = ext_code(symbol)
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
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.6 * (attempt + 1))
    if last_err:
        raise last_err
    return []


def all_proxy_symbols() -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for syms in PROXY_MAP.values():
        for s in syms:
            u = s.upper()
            if u not in seen:
                seen.add(u)
                ordered.append(u)
    return ordered


# 东财美股不可用时，用池内相关 A 股 ETF 日K作粗糙代理（仍公开）
A_SHARE_FALLBACK: dict[str, str] = {
    "XBI": "159748",
    "CPER": "159329",
    "LIT": "159305",
    "XLI": "159770",
    "TLT": "511010",
    "UUP": "510300",
    "AMZN": "159273",
    "GOOGL": "159273",
}


def _copy_fallback_bars(symbol: str) -> list[dict[str, Any]]:
    src = A_SHARE_FALLBACK.get(symbol.upper())
    if not src:
        return []
    bars = store.list_bars(src, limit=320)
    code = ext_code(symbol)
    out = []
    for b in bars:
        row = dict(b)
        row["code"] = code
        out.append(row)
    return out


async def refresh_external_proxies() -> dict[str, Any]:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    symbols = all_proxy_symbols()
    ok = 0
    bars_n = 0
    failed: list[str] = []
    via_fallback: list[str] = []
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for i, sym in enumerate(symbols):
            bars: list[dict[str, Any]] = []
            try:
                bars = await fetch_us_bars(client, sym)
            except Exception:  # noqa: BLE001
                bars = []
            if not bars:
                bars = _copy_fallback_bars(sym)
                if bars:
                    via_fallback.append(sym)
            if bars:
                store.replace_bars(ext_code(sym), bars)
                ok += 1
                bars_n += len(bars)
            else:
                failed.append(sym)
            if i + 1 < len(symbols) and gap > 0:
                await asyncio.sleep(gap + 0.25)
    store.set_meta("last_ext_at", store.utc_now_iso())
    return {
        "symbols_ok": ok,
        "bars": bars_n,
        "failed": failed,
        "via_a_fallback": via_fallback,
        "source": "eastmoney_us_105",
    }
