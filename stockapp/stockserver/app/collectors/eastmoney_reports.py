"""东财公开研报列表：个股目标价（indvAimPriceT/L）。"""
from __future__ import annotations

import asyncio
import statistics
from datetime import date, timedelta
from typing import Any

import httpx

from app.config import SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://data.eastmoney.com/report/",
}


def _f(v: Any) -> float | None:
    if v is None or v == "":
        return None
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    if x <= 0:
        return None
    return x


def _day(raw: Any) -> str | None:
    if raw is None:
        return None
    s = str(raw).strip()[:10]
    return s if len(s) >= 10 else None


async def fetch_reports_with_targets(
    *,
    days: int = 90,
    page_size: int = 100,
    max_pages: int = 40,
) -> list[dict[str, Any]]:
    """近 N 日带有效目标价的个股研报。"""
    begin = (date.today() - timedelta(days=days)).isoformat()
    end = date.today().isoformat()
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    out: list[dict[str, Any]] = []

    async with httpx.AsyncClient(headers=_HEADERS) as client:
        for page in range(1, max_pages + 1):
            params = {
                "industryCode": "*",
                "pageNo": page,
                "pageSize": page_size,
                "code": "*",
                "industry": "*",
                "rating": "*",
                "ratingChange": "*",
                "beginTime": begin,
                "endTime": end,
                "fields": "",
                "qType": 0,
            }
            data: list[Any] = []
            last_err: Exception | None = None
            for attempt in range(3):
                try:
                    resp = await client.get(
                        "https://reportapi.eastmoney.com/report/list",
                        params=params,
                        timeout=30.0,
                    )
                    resp.raise_for_status()
                    body = resp.json()
                    data = body.get("data") or []
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
                code = str(row.get("stockCode") or "").zfill(6)
                if len(code) != 6:
                    continue
                aim_t = _f(row.get("indvAimPriceT"))
                aim_l = _f(row.get("indvAimPriceL"))
                aim = aim_t or aim_l
                if aim is None:
                    continue
                out.append(
                    {
                        "code": code,
                        "name": str(row.get("stockName") or code),
                        "title": str(row.get("title") or ""),
                        "org": str(row.get("orgSName") or row.get("orgName") or ""),
                        "publish_date": _day(row.get("publishDate")),
                        "aim_price": aim,
                        "aim_price_t": aim_t,
                        "aim_price_l": aim_l,
                        "rating": str(row.get("emRatingName") or row.get("sRatingName") or ""),
                        "info_code": str(row.get("infoCode") or ""),
                    }
                )
            if len(data) < page_size:
                break
            if gap:
                await asyncio.sleep(gap)
    return out


def aggregate_targets_by_code(
    reports: list[dict[str, Any]],
    *,
    price_by_code: dict[str, float] | None = None,
    min_upside: float = 0.30,
) -> dict[str, dict[str, Any]]:
    """按股票聚合目标价；若提供现价则只保留上行空间达标者。"""
    by: dict[str, list[dict[str, Any]]] = {}
    for r in reports:
        by.setdefault(r["code"], []).append(r)

    out: dict[str, dict[str, Any]] = {}
    for code, rows in by.items():
        aims = [float(r["aim_price"]) for r in rows if r.get("aim_price")]
        if not aims:
            continue
        med = statistics.median(aims)
        latest = sorted(rows, key=lambda x: x.get("publish_date") or "", reverse=True)[0]
        price = (price_by_code or {}).get(code)
        upside = None
        if price and price > 0:
            upside = med / price - 1.0
            if upside < min_upside:
                continue
        orgs = sorted({str(r.get("org") or "") for r in rows if r.get("org")})
        out[code] = {
            "code": code,
            "name": latest.get("name") or code,
            "target_median": round(med, 4),
            "target_mean": round(statistics.mean(aims), 4),
            "target_min": round(min(aims), 4),
            "target_max": round(max(aims), 4),
            "target_latest": float(latest["aim_price"]),
            "report_count": len(rows),
            "org_count": len(orgs),
            "orgs": orgs[:12],
            "upside": None if upside is None else round(upside, 4),
            "price": price,
            "reports": sorted(rows, key=lambda x: x.get("publish_date") or "", reverse=True)[:15],
            "latest_date": latest.get("publish_date"),
            "latest_rating": latest.get("rating"),
        }
    return out
