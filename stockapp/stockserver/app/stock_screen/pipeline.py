"""A股初选流水线：高管增持 ∩ 研报上行 ∩ 估值偏低 → Top 池。"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.collectors import (
    eastmoney_insider,
    eastmoney_kline,
    eastmoney_quote,
    eastmoney_reports,
    sina_stock,
)
from app.config import SETTINGS, load_yaml
from app.db import store
from app.stock_screen.analyze import build_analysis, is_st_name


def screen_cfg() -> dict[str, Any]:
    return load_yaml("stock_screen.yaml")


async def _fetch_prices(codes: list[str]) -> dict[str, dict[str, Any]]:
    """东财个股快照优先，失败则新浪批量行情。"""
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    out: dict[str, dict[str, Any]] = {}
    async with httpx.AsyncClient(
        headers={
            "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
            "Referer": "https://quote.eastmoney.com/",
        }
    ) as client:
        for i, code in enumerate(codes):
            try:
                q = await eastmoney_quote.fetch_quote(client, code)
                if q.get("price") is not None:
                    out[code] = q
            except Exception:  # noqa: BLE001
                pass
            if i + 1 < len(codes) and gap:
                await asyncio.sleep(gap)
    missing = [c for c in codes if c not in out]
    if missing:
        try:
            sina_q = await sina_stock.fetch_quotes(missing)
            out.update(sina_q)
        except Exception:  # noqa: BLE001
            pass
    return out


async def _refresh_candidate_bars(codes: list[str], *, limit: int) -> dict[str, int]:
    """东财日K优先；缺口用新浪日K回退。"""
    em_n = 0
    try:
        em_n = await eastmoney_kline.refresh_bars(codes, limit=limit)
    except Exception:  # noqa: BLE001
        em_n = 0
    need = [c for c in codes if len(store.list_bars(c, limit=limit)) < 60]
    sina_n = 0
    if need:
        sina_n = await sina_stock.refresh_bars(need, limit=limit)
    return {"eastmoney_bars": em_n, "sina_bars": sina_n, "filled_codes": len(codes) - len(need) + (len(need) if sina_n else 0)}


async def run_stock_screen(*, force_bars: bool = True) -> dict[str, Any]:
    cfg = screen_cfg()
    days = int(cfg.get("insider_days", 90))
    min_upside = float(cfg.get("min_upside", 0.30))
    max_pct = float(cfg.get("max_price_percentile", 0.35))
    pool_size = int(cfg.get("pool_size", 30))
    exclude_st = bool(cfg.get("exclude_st", True))
    report_pages = int(cfg.get("report_max_pages", 40))
    report_ps = int(cfg.get("report_page_size", 100))
    insider_ps = int(cfg.get("insider_page_size", 500))

    # 1) 高管增持
    insider_events = await eastmoney_insider.fetch_executive_increases(
        days=days, page_size=insider_ps, max_pages=40
    )
    insider_by = eastmoney_insider.aggregate_insider_by_code(insider_events)

    # 2) 研报目标价（先不过滤上行，等有现价）
    reports = await eastmoney_reports.fetch_reports_with_targets(
        days=days, page_size=report_ps, max_pages=report_pages
    )
    # 先粗交：两边都有的代码
    report_codes = {r["code"] for r in reports}
    insider_codes = set(insider_by.keys())
    intersect = sorted(insider_codes & report_codes)

    # 名称映射
    name_map = {c: insider_by[c].get("name") or c for c in intersect}
    for r in reports:
        if r["code"] in name_map and r.get("name"):
            name_map[r["code"]] = r["name"]

    if exclude_st:
        intersect = [c for c in intersect if not is_st_name(name_map.get(c, ""))]

    # 3) 现价
    quotes = await _fetch_prices(intersect) if intersect else {}
    price_by = {
        c: float(q["price"])
        for c, q in quotes.items()
        if q.get("price") is not None and float(q["price"]) > 0
    }

    research_by = eastmoney_reports.aggregate_targets_by_code(
        reports, price_by_code=price_by, min_upside=min_upside
    )
    # 再次交集：有增持且上行达标
    candidates = sorted(set(intersect) & set(research_by.keys()))

    # 4) 日K + 估值（东财失败时新浪回退）
    bar_stats: dict[str, Any] = {}
    if force_bars and candidates:
        bar_stats = await _refresh_candidate_bars(
            candidates, limit=max(280, int(cfg.get("price_lookback", 250)) + 30)
        )

    analyzed: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    for code in candidates:
        bars = store.list_bars(code, limit=400)
        q = quotes.get(code) or {}
        name = str(q.get("name") or name_map.get(code) or code)
        # 报价仍缺时，用日K最新收盘
        price = q.get("price")
        if price is None and bars and bars[-1].get("close") is not None:
            price = float(bars[-1]["close"])
            q = {**q, "price": price, "name": name}
        row = build_analysis(
            code=code,
            name=name,
            price=price,
            change_pct=q.get("change_pct"),
            bars=bars,
            insider=insider_by.get(code),
            research=research_by.get(code),
            cfg=cfg,
        )
        # 有了现价后复核上行空间（研报聚合阶段可能无价）
        res = row.get("research") or {}
        upside = res.get("upside")
        if upside is None and price and res.get("target_median"):
            upside = float(res["target_median"]) / float(price) - 1.0
            res["upside"] = round(upside, 4)
            res["price"] = price
            row["research"] = res
            row["checks"]["research_upside"] = {
                "ok": upside >= min_upside,
                "detail": f"目标价中枢 {res.get('target_median')}，上行 {upside*100:.1f}%（≥{min_upside*100:.0f}%）",
            }
            row["passed"] = all(c["ok"] for c in row["checks"].values())
        if upside is not None and upside < min_upside:
            row["passed"] = False
        if row["passed"]:
            analyzed.append(row)
        else:
            rejected.append(
                {
                    "code": code,
                    "name": name,
                    "checks": row["checks"],
                    "price_percentile": (row.get("valuation") or {}).get("price_percentile"),
                }
            )

    analyzed.sort(key=lambda x: float(x.get("score") or 0), reverse=True)
    pool = analyzed[:pool_size]

    # 列表精简字段
    pool_list = []
    for r in pool:
        res = r.get("research") or {}
        ins = r.get("insider") or {}
        val = r.get("valuation") or {}
        pool_list.append(
            {
                "code": r["code"],
                "name": r["name"],
                "price": r.get("price"),
                "change_pct": r.get("change_pct"),
                "score": r.get("score"),
                "signal": r.get("signal"),
                "price_percentile": val.get("price_percentile"),
                "target_median": res.get("target_median"),
                "upside": res.get("upside"),
                "insider_events": ins.get("event_count"),
                "insider_amount": ins.get("total_amount"),
                "report_count": res.get("report_count"),
                "org_count": res.get("org_count"),
            }
        )

    payload = {
        "updated_at": store.utc_now_iso(),
        "cfg": {
            "insider_days": days,
            "min_upside": min_upside,
            "max_price_percentile": max_pct,
            "pool_size": pool_size,
        },
        "stats": {
            "insider_events": len(insider_events),
            "insider_codes": len(insider_by),
            "reports_with_target": len(reports),
            "intersect_before_price": len(intersect),
            "upside_pass": len(research_by),
            "valuation_pass": len(analyzed),
            "pool_n": len(pool),
            "rejected_valuation": len(rejected),
            "bars": bar_stats,
        },
        "pool": pool_list,
        "details": {r["code"]: r for r in pool},
        "disclosure": cfg.get("disclosure"),
        "data_policy": "public_only",
    }
    store.save_json_meta("stock_screen_pool", payload)
    store.set_meta("last_stock_screen_at", payload["updated_at"])
    return payload
