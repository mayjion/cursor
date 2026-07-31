"""东财公开：PE/PB 与财报增速。"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.config import SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://data.eastmoney.com/",
}


def _f(v: Any) -> float | None:
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


async def fetch_valuation_snapshot(code: str) -> dict[str, Any] | None:
    """RPT_VALUEANALYSIS_DET：PE_TTM / PB_MRQ 等。"""
    code = str(code).zfill(6)
    params = {
        "reportName": "RPT_VALUEANALYSIS_DET",
        "columns": "ALL",
        "filter": f'(SECURITY_CODE="{code}")',
        "pageNumber": "1",
        "pageSize": "1",
        "source": "WEB",
        "client": "WEB",
    }
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        resp = await client.get(
            "https://datacenter-web.eastmoney.com/api/data/v1/get",
            params=params,
            timeout=25.0,
        )
        resp.raise_for_status()
        body = resp.json()
        data = ((body.get("result") or {}).get("data")) or []
        if not data or not isinstance(data[0], dict):
            return None
        row = data[0]
        return {
            "code": code,
            "name": str(row.get("SECURITY_NAME_ABBR") or code),
            "pe_ttm": _f(row.get("PE_TTM")),
            "pe_lar": _f(row.get("PE_LAR")),
            "pb_mrq": _f(row.get("PB_MRQ")),
            "ps_ttm": _f(row.get("PS_TTM")),
            "peg": _f(row.get("PEG_CAR")),
            "market_cap": _f(row.get("TOTAL_MARKET_CAP")),
            "close": _f(row.get("CLOSE_PRICE")),
            "trade_date": str(row.get("TRADE_DATE") or "")[:10] or None,
        }


async def fetch_growth_snapshot(code: str) -> dict[str, Any] | None:
    """RPT_LICO_FN_CPD：最新一期营收/净利同比增速。"""
    code = str(code).zfill(6)
    params = {
        "reportName": "RPT_LICO_FN_CPD",
        "columns": "ALL",
        "filter": f'(SECURITY_CODE="{code}")',
        "pageNumber": "1",
        "pageSize": "1",
        "sortTypes": "-1",
        "sortColumns": "REPORTDATE",
        "source": "WEB",
        "client": "WEB",
    }
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        resp = await client.get(
            "https://datacenter-web.eastmoney.com/api/data/v1/get",
            params=params,
            timeout=25.0,
        )
        resp.raise_for_status()
        body = resp.json()
        data = ((body.get("result") or {}).get("data")) or []
        if not data or not isinstance(data[0], dict):
            return None
        row = data[0]
        # YSTZ/SJLTZ 单位通常为百分比数值，如 12.3 表示 12.3%
        return {
            "code": code,
            "name": str(row.get("SECURITY_NAME_ABBR") or code),
            "revenue_yoy": _f(row.get("YSTZ")),
            "profit_yoy": _f(row.get("SJLTZ")),
            "roe": _f(row.get("WEIGHTAVG_ROE")),
            "eps": _f(row.get("BASIC_EPS")),
            "report_date": str(row.get("REPORTDATE") or "")[:10] or None,
            "notice_date": str(row.get("NOTICE_DATE") or "")[:10] or None,
        }


async def fetch_fundamentals_map(
    codes: list[str],
    *,
    concurrency: int = 10,
) -> dict[str, dict[str, Any]]:
    """批量拉取估值+增速，合并为 fundamentals。"""
    uniq = sorted({str(c).zfill(6) for c in codes if str(c).zfill(6).isdigit()})
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    sem = asyncio.Semaphore(concurrency)
    out: dict[str, dict[str, Any]] = {}

    async def one(code: str) -> None:
        async with sem:
            val = None
            growth = None
            try:
                val = await fetch_valuation_snapshot(code)
            except Exception:  # noqa: BLE001
                val = None
            try:
                growth = await fetch_growth_snapshot(code)
            except Exception:  # noqa: BLE001
                growth = None
            if not val and not growth:
                return
            pe = (val or {}).get("pe_ttm")
            profit_yoy = (growth or {}).get("profit_yoy")
            peg = (val or {}).get("peg")
            if peg is None and pe is not None and pe > 0 and profit_yoy is not None:
                # profit_yoy 为百分比；PEG = PE / 增速(%)
                g = max(float(profit_yoy), 1.0) if float(profit_yoy) > 0 else None
                if g is not None:
                    peg = float(pe) / g
            out[code] = {
                "code": code,
                "name": (val or growth or {}).get("name") or code,
                "pe_ttm": pe,
                "pb_mrq": (val or {}).get("pb_mrq"),
                "ps_ttm": (val or {}).get("ps_ttm"),
                "peg": None if peg is None else round(float(peg), 4),
                "market_cap": (val or {}).get("market_cap"),
                "revenue_yoy": (growth or {}).get("revenue_yoy"),
                "profit_yoy": profit_yoy,
                "roe": (growth or {}).get("roe"),
                "eps": (growth or {}).get("eps"),
                "report_date": (growth or {}).get("report_date"),
                "trade_date": (val or {}).get("trade_date"),
            }
            if gap:
                await asyncio.sleep(gap / max(concurrency, 1))

    await asyncio.gather(*(one(c) for c in uniq))
    return out
