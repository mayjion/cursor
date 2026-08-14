"""涨停候选与主力净流入采集。"""
from __future__ import annotations

import asyncio
from datetime import datetime
from typing import Any

import httpx

from app.collectors.sina_stock import fetch_daily_bars, sina_symbol
from app.config import SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://quote.eastmoney.com/",
}

CLIST_URLS = [
    "https://push2delay.eastmoney.com/api/qt/clist/get",
    "https://push2.eastmoney.com/api/qt/clist/get",
]


def _f(v: Any) -> float | None:
    if v is None or v == "" or v == "-":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


async def fetch_zt_pool_candidates(
    client: httpx.AsyncClient,
    *,
    trade_date: str | None = None,
    pagesize: int = 200,
    min_market_cap_yi: float = 100.0,
) -> list[dict[str, Any]]:
    """东财涨停池；失败则回退 clist 大涨票。"""
    day = (trade_date or datetime.now().strftime("%Y%m%d")).replace("-", "")
    params = {
        "ut": "7eea3edcaed734bea9cbfc24409ed989",
        "dpt": "wz.ztzt",
        "Pageindex": "0",
        "pagesize": str(pagesize),
        "sort": "fbt:asc",
        "date": day,
    }
    out: list[dict[str, Any]] = []
    try:
        resp = await client.get(
            "https://push2ex.eastmoney.com/getTopicZTPool",
            params=params,
            timeout=25.0,
            headers={**_HEADERS, "Referer": "https://quote.eastmoney.com/ztb/"},
        )
        resp.raise_for_status()
        pool = ((resp.json().get("data") or {}).get("pool")) or []
        for row in pool:
            if not isinstance(row, dict):
                continue
            code = str(row.get("c") or "").zfill(6)
            name = str(row.get("n") or "")
            if not code.isdigit() or len(code) != 6:
                continue
            if "ST" in name.upper():
                continue
            if code.startswith(("4", "8")):
                continue
            # zsz=总市值（元）常见字段；没有则后面用 clist 补
            mcap = _f(row.get("zsz")) or _f(row.get("tshare"))
            mcap_yi = (mcap / 1e8) if mcap and mcap > 1e6 else None
            if mcap_yi is not None and mcap_yi < min_market_cap_yi:
                continue
            out.append(
                {
                    "code": code,
                    "name": name,
                    "market_cap_yi": round(mcap_yi, 2) if mcap_yi else None,
                    "change_pct": _f(row.get("zdp")),
                    "price": _f(row.get("p")),
                    "source": "zt_pool",
                    "trade_date": f"{day[:4]}-{day[4:6]}-{day[6:8]}",
                }
            )
    except Exception:  # noqa: BLE001
        out = []

    if out:
        # 补市值：对缺失的再拉一页 clist 大市值对照
        need = [r for r in out if r.get("market_cap_yi") is None]
        if need:
            caps = await fetch_large_cap_map(client, min_yi=min_market_cap_yi)
            filtered: list[dict[str, Any]] = []
            for r in out:
                if r.get("market_cap_yi") is None:
                    cap = caps.get(r["code"])
                    if cap is None or cap < min_market_cap_yi:
                        continue
                    r["market_cap_yi"] = round(cap, 2)
                filtered.append(r)
            out = filtered
        return out

    return await fetch_limitup_from_clist(
        client, min_market_cap_yi=min_market_cap_yi
    )


async def fetch_large_cap_map(
    client: httpx.AsyncClient, *, min_yi: float = 100.0, pages: int = 8
) -> dict[str, float]:
    caps: dict[str, float] = {}
    for page in range(1, pages + 1):
        params = {
            "pn": str(page),
            "pz": "100",
            "po": "1",
            "np": "1",
            "fltt": "2",
            "invt": "2",
            "fid": "f20",
            "fs": "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048",
            "fields": "f12,f14,f20",
            "ut": "b2884a393a59ad64002292a3e90d46a5",
        }
        ok = False
        for url in CLIST_URLS:
            try:
                resp = await client.get(url, params=params, timeout=25.0)
                resp.raise_for_status()
                diff = ((resp.json().get("data") or {}).get("diff")) or []
                for row in diff:
                    if not isinstance(row, dict):
                        continue
                    code = str(row.get("f12") or "").zfill(6)
                    mcap = _f(row.get("f20"))
                    if not code.isdigit() or mcap is None:
                        continue
                    yi = mcap / 1e8
                    if yi >= min_yi:
                        caps[code] = yi
                ok = True
                break
            except Exception:  # noqa: BLE001
                continue
        if not ok:
            break
        await asyncio.sleep(0.15)
    return caps


