"""东财公告：公司回购 / 控股股东增持计划。"""

from __future__ import annotations

import asyncio
import re
from datetime import date, timedelta
from typing import Any

import httpx

from app.config import SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://data.eastmoney.com/notices/",
}

# 排除股权激励相关的「回购价格调整」
_EXCLUDE_BUYBACK = re.compile(
    r"(限制性股票回购价格|调整股票期权|激励计划.*回购|回购价格的公告|行权价格)"
)
_BUYBACK_HIT = re.compile(
    r"(回购公司股份|回购公司部分|股份回购|回购股份进展|回购股份的进展|回购报告书|"
    r"首次回购|回购方案实施|获得回购公司股份)"
)
_HOLDER_HIT = re.compile(
    r"((控股股东|实际控制人).{0,12}增持|增持公司股份计划)"
)


def classify_ann_title(title: str) -> str | None:
    """返回 buyback / holder_increase / None。"""
    t = title or ""
    if _EXCLUDE_BUYBACK.search(t):
        # 仍可能同时有真实回购标题；激励调整单独排除
        if not _BUYBACK_HIT.search(t):
            return None
        if "激励" in t or "期权" in t or "限制性股票" in t:
            return None
    if _BUYBACK_HIT.search(t):
        return "buyback"
    if _HOLDER_HIT.search(t):
        return "holder_increase"
    return None


async def fetch_ann_signals_for_codes(
    codes: list[str],
    *,
    days: int = 90,
    concurrency: int = 12,
) -> dict[str, dict[str, Any]]:
    """按股票拉取近 N 日公告，识别回购/大股东增持。"""
    since = (date.today() - timedelta(days=days)).isoformat()
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    uniq = sorted({str(c).zfill(6) for c in codes if str(c).zfill(6).isdigit()})
    out: dict[str, dict[str, Any]] = {}
    sem = asyncio.Semaphore(concurrency)

    async with httpx.AsyncClient(headers=_HEADERS) as client:

        async def one(code: str) -> None:
            async with sem:
                try:
                    pack = await _fetch_one(client, code, since=since)
                except Exception:  # noqa: BLE001
                    pack = None
                if pack:
                    out[code] = pack
                if gap:
                    await asyncio.sleep(gap / max(concurrency, 1))

        await asyncio.gather(*(one(c) for c in uniq))
    return out


async def _fetch_one(
    client: httpx.AsyncClient,
    code: str,
    *,
    since: str,
) -> dict[str, Any] | None:
    buybacks: list[dict[str, Any]] = []
    holders: list[dict[str, Any]] = []
    name = code
    for page in range(1, 4):
        resp = await client.get(
            "https://np-anotice-stock.eastmoney.com/api/security/ann",
            params={
                "page_size": 50,
                "page_index": page,
                "ann_type": "A",
                "client_source": "web",
                "stock_list": code,
            },
            timeout=25.0,
        )
        resp.raise_for_status()
        body = resp.json()
        items = ((body.get("data") or {}).get("list")) or []
        if not items:
            break
        older = False
        for it in items:
            if not isinstance(it, dict):
                continue
            day = str(it.get("notice_date") or "")[:10]
            if day and day < since:
                older = True
                continue
            title = str(it.get("title") or "")
            kind = classify_ann_title(title)
            codes = it.get("codes") or []
            for c in codes:
                sc = str((c or {}).get("stock_code") or "").zfill(6)
                if sc == code and (c or {}).get("short_name"):
                    name = str(c["short_name"])
            if kind == "buyback":
                buybacks.append({"date": day, "title": title})
            elif kind == "holder_increase":
                holders.append({"date": day, "title": title})
        if older or len(items) < 50:
            break

    if not buybacks and not holders:
        return None
    buybacks.sort(key=lambda x: x.get("date") or "", reverse=True)
    holders.sort(key=lambda x: x.get("date") or "", reverse=True)
    latest = None
    for row in buybacks + holders:
        d = row.get("date")
        if d and (latest is None or d > latest):
            latest = d
    return {
        "code": code,
        "name": name,
        "has_buyback": bool(buybacks),
        "has_holder_increase": bool(holders),
        "buyback_count": len(buybacks),
        "holder_count": len(holders),
        "buybacks": buybacks[:10],
        "holder_increases": holders[:10],
        "latest_date": latest,
    }


def merge_ownership(
    insider_by: dict[str, dict[str, Any]],
    ann_by: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """合并高管增持与公告信号 → 所有权画像。"""
    codes = set(insider_by) | set(ann_by)
    out: dict[str, dict[str, Any]] = {}
    for code in codes:
        ins = insider_by.get(code)
        ann = ann_by.get(code)
        name = (ins or {}).get("name") or (ann or {}).get("name") or code
        sources: list[str] = []
        if ins and int(ins.get("event_count") or 0) > 0:
            sources.append("insider")
        if ann and ann.get("has_buyback"):
            sources.append("buyback")
        if ann and ann.get("has_holder_increase"):
            sources.append("holder_increase")
        if not sources:
            continue
        strength = 0.0
        if "insider" in sources:
            strength += 40.0 + min(30.0, int(ins.get("event_count") or 0) * 8.0)
            strength += min(20.0, float(ins.get("total_amount") or 0) / 1e6 * 2.0)
        if "buyback" in sources:
            strength += 35.0 + min(25.0, int((ann or {}).get("buyback_count") or 0) * 6.0)
        if "holder_increase" in sources:
            strength += 30.0 + min(20.0, int((ann or {}).get("holder_count") or 0) * 8.0)
        latest = None
        for d in (
            (ins or {}).get("latest_date"),
            (ann or {}).get("latest_date"),
        ):
            if d and (latest is None or d > latest):
                latest = d
        out[code] = {
            "code": code,
            "name": name,
            "sources": sources,
            "strength": round(min(100.0, strength), 1),
            "insider": ins,
            "ann": ann,
            "latest_date": latest,
            "event_count": int((ins or {}).get("event_count") or 0)
            + int((ann or {}).get("buyback_count") or 0)
            + int((ann or {}).get("holder_count") or 0),
            "total_amount": float((ins or {}).get("total_amount") or 0),
            "person_count": int((ins or {}).get("person_count") or 0),
            "persons": (ins or {}).get("persons") or [],
            "events": (ins or {}).get("events") or [],
            "has_buyback": bool(ann and ann.get("has_buyback")),
            "has_holder_increase": bool(ann and ann.get("has_holder_increase")),
        }
    return out
