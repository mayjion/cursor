"""东财公开：董监高持股变动（增持）。"""
from __future__ import annotations

import asyncio
from datetime import date, datetime, timedelta
from typing import Any

import httpx

from app.config import SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://data.eastmoney.com/",
}


def _parse_day(raw: Any) -> str | None:
    if raw is None:
        return None
    s = str(raw).strip()[:10]
    if len(s) >= 10 and s[4] == "-" and s[7] == "-":
        return s
    return None


async def fetch_executive_increases(
    *,
    days: int = 90,
    page_size: int = 500,
    max_pages: int = 40,
) -> list[dict[str, Any]]:
    """近 N 日 CHANGE_SHARES>0 的高管增持明细。"""
    since = (date.today() - timedelta(days=days)).isoformat()
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    out: list[dict[str, Any]] = []
    filter_expr = f"(CHANGE_SHARES>0)(CHANGE_DATE>='{since}')"

    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for page in range(1, max_pages + 1):
            params = {
                "reportName": "RPT_EXECUTIVE_HOLD_DETAILS",
                "columns": "ALL",
                "pageNumber": str(page),
                "pageSize": str(page_size),
                "sortTypes": "-1",
                "sortColumns": "CHANGE_DATE",
                "source": "WEB",
                "client": "WEB",
                "filter": filter_expr,
            }
            last_err: Exception | None = None
            data: list[Any] = []
            for attempt in range(3):
                try:
                    resp = await client.get(
                        "https://datacenter-web.eastmoney.com/api/data/v1/get",
                        params=params,
                        timeout=30.0,
                    )
                    resp.raise_for_status()
                    body = resp.json()
                    if not body.get("success"):
                        raise RuntimeError(body.get("message") or "insider api failed")
                    data = ((body.get("result") or {}).get("data")) or []
                    break
                except Exception as exc:  # noqa: BLE001
                    last_err = exc
                    await asyncio.sleep(0.4 * (attempt + 1))
            else:
                if last_err:
                    raise last_err

            if not data:
                break
            for row in data:
                if not isinstance(row, dict):
                    continue
                code = str(row.get("SECURITY_CODE") or "").zfill(6)
                if len(code) != 6:
                    continue
                day = _parse_day(row.get("CHANGE_DATE"))
                try:
                    shares = float(row.get("CHANGE_SHARES") or 0)
                except (TypeError, ValueError):
                    shares = 0.0
                if shares <= 0:
                    continue
                try:
                    amount = float(row["CHANGE_AMOUNT"]) if row.get("CHANGE_AMOUNT") is not None else None
                except (TypeError, ValueError):
                    amount = None
                try:
                    avg_price = float(row["AVERAGE_PRICE"]) if row.get("AVERAGE_PRICE") is not None else None
                except (TypeError, ValueError):
                    avg_price = None
                out.append(
                    {
                        "code": code,
                        "name": str(row.get("SECURITY_NAME") or code),
                        "person": str(row.get("PERSON_NAME") or ""),
                        "position": str(row.get("POSITION_NAME") or ""),
                        "change_date": day,
                        "change_shares": shares,
                        "change_amount": amount,
                        "average_price": avg_price,
                        "reason": str(row.get("CHANGE_REASON") or ""),
                        "relation": str(row.get("PERSON_DSE_RELATION") or ""),
                    }
                )
            if len(data) < page_size:
                break
            if gap:
                await asyncio.sleep(gap)
    return out


def aggregate_insider_by_code(events: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """按股票聚合增持强度。"""
    by: dict[str, dict[str, Any]] = {}
    for e in events:
        code = e["code"]
        pack = by.setdefault(
            code,
            {
                "code": code,
                "name": e.get("name") or code,
                "events": [],
                "event_count": 0,
                "total_shares": 0.0,
                "total_amount": 0.0,
                "persons": set(),
                "latest_date": None,
            },
        )
        pack["events"].append(e)
        pack["event_count"] += 1
        pack["total_shares"] += float(e.get("change_shares") or 0)
        if e.get("change_amount") is not None:
            pack["total_amount"] += float(e["change_amount"])
        if e.get("person"):
            pack["persons"].add(e["person"])
        d = e.get("change_date")
        if d and (pack["latest_date"] is None or d > pack["latest_date"]):
            pack["latest_date"] = d
            pack["name"] = e.get("name") or pack["name"]

    for pack in by.values():
        pack["person_count"] = len(pack["persons"])
        pack["persons"] = sorted(pack["persons"])
        pack["events"] = sorted(
            pack["events"],
            key=lambda x: x.get("change_date") or "",
            reverse=True,
        )[:20]
    return by