async def fetch_limitup_from_clist(
    client: httpx.AsyncClient,
    *,
    min_market_cap_yi: float = 100.0,
    pages: int = 6,
) -> list[dict[str, Any]]:
    """按涨跌幅排序的大市值票中筛近似涨停。"""
    out: list[dict[str, Any]] = []
    for page in range(1, pages + 1):
        params = {
            "pn": str(page),
            "pz": "100",
            "po": "1",
            "np": "1",
            "fltt": "2",
            "invt": "2",
            "fid": "f3",
            "fs": "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048",
            "fields": "f12,f14,f2,f3,f20",
            "ut": "b2884a393a59ad64002292a3e90d46a5",
        }
        diff: list[Any] = []
        for url in CLIST_URLS:
            try:
                resp = await client.get(url, params=params, timeout=25.0)
                resp.raise_for_status()
                diff = ((resp.json().get("data") or {}).get("diff")) or []
                break
            except Exception:  # noqa: BLE001
                continue
        if not diff:
            break
        for row in diff:
            if not isinstance(row, dict):
                continue
            code = str(row.get("f12") or "").zfill(6)
            name = str(row.get("f14") or "")
            chg = _f(row.get("f3")) or 0.0
            mcap = _f(row.get("f20"))
            if not code.isdigit() or "ST" in name.upper() or code.startswith(("4", "8")):
                continue
            if mcap is None or mcap < min_market_cap_yi * 1e8:
                continue
            # 近似涨停：主板≥9.7，双创≥19.5
            thr = 19.5 if code.startswith(("300", "301", "688", "689")) else 9.7
            if chg < thr:
                continue
            out.append(
                {
                    "code": code,
                    "name": name,
                    "market_cap_yi": round(mcap / 1e8, 2),
                    "change_pct": chg,
                    "price": _f(row.get("f2")),
                    "source": "clist",
                }
            )
        await asyncio.sleep(0.15)
    seen: set[str] = set()
    uniq: list[dict[str, Any]] = []
    for r in out:
        if r["code"] in seen:
            continue
        seen.add(r["code"])
        uniq.append(r)
    return uniq


async def fetch_money_flow_map(
    client: httpx.AsyncClient, code: str, *, limit: int = 40
) -> dict[str, float]:
    """新浪超大单净流入 r0_net（主力近似）。"""
    out: dict[str, float] = {}
    daima = sina_symbol(code)
    page_size = 60
    pages = max(1, (limit + page_size - 1) // page_size)
    for page in range(1, pages + 1):
        try:
            resp = await client.get(
                "https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/MoneyFlow.ssl_qsfx_zjlrqs",
                params={
                    "page": str(page),
                    "num": str(page_size),
                    "sort": "opendate",
                    "asc": "0",
                    "daima": daima,
                },
                timeout=25.0,
                headers={
                    **_HEADERS,
                    "Referer": "https://vip.stock.finance.sina.com.cn/",
                },
            )
            resp.raise_for_status()
            rows = resp.json()
            if not isinstance(rows, list) or not rows:
                break
            for row in rows:
                if not isinstance(row, dict):
                    continue
                d = str(row.get("opendate") or "")
                v = _f(row.get("r0_net"))
                if v is None:
                    v = _f(row.get("netamount"))
                if d and v is not None:
                    out[d] = v
            if len(out) >= limit:
                break
        except Exception:  # noqa: BLE001
            break
        await asyncio.sleep(float(SETTINGS.get("request_gap_ms", 120)) / 1000.0)
    return out


async def fetch_bars_for_code(
    client: httpx.AsyncClient, code: str, *, limit: int = 40
) -> list[dict[str, Any]]:
    return await fetch_daily_bars(client, code, limit=limit)
