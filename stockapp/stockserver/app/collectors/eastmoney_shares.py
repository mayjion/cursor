from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.config import SETTINGS
from app.db import store

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.1 (personal research)",
    "Referer": "https://data.eastmoney.com/",
}


def _to_float(v: Any) -> float | None:
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _date_only(v: Any) -> str | None:
    if v is None:
        return None
    s = str(v)
    return s[:10] if len(s) >= 10 else s


async def fetch_share_history(
    client: httpx.AsyncClient,
    code: str,
    *,
    limit: int = 500,
) -> list[dict[str, Any]]:
    """东财公开 ETF 份额变动（含季报期间申购/赎回）。"""
    uri = "https://datacenter-web.eastmoney.com/api/data/v1/get"
    params = {
        "reportName": "RPT_FUND_ETF_SHARECHANGE",
        "columns": (
            "SECURITY_CODE,CHANGE_DATE,TOTAL_SHARE,"
            "PERIOD_APPLY_SHARE,PERIOD_REDEEM_SHARE,SHARE_CHANGE_Q,SHARE_CHANGE_QRATE"
        ),
        "filter": f'(SECURITY_CODE="{code}")',
        "pageNumber": "1",
        "pageSize": str(limit),
        "sortTypes": "-1",
        "sortColumns": "CHANGE_DATE",
        "source": "WEB",
        "client": "WEB",
    }
    resp = await client.get(uri, params=params, timeout=25.0)
    resp.raise_for_status()
    rows = ((resp.json().get("result") or {}).get("data")) or []
    raw: list[dict[str, Any]] = []
    for item in rows:
        if not isinstance(item, dict):
            continue
        date = _date_only(item.get("CHANGE_DATE"))
        total = _to_float(item.get("TOTAL_SHARE"))
        if not date or total is None:
            continue
        apply_s = _to_float(item.get("PERIOD_APPLY_SHARE"))
        redeem_s = _to_float(item.get("PERIOD_REDEEM_SHARE"))
        q_net = None
        if apply_s is not None or redeem_s is not None:
            q_net = (apply_s or 0.0) - (redeem_s or 0.0)
        raw.append(
            {
                "code": code,
                "change_date": date,
                "total_share": total,
                "apply_share": apply_s,
                "redeem_share": redeem_s,
                "quarter_net": q_net,
                "share_change_q": _to_float(item.get("SHARE_CHANGE_Q")),
            }
        )
    raw.sort(key=lambda x: x["change_date"])
    # 日净变动代理
    for i, row in enumerate(raw):
        if i == 0:
            row["daily_net"] = None
        else:
            row["daily_net"] = row["total_share"] - raw[i - 1]["total_share"]
    return raw


async def refresh_shares(codes: list[str], *, limit: int = 500) -> int:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    total = 0
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for i, code in enumerate(codes):
            try:
                rows = await fetch_share_history(client, code, limit=limit)
                if rows:
                    store.replace_shares(code, rows)
                    total += len(rows)
            except Exception:  # noqa: BLE001
                pass
            if i + 1 < len(codes) and gap > 0:
                await asyncio.sleep(gap)
    store.set_meta("last_shares_at", store.utc_now_iso())
    return total
