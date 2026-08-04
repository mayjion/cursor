"""东财 F10：公司概况、多年财务主表、主营构成。"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.config import SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://emweb.securities.eastmoney.com/",
}


def _f(v: Any) -> float | None:
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _day(raw: Any) -> str | None:
    if raw is None:
        return None
    s = str(raw).strip()[:10]
    return s if len(s) >= 10 else None


def _sec_prefix(code: str) -> str:
    c = str(code).zfill(6)
    return f"SH{c}" if c.startswith(("5", "6", "9")) else f"SZ{c}"


def _yi(v: float | None) -> float | None:
    """元 → 亿元，保留 2 位。"""
    if v is None:
        return None
    return round(v / 1e8, 2)


async def fetch_company_profile(code: str) -> dict[str, Any]:
    code = str(code).zfill(6)
    uri = (
        "https://emweb.securities.eastmoney.com/PC_HSF10/CompanySurvey/"
        f"CompanySurveyAjax?code={_sec_prefix(code)}"
    )
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        resp = await client.get(uri, timeout=25.0)
        resp.raise_for_status()
        body = resp.json()
    jb = body.get("jbzl") or {}
    fx = body.get("fxxg") or {}
    return {
        "code": code,
        "name": str(jb.get("agjc") or code),
        "full_name": str(jb.get("gsmc") or ""),
        "industry": str(jb.get("sshy") or jb.get("sszjhhy") or ""),
        "exchange": str(jb.get("ssjys") or ""),
        "website": str(jb.get("gswz") or ""),
        "profile": str(jb.get("gsjj") or "").strip(),
        "business_scope": str(jb.get("jyfw") or "").strip(),
        "list_date": _day(fx.get("ssrq")),
        "establish_date": _day(fx.get("clrq")),
        "employees": _f(jb.get("gyrs")),
        "chairman": str(jb.get("dsz") or ""),
        "ceo": str(jb.get("zjl") or ""),
    }


def _map_finance_row(row: dict[str, Any]) -> dict[str, Any]:
    rev = _f(row.get("TOTALOPERATEREVE"))
    np_ = _f(row.get("PARENTNETPROFIT"))
    return {
        "report_date": _day(row.get("REPORT_DATE")),
        "report_type": str(row.get("REPORT_TYPE") or ""),
        "report_name": str(row.get("REPORT_DATE_NAME") or ""),
        "revenue": rev,
        "revenue_yi": _yi(rev),
        "net_profit": np_,
        "net_profit_yi": _yi(np_),
        "deduct_net_profit": _f(row.get("KCFJCXSYJLR")),
        "deduct_net_profit_yi": _yi(_f(row.get("KCFJCXSYJLR"))),
        "operate_profit": _f(row.get("OPERATE_PROFIT_PK")),
        "operate_profit_yi": _yi(_f(row.get("OPERATE_PROFIT_PK"))),
        "gross_margin": _f(row.get("XSMLL")),
        "net_margin": _f(row.get("XSJLL")),
        "roe": _f(row.get("ROEJQ")),
        "eps": _f(row.get("EPSJB")),
        "bps": _f(row.get("BPS")),
        "revenue_yoy": _f(row.get("TOTALOPERATEREVETZ")),
        "profit_yoy": _f(row.get("PARENTNETPROFITTZ")),
        "ocf": _f(row.get("NETCASH_OPERATE_PK")),
        "ocf_yi": _yi(_f(row.get("NETCASH_OPERATE_PK"))),
        "ocf_per_share": _f(row.get("MGJYXJJE")),
    }


async def fetch_main_financials(
    code: str,
    *,
    report_type: str | None = "年报",
    limit: int = 8,
) -> list[dict[str, Any]]:
    """主财务指标。report_type=年报/一季报/三季报/中报；None=全部类型。"""
    code = str(code).zfill(6)
    filt = f'(SECURITY_CODE="{code}")'
    if report_type:
        filt += f'(REPORT_TYPE="{report_type}")'
    params = {
        "reportName": "RPT_F10_FINANCE_MAINFINADATA",
        "columns": "ALL",
        "filter": filt,
        "pageNumber": "1",
        "pageSize": str(limit),
        "sortColumns": "REPORT_DATE",
        "sortTypes": "-1",
        "source": "WEB",
        "client": "WEB",
    }
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        resp = await client.get(
            "https://datacenter-web.eastmoney.com/api/data/v1/get",
            params=params,
            timeout=30.0,
        )
        resp.raise_for_status()
        body = resp.json()
    data = ((body.get("result") or {}).get("data")) or []
    out: list[dict[str, Any]] = []
    for row in data:
        if isinstance(row, dict):
            out.append(_map_finance_row(row))
    return out


async def fetch_business_composition(code: str) -> dict[str, Any]:
    """主营构成：产品(2)/地区(3)。"""
    code = str(code).zfill(6)
    uri = (
        "https://emweb.securities.eastmoney.com/PC_HSF10/BusinessAnalysis/"
        f"PageAjax?code={_sec_prefix(code)}"
    )
    async with httpx.AsyncClient(headers=_HEADERS) as client:
        resp = await client.get(uri, timeout=30.0)
        resp.raise_for_status()
        body = resp.json()
    items = body.get("zygcfx") or []
    review_rows = body.get("jyps") or []
    review = ""
    if review_rows and isinstance(review_rows[0], dict):
        review = str(review_rows[0].get("BUSINESS_REVIEW") or "").strip()

    if not items:
        return {"report_date": None, "by_product": [], "by_region": [], "review": review}

    latest = max(
        str(it.get("REPORT_DATE") or "")[:10] for it in items if it.get("REPORT_DATE")
    )

    def _pack(mainop_type: str) -> list[dict[str, Any]]:
        rows = [
            it
            for it in items
            if str(it.get("REPORT_DATE") or "")[:10] == latest
            and str(it.get("MAINOP_TYPE")) == mainop_type
        ]
        out: list[dict[str, Any]] = []
        for it in rows:
            name = str(it.get("ITEM_NAME") or "")
            if not name or name.startswith("其他(补充)"):
                continue
            income = _f(it.get("MAIN_BUSINESS_INCOME"))
            ratio = _f(it.get("MBI_RATIO"))
            if ratio is not None and ratio > 1.5:
                ratio = ratio / 100.0
            gm = _f(it.get("GROSS_RPOFIT_RATIO"))
            if gm is not None and gm <= 1.5:
                gm = gm * 100.0
            out.append(
                {
                    "name": name,
                    "income": income,
                    "income_yi": _yi(income),
                    "ratio": None if ratio is None else round(ratio, 4),
                    "gross_margin": None if gm is None else round(gm, 2),
                    "profit": _f(it.get("MAIN_BUSINESS_RPOFIT")),
                }
            )
        out.sort(key=lambda x: float(x.get("ratio") or 0), reverse=True)
        return out

    prev_candidates = sorted(
        {
            str(it.get("REPORT_DATE") or "")[:10]
            for it in items
            if str(it.get("MAINOP_TYPE")) == "2"
            and str(it.get("REPORT_DATE") or "")[:10] < latest
            and str(it.get("REPORT_DATE") or "")[:10].endswith("-12-31")
        },
        reverse=True,
    )
    prev = prev_candidates[0] if prev_candidates else None
    prev_map = {
        str(it.get("ITEM_NAME")): _f(it.get("MAIN_BUSINESS_INCOME"))
        for it in items
        if prev
        and str(it.get("REPORT_DATE") or "")[:10] == prev
        and str(it.get("MAINOP_TYPE")) == "2"
    }
    products = _pack("2")
    for p in products:
        base = prev_map.get(p["name"])
        cur = p.get("income")
        if base and base > 0 and cur is not None:
            p["yoy"] = round(cur / base - 1.0, 4)
        else:
            p["yoy"] = None

    return {
        "report_date": latest,
        "by_product": products,
        "by_region": _pack("3"),
        "review": review,
    }


async def fetch_quarter_rows(code: str, *, limit: int = 12) -> list[dict[str, Any]]:
    """最近若干期（含季报）主财务。"""
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    rows = await fetch_main_financials(code, report_type=None, limit=limit)
    if gap:
        await asyncio.sleep(gap)
    return rows
