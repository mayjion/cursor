"""个股投研报告：采集公开数据并组装 Kimi 风格结构化分析。"""

from __future__ import annotations

import asyncio
import time
import statistics
from datetime import date, datetime, timedelta, timezone
from typing import Any

import httpx

from app.collectors import (
    baidu_kline,
    eastmoney_finance,
    eastmoney_fundamentals,
    eastmoney_kline,
    eastmoney_quote,
    eastmoney_reports,
)
from app.db import store

_CACHE: dict[str, tuple[float, dict[str, Any]]] = {}
_CACHE_TTL = 900.0  # 15 分钟

_DISCLAIMER = (
    "以上分析基于公开数据自动生成，仅供个人研究学习，不构成投资建议。"
    "股市有风险，投资需谨慎。"
)


def _pct(v: float | None, digits: int = 1) -> str:
    if v is None:
        return "—"
    return f"{v:.{digits}f}%"


def _num(v: float | None, digits: int = 2) -> str:
    if v is None:
        return "—"
    return f"{v:.{digits}f}"


def _stars(n: int) -> str:
    n = max(1, min(5, int(n)))
    return "⭐" * n


def _yoy_delta(cur: float | None, prev: float | None) -> float | None:
    if cur is None or prev is None or prev == 0:
        return None
    return cur / prev - 1.0


def _find_yoy_quarter(
    quarters: list[dict[str, Any]],
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """取最新一期非年报，并匹配去年同期。"""
    non_annual = [q for q in quarters if q.get("report_type") and q["report_type"] != "年报"]
    if not non_annual:
        return None, None
    latest = non_annual[0]
    rd = latest.get("report_date") or ""
    if len(rd) < 10:
        return latest, None
    try:
        y = int(rd[:4]) - 1
        target = f"{y}{rd[4:]}"
    except ValueError:
        return latest, None
    prev = next((q for q in quarters if q.get("report_date") == target), None)
    return latest, prev


def _price_stats(bars: list[dict[str, Any]]) -> dict[str, Any]:
    if not bars:
        return {}
    closes = [float(b["close"]) for b in bars if b.get("close") is not None]
    if not closes:
        return {}
    high = max(closes)
    low = min(closes)
    last = closes[-1]
    pos = (last - low) / (high - low) if high > low else 0.5
    # 近 20 日均量 vs 前 60 日
    vols = [float(b["volume"]) for b in bars if b.get("volume")]
    turnover_hint = None
    if len(vols) >= 40:
        recent = sum(vols[-20:]) / 20
        base = sum(vols[-80:-20]) / max(1, len(vols[-80:-20]))
        if base > 0:
            turnover_hint = recent / base
    return {
        "last": round(last, 2),
        "high_52w": round(high, 2),
        "low_52w": round(low, 2),
        "range_position": round(pos, 3),
        "volume_ratio_20_60": None if turnover_hint is None else round(turnover_hint, 2),
        "bars_n": len(bars),
        "from": bars[0].get("trade_date"),
        "to": bars[-1].get("trade_date"),
    }


def _build_swot(
    *,
    profile: dict[str, Any],
    annual: list[dict[str, Any]],
    business: dict[str, Any],
    valuation: dict[str, Any] | None,
    research: dict[str, Any],
    quarter: dict[str, Any] | None,
) -> dict[str, list[str]]:
    s: list[str] = []
    w: list[str] = []
    o: list[str] = []
    t: list[str] = []

    industry = profile.get("industry") or ""
    if industry:
        s.append(f"所属行业：{industry}")

    if len(annual) >= 2:
        gm0 = annual[0].get("gross_margin")
        gm1 = annual[-1].get("gross_margin") if len(annual) >= 2 else None
        # annual is newest-first
        oldest_gm = annual[min(len(annual) - 1, 3)].get("gross_margin")
        if gm0 is not None and oldest_gm is not None and gm0 > oldest_gm + 2:
            s.append(
                f"毛利率持续改善（约 {_pct(oldest_gm)} → {_pct(gm0)}）"
            )
        nm0 = annual[0].get("net_margin")
        if nm0 is not None and nm0 >= 10:
            s.append(f"净利率较高（{_pct(nm0)}）")
        rev_yoy = annual[0].get("revenue_yoy")
        profit_yoy = annual[0].get("profit_yoy")
        if rev_yoy is not None and rev_yoy < 0:
            w.append(f"最新年报营收同比 {_pct(rev_yoy)}，规模承压")
        if profit_yoy is not None and profit_yoy > 10:
            s.append(f"最新年报归母净利同比 {_pct(profit_yoy)}")
        if rev_yoy is not None and rev_yoy < 0 and profit_yoy and profit_yoy > 0:
            s.append("营收收缩但利润仍增长，盈利质量改善迹象")

    products = business.get("by_product") or []
    growing = [p for p in products if (p.get("yoy") or 0) > 0.08]
    shrinking = [p for p in products if (p.get("yoy") or 0) < -0.08]
    if growing:
        names = "、".join(p["name"][:12] for p in growing[:3])
        o.append(f"增长业务：{names}")
    if shrinking:
        names = "、".join(p["name"][:12] for p in shrinking[:2])
        w.append(f"收缩业务：{names}")

    regions = business.get("by_region") or []
    overseas = [
        r
        for r in regions
        if any(k in str(r.get("name") or "") for k in ("境外", "海外", "国外", "港澳台"))
    ]
    if overseas:
        ratio = overseas[0].get("ratio")
        if ratio and ratio >= 0.25:
            w.append(f"海外收入占比较高（约 {_pct(ratio * 100)}），汇率波动敏感")
            t.append("汇率大幅波动可能冲击报表利润")

    review = str(business.get("review") or "") + str(profile.get("profile") or "")
    for kw, tip in (
        ("人工智能", "AI/智能化相关业务可能打开增长空间"),
        ("边缘计算", "边缘计算需求扩张带来增量机会"),
        ("液冷", "液冷/智算相关业务具备政策与需求催化"),
        ("云计算", "云计算产业链景气度变化影响订单"),
    ):
        if kw in review:
            o.append(tip)

    pe = (valuation or {}).get("pe_ttm")
    if pe is not None:
        if pe >= 45:
            t.append(f"估值偏高（PE-TTM {pe:.1f}x），业绩不及预期时回调风险大")
            w.append(f"PE-TTM {pe:.1f}x，已反映较多增长预期")
        elif pe <= 20:
            s.append(f"估值相对温和（PE-TTM {pe:.1f}x）")

    org_n = research.get("org_count") or 0
    if org_n <= 2:
        w.append(f"近一年机构覆盖偏少（约 {org_n} 家有研报）")
    elif org_n >= 5:
        s.append(f"机构关注度尚可（近一年约 {org_n} 家研报）")

    ratings = research.get("rating_dist") or {}
    buys = int(ratings.get("买入") or 0) + int(ratings.get("增持") or 0)
    sells = int(ratings.get("卖出") or 0) + int(ratings.get("减持") or 0)
    if buys > sells and buys > 0:
        o.append(f"近期机构评级偏多（买入/增持 {buys}）")
    if sells > buys:
        t.append("存在机构卖出/减持评级，需关注分歧")

    q_gm = (quarter or {}).get("gross_margin")
    if q_gm is not None and q_gm >= 30:
        s.append(f"最新季报毛利率 {_pct(q_gm)}，盈利能力维持高位")

    t.append("行业竞争加剧或价格战可能压制毛利率")
    if not o:
        o.append("关注主营构成中高增速细分与政策/产业催化")
    if not s:
        s.append("可参考多年财务与主营结构自行评估护城河")

    return {
        "strengths": s[:6],
        "weaknesses": w[:6],
        "opportunities": o[:6],
        "threats": t[:6],
    }


def _build_rating(
    *,
    annual: list[dict[str, Any]],
    valuation: dict[str, Any] | None,
    business: dict[str, Any],
    research: dict[str, Any],
    price_stats: dict[str, Any],
) -> dict[str, Any]:
    # 盈利能力
    profit_score = 3
    if annual:
        gm = annual[0].get("gross_margin")
        nm = annual[0].get("net_margin")
        roe = annual[0].get("roe")
        if gm is not None and gm >= 30:
            profit_score += 1
        if nm is not None and nm >= 12:
            profit_score += 1
        if roe is not None and roe < 8:
            profit_score -= 1
        if len(annual) >= 3:
            gms = [a.get("gross_margin") for a in annual[:4] if a.get("gross_margin") is not None]
            if len(gms) >= 2 and gms[0] > gms[-1] + 3:
                profit_score += 1
    profit_score = max(1, min(5, profit_score))

    # 成长性
    growth_score = 3
    if annual:
        ry = annual[0].get("revenue_yoy")
        py = annual[0].get("profit_yoy")
        if ry is not None and ry > 10:
            growth_score += 1
        elif ry is not None and ry < -5:
            growth_score -= 1
        if py is not None and py > 15:
            growth_score += 1
        elif py is not None and py < 0:
            growth_score -= 1
    products = business.get("by_product") or []
    if any((p.get("yoy") or 0) > 0.15 for p in products):
        growth_score += 1
    growth_score = max(1, min(5, growth_score))

    # 估值
    val_score = 3
    pe = (valuation or {}).get("pe_ttm")
    if pe is not None:
        if pe <= 20:
            val_score = 5
        elif pe <= 30:
            val_score = 4
        elif pe <= 40:
            val_score = 3
        elif pe <= 55:
            val_score = 2
        else:
            val_score = 1
    pb = (valuation or {}).get("pb_mrq")
    if pb is not None and pb > 5 and val_score > 1:
        val_score -= 1

    # 财务健康（公开字段有限，用经营现金流与扣非粗判）
    health_score = 4
    if annual:
        ocf = annual[0].get("ocf")
        np_ = annual[0].get("net_profit")
        if ocf is not None and np_ and np_ > 0 and ocf > 0:
            health_score = 5
        elif ocf is not None and ocf < 0:
            health_score = 2

    # 行业/关注度
    industry_score = 3
    if (research.get("org_count") or 0) >= 4:
        industry_score += 1
    if (research.get("upside") or 0) >= 0.2:
        industry_score += 1
    industry_score = max(1, min(5, industry_score))

    dims = [
        {
            "key": "profitability",
            "name": "盈利能力",
            "score": profit_score,
            "stars": _stars(profit_score),
            "note": "毛利率/净利率与改善趋势",
        },
        {
            "key": "growth",
            "name": "成长性",
            "score": growth_score,
            "stars": _stars(growth_score),
            "note": "营收净利增速与细分业务增长",
        },
        {
            "key": "valuation",
            "name": "估值水平",
            "score": val_score,
            "stars": _stars(val_score),
            "note": "PE/PB 相对高低",
        },
        {
            "key": "health",
            "name": "财务健康",
            "score": health_score,
            "stars": _stars(health_score),
            "note": "经营现金流与盈利匹配",
        },
        {
            "key": "position",
            "name": "市场关注",
            "score": industry_score,
            "stars": _stars(industry_score),
            "note": "机构覆盖与目标价空间",
        },
    ]
    avg = sum(d["score"] for d in dims) / len(dims)

    if val_score <= 2 and growth_score >= 3:
        stance = "基本面尚可，但估值偏高；更适合回调后逢低关注，不宜追高。"
        action = "观望/逢低"
    elif val_score >= 4 and profit_score >= 4:
        stance = "盈利与估值相对匹配，可纳入观察池，结合催化分批布局。"
        action = "积极观察"
    elif growth_score <= 2 and profit_score <= 2:
        stance = "成长与盈利信号偏弱，优先等待基本面拐点确认。"
        action = "谨慎"
    else:
        stance = "多空因素并存，建议跟踪季报兑现与估值消化节奏。"
        action = "中性跟踪"

    pos = price_stats.get("range_position")
    if pos is not None:
        if pos >= 0.75:
            stance += " 股价处于近两年偏高区间。"
        elif pos <= 0.35:
            stance += " 股价处于近两年偏低区间。"

    return {
        "dimensions": dims,
        "average": round(avg, 2),
        "stance": stance,
        "action": action,
    }


def _build_narrative(
    *,
    code: str,
    name: str,
    profile: dict[str, Any],
    quote: dict[str, Any],
    annual: list[dict[str, Any]],
    latest_q: dict[str, Any] | None,
    prev_q: dict[str, Any] | None,
    business: dict[str, Any],
    valuation: dict[str, Any] | None,
    research: dict[str, Any],
    rating: dict[str, Any],
    price_stats: dict[str, Any],
) -> list[dict[str, str]]:
    sections: list[dict[str, str]] = []

    mcap = (valuation or {}).get("market_cap")
    mcap_yi = None if mcap is None else round(mcap / 1e8, 1)
    price = quote.get("price") or (valuation or {}).get("close")
    overview = (
        f"{name}（{code}）"
        f"{'，' + (profile.get('industry') or '') if profile.get('industry') else ''}。"
    )
    if profile.get("list_date"):
        overview += f"上市日期 {profile['list_date']}。"
    if profile.get("profile"):
        brief = profile["profile"]
        if len(brief) > 220:
            brief = brief[:220] + "…"
        overview += brief
    meta = []
    if price is not None:
        meta.append(f"现价约 {_num(price)} 元")
    if mcap_yi is not None:
        meta.append(f"总市值约 {_num(mcap_yi, 1)} 亿元")
    if meta:
        overview += "截至数据时点：" + "，".join(meta) + "。"
    sections.append({"id": "overview", "title": "一、公司概况", "body": overview})

    if annual:
        lines = [
            "核心观察：对比近年年报，关注营收规模与利润、毛利率/净利率是否同步改善。"
        ]
        a0 = annual[0]
        if a0.get("revenue_yoy") is not None or a0.get("profit_yoy") is not None:
            lines.append(
                f"最新年报：营收同比 {_pct(a0.get('revenue_yoy'))}，"
                f"归母净利同比 {_pct(a0.get('profit_yoy'))}，"
                f"毛利率 {_pct(a0.get('gross_margin'))}，净利率 {_pct(a0.get('net_margin'))}。"
            )
        if len(annual) >= 2:
            old = annual[min(len(annual) - 1, 3)]
            if a0.get("gross_margin") is not None and old.get("gross_margin") is not None:
                lines.append(
                    f"毛利率从 {old.get('report_date', '')[:4]} 年的 "
                    f"{_pct(old.get('gross_margin'))} 变化至 "
                    f"{_pct(a0.get('gross_margin'))}。"
                )
        sections.append(
            {"id": "financials", "title": "二、财务分析", "body": "\n".join(lines)}
        )

    if latest_q:
        body = (
            f"最新季报（{latest_q.get('report_name') or latest_q.get('report_date')}）："
            f"营收 {_num(latest_q.get('revenue_yi'))} 亿元，"
            f"归母净利 {_num(latest_q.get('net_profit_yi'))} 亿元，"
            f"毛利率 {_pct(latest_q.get('gross_margin'))}。"
        )
        if prev_q:
            ry = _yoy_delta(latest_q.get("revenue"), prev_q.get("revenue"))
            py = _yoy_delta(latest_q.get("net_profit"), prev_q.get("net_profit"))
            body += (
                f" 对比去年同期：营收同比 {_pct(None if ry is None else ry * 100)}，"
                f"归母净利同比 {_pct(None if py is None else py * 100)}。"
            )
            body += " 若报表同比承压，需区分业务剥离、股份支付、汇兑等一次性因素。"
        sections.append(
            {"id": "quarter", "title": "二（附）、最新季报", "body": body}
        )

    products = business.get("by_product") or []
    if products:
        parts = []
        for p in products[:5]:
            yoy = p.get("yoy")
            yoy_s = "—" if yoy is None else f"{yoy * 100:+.1f}%"
            parts.append(
                f"{p['name']} 占比 {_pct(None if p.get('ratio') is None else p['ratio'] * 100)}"
                f"（同比 {yoy_s}）"
            )
        body = f"业务结构（{business.get('report_date') or '最新'}）：" + "；".join(parts) + "。"
        if business.get("review"):
            rev = business["review"]
            if len(rev) > 280:
                rev = rev[:280] + "…"
            body += "经营评述摘要：" + rev
        sections.append(
            {"id": "business", "title": "三、业务结构", "body": body}
        )

    val_lines = []
    if valuation:
        val_lines.append(
            f"PE(TTM) {_num(valuation.get('pe_ttm'), 1)}x · "
            f"PB {_num(valuation.get('pb_mrq'), 2)}x · "
            f"PS {_num(valuation.get('ps_ttm'), 2)}x"
        )
    if research.get("target_median"):
        src = "显式目标价" if research.get("target_source") == "aim" else "隐含目标价"
        val_lines.append(
            f"近一年研报{src}中位数约 {_num(research['target_median'])} 元"
            f"（{research.get('org_count') or 0} 家机构）"
            + (
                f"，相对现价上行空间 {_pct(None if research.get('upside') is None else research['upside'] * 100)}"
                if research.get("upside") is not None
                else ""
            )
        )
    forecasts = research.get("forecasts") or []
    if forecasts:
        f0 = forecasts[0]
        val_lines.append(
            f"一致预期参考：今年 EPS {_num(f0.get('eps'))}、PE {_num(f0.get('pe'), 1)}x"
            + (
                f"；明年 EPS {_num(f0.get('next_eps'))}"
                if f0.get("next_eps")
                else ""
            )
        )
    if pe := (valuation or {}).get("pe_ttm"):
        if pe >= 40:
            val_lines.append("当前估值偏高，需业绩兑现支撑；若增长放缓存在杀估值风险。")
    sections.append(
        {
            "id": "valuation",
            "title": "四、估值分析",
            "body": "\n".join(val_lines) if val_lines else "估值数据暂缺。",
        }
    )

    if price_stats:
        body = (
            f"近两年区间：低 {_num(price_stats.get('low_52w'))} / "
            f"高 {_num(price_stats.get('high_52w'))}，"
            f"现价位于区间约 {_pct(None if price_stats.get('range_position') is None else price_stats['range_position'] * 100, 0)} 分位。"
        )
        if price_stats.get("volume_ratio_20_60"):
            body += f" 近20日成交量相对此前约为 {price_stats['volume_ratio_20_60']} 倍。"
    else:
        body = (
            f"现价约 {_num(price)} 元"
            + (
                f"，日涨跌 {_pct(quote.get('change_pct'))}"
                if quote.get("change_pct") is not None
                else ""
            )
            + "。日K 暂不可用时，仅展示最新报价；连通行情源后可补全日线区间位置。"
        )
    sections.append({"id": "price", "title": "五、股价走势", "body": body})

    sections.append(
        {
            "id": "conclusion",
            "title": "六、综合判断",
            "body": (
                f"操作参考：{rating.get('action')}。"
                f"{rating.get('stance')}"
                " 重点跟踪：季报利润质量、高增速细分业务占比、估值消化与产业催化。"
            ),
        }
    )
    return sections


def _research_bundle(reports: list[dict[str, Any]], price: float | None) -> dict[str, Any]:
    if not reports:
        return {
            "reports": [],
            "org_count": 0,
            "report_count": 0,
            "rating_dist": {},
            "target_median": None,
            "upside": None,
            "forecasts": [],
        }
    # 放宽聚合门槛以展示分析用目标价
    agg = eastmoney_reports.aggregate_targets_by_code(
        [r for r in reports if r.get("target_price")],
        price_by_code={reports[0]["code"]: price} if price else None,
        min_upside=-10.0,
    )
    code = reports[0]["code"]
    info = agg.get(code) or {}
    cutoff = (date.today() - timedelta(days=30)).isoformat()
    rating_dist: dict[str, int] = {}
    for r in reports:
        if (r.get("publish_date") or "") < cutoff:
            continue
        key = str(r.get("rating") or "未评级").strip() or "未评级"
        rating_dist[key] = rating_dist.get(key, 0) + 1

    orgs = sorted({str(r.get("org") or "") for r in reports if r.get("org")})
    forecasts = []
    for r in reports[:8]:
        if r.get("predict_this_eps") or r.get("predict_next_eps"):
            forecasts.append(
                {
                    "org": r.get("org"),
                    "date": r.get("publish_date"),
                    "eps": r.get("predict_this_eps"),
                    "pe": r.get("predict_this_pe"),
                    "next_eps": r.get("predict_next_eps"),
                    "next_pe": r.get("predict_next_pe"),
                    "rating": r.get("rating"),
                }
            )

    upside = info.get("upside")
    if upside is None and info.get("target_median") and price and price > 0:
        upside = info["target_median"] / price - 1.0

    # 一致预期 EPS：取有预测的研报中位数
    this_eps = [float(f["eps"]) for f in forecasts if f.get("eps")]
    next_eps = [float(f["next_eps"]) for f in forecasts if f.get("next_eps")]
    cons_this = statistics.median(this_eps) if this_eps else None
    cons_next = statistics.median(next_eps) if next_eps else None
    eps_growth = None
    if cons_this and cons_this > 0 and cons_next is not None:
        eps_growth = cons_next / cons_this - 1.0

    return {
        "reports": reports[:12],
        "org_count": len(orgs),
        "orgs": orgs[:15],
        "report_count": len(reports),
        "rating_dist": rating_dist,
        "target_median": info.get("target_median"),
        "target_min": info.get("target_min"),
        "target_max": info.get("target_max"),
        "target_source": info.get("target_source"),
        "price": price,
        "upside": None if upside is None else round(upside, 4),
        "forecasts": forecasts[:6],
        "consensus_eps_this": None if cons_this is None else round(cons_this, 4),
        "consensus_eps_next": None if cons_next is None else round(cons_next, 4),
        "consensus_eps_growth": None if eps_growth is None else round(eps_growth, 4),
        "latest_date": info.get("latest_date") or (reports[0].get("publish_date") if reports else None),
        "latest_rating": info.get("latest_rating") or (reports[0].get("rating") if reports else None),
    }


def _chart_payload(
    annual: list[dict[str, Any]],
    bars: list[dict[str, Any]],
    business: dict[str, Any],
    research: dict[str, Any],
) -> dict[str, Any]:
    years = list(reversed(annual[:5]))
    # 价格：约两年，降采样
    price_bars = bars[-520:] if len(bars) > 520 else bars
    step = max(1, len(price_bars) // 180)
    sampled = price_bars[::step]
    if price_bars and sampled[-1] != price_bars[-1]:
        sampled.append(price_bars[-1])

    products = business.get("by_product") or []
    return {
        "annual_years": [str(a.get("report_date") or "")[:4] for a in years],
        "annual_revenue_yi": [a.get("revenue_yi") for a in years],
        "annual_profit_yi": [a.get("net_profit_yi") for a in years],
        "annual_revenue_yoy": [a.get("revenue_yoy") for a in years],
        "annual_profit_yoy": [a.get("profit_yoy") for a in years],
        "annual_gross_margin": [a.get("gross_margin") for a in years],
        "annual_net_margin": [a.get("net_margin") for a in years],
        "price_dates": [b.get("trade_date") for b in sampled],
        "price_close": [b.get("close") for b in sampled],
        "price_high": [b.get("high") for b in sampled],
        "price_low": [b.get("low") for b in sampled],
        "price_volume": [b.get("volume") for b in sampled],
        "biz_names": [p.get("name") for p in products],
        "biz_ratios": [
            None if p.get("ratio") is None else round(p["ratio"] * 100, 1) for p in products
        ],
        "biz_yoys": [
            None if p.get("yoy") is None else round(p["yoy"] * 100, 1) for p in products
        ],
        "rating_labels": list((research.get("rating_dist") or {}).keys()),
        "rating_values": list((research.get("rating_dist") or {}).values()),
        "eps_this": research.get("consensus_eps_this"),
        "eps_next": research.get("consensus_eps_next"),
        "target_low": research.get("target_min"),
        "target_mid": research.get("target_median"),
        "target_high": research.get("target_max"),
    }


def _trend_from_yoy(yoy: float | None, *, up: float = 5.0, down: float = -5.0) -> dict[str, Any]:
    """yoy 为百分数数值，如 12.3 表示 12.3%。"""
    if yoy is None:
        return {"signal": "unknown", "label": "暂无", "yoy": None}
    if yoy >= up:
        return {"signal": "up", "label": "增长", "yoy": round(yoy, 1)}
    if yoy <= down:
        return {"signal": "down", "label": "下滑", "yoy": round(yoy, 1)}
    return {"signal": "flat", "label": "平稳", "yoy": round(yoy, 1)}


def _trend_from_margin_delta(delta: float | None) -> dict[str, Any]:
    if delta is None:
        return {"signal": "unknown", "label": "暂无", "delta": None}
    if delta >= 1.0:
        return {"signal": "up", "label": "改善", "delta": round(delta, 1)}
    if delta <= -1.0:
        return {"signal": "down", "label": "走弱", "delta": round(delta, 1)}
    return {"signal": "flat", "label": "持平", "delta": round(delta, 1)}


_PROSPECT_KEYWORDS: list[tuple[str, str]] = [
    ("人工智能", "AI"),
    ("边缘计算", "边缘计算"),
    ("边缘AI", "边缘AI"),
    ("液冷", "液冷"),
    ("智算", "智算"),
    ("云计算", "云计算"),
    ("安全", "安全增值"),
    ("CDN", "CDN"),
    ("数据中心", "数据中心"),
    ("新能源", "新能源"),
    ("半导体", "半导体"),
    ("机器人", "机器人"),
]


def _build_decision_dashboard(
    *,
    annual: list[dict[str, Any]],
    business: dict[str, Any],
    valuation: dict[str, Any] | None,
    research: dict[str, Any],
    price_stats: dict[str, Any],
    profile: dict[str, Any],
    rating: dict[str, Any],
) -> dict[str, Any]:
    """一眼决策：趋势灯 + 估值三态 + 前景标签 + 研报预期。"""
    a0 = annual[0] if annual else {}
    # 毛利率：最新 vs 3年前（或最早）
    gm_delta = None
    if annual:
        newest_gm = a0.get("gross_margin")
        oldest = annual[min(len(annual) - 1, 3)]
        if newest_gm is not None and oldest.get("gross_margin") is not None:
            gm_delta = float(newest_gm) - float(oldest["gross_margin"])

    rev_trend = _trend_from_yoy(a0.get("revenue_yoy"))
    profit_trend = _trend_from_yoy(a0.get("profit_yoy"))
    margin_trend = _trend_from_margin_delta(gm_delta)

    pe = (valuation or {}).get("pe_ttm")
    pb = (valuation or {}).get("pb_mrq")
    upside = research.get("upside")
    range_pos = price_stats.get("range_position")

    # 估值三态
    score = 0  # 正=便宜倾向，负=贵
    reasons: list[str] = []
    if pe is not None:
        if pe <= 20:
            score += 2
            reasons.append(f"PE {pe:.1f}x 偏低")
        elif pe <= 30:
            score += 1
            reasons.append(f"PE {pe:.1f}x 温和")
        elif pe >= 45:
            score -= 2
            reasons.append(f"PE {pe:.1f}x 偏高")
        elif pe >= 35:
            score -= 1
            reasons.append(f"PE {pe:.1f}x 较高")
        else:
            reasons.append(f"PE {pe:.1f}x")
    if upside is not None:
        if upside >= 0.30:
            score += 2
            reasons.append(f"目标价上行 {upside * 100:.0f}%")
        elif upside >= 0.15:
            score += 1
            reasons.append(f"目标价上行 {upside * 100:.0f}%")
        elif upside < 0.05:
            score -= 1
            reasons.append(f"目标价空间有限 {upside * 100:.0f}%")
    if range_pos is not None:
        if range_pos <= 0.30:
            score += 1
            reasons.append("股价处近两年偏低区间")
        elif range_pos >= 0.75:
            score -= 1
            reasons.append("股价处近两年偏高区间")

    if score >= 2:
        val_state, val_label = "cheap", "低估"
    elif score <= -2:
        val_state, val_label = "expensive", "偏贵"
    else:
        val_state, val_label = "fair", "合理"

    # 机构灯
    dist = research.get("rating_dist") or {}
    buys = int(dist.get("买入") or 0) + int(dist.get("增持") or 0)
    sells = int(dist.get("卖出") or 0) + int(dist.get("减持") or 0)
    holds = int(dist.get("持有") or 0) + int(dist.get("中性") or 0)
    if research.get("report_count", 0) == 0:
        research_signal = {"signal": "unknown", "label": "无覆盖", "buys": 0, "sells": 0, "holds": 0}
    elif buys > sells:
        research_signal = {"signal": "up", "label": "偏多", "buys": buys, "sells": sells, "holds": holds}
    elif sells > buys:
        research_signal = {"signal": "down", "label": "偏空", "buys": buys, "sells": sells, "holds": holds}
    else:
        research_signal = {"signal": "flat", "label": "分歧", "buys": buys, "sells": sells, "holds": holds}

    products = business.get("by_product") or []
    engines = [
        {
            "name": p["name"],
            "ratio": p.get("ratio"),
            "yoy": p.get("yoy"),
            "role": "engine",
        }
        for p in products
        if (p.get("yoy") or 0) >= 0.08
    ]
    shrinking = [
        {
            "name": p["name"],
            "ratio": p.get("ratio"),
            "yoy": p.get("yoy"),
            "role": "shrink",
        }
        for p in products
        if (p.get("yoy") or 0) <= -0.08
    ]

    text_blob = f"{business.get('review') or ''} {profile.get('profile') or ''} {profile.get('industry') or ''}"
    tags: list[str] = []
    for kw, tag in _PROSPECT_KEYWORDS:
        if kw in text_blob and tag not in tags:
            tags.append(tag)
        if len(tags) >= 4:
            break
    if not tags and profile.get("industry"):
        tags.append(str(profile["industry"])[:8])

    # 行业/主业前景灯（轻量规则）
    if engines and (profit_trend["signal"] == "up" or margin_trend["signal"] == "up"):
        outlook = {"signal": "up", "label": "景气向上", "note": "增长业务扩张且盈利改善"}
    elif shrinking and rev_trend["signal"] == "down" and not engines:
        outlook = {"signal": "down", "label": "承压", "note": "主业收缩且缺少增长引擎"}
    elif engines and rev_trend["signal"] == "down":
        outlook = {"signal": "flat", "label": "结构分化", "note": "总量承压但细分引擎增长"}
    elif rev_trend["signal"] == "up" and profit_trend["signal"] == "up":
        outlook = {"signal": "up", "label": "同步扩张", "note": "营收与利润同向增长"}
    else:
        outlook = {"signal": "flat", "label": "中性跟踪", "note": "等待业绩与产业催化确认"}

    # 趋势结论徽章
    def _badge(rev: dict, profit: dict, margin: dict) -> str:
        parts = []
        if rev["signal"] == "down" and profit["signal"] == "up":
            parts.append("营收承压·利润改善")
        elif rev["signal"] == "up" and profit["signal"] == "up":
            parts.append("量利齐升")
        elif rev["signal"] == "down" and profit["signal"] == "down":
            parts.append("量利双降")
        else:
            parts.append(f"营收{rev['label']}·利润{profit['label']}")
        parts.append(f"毛利{margin['label']}")
        return " · ".join(parts)

    lights = [
        {
            "key": "revenue",
            "name": "营收",
            "icon": "apartment",
            **rev_trend,
            "detail": None if rev_trend["yoy"] is None else f"同比 {rev_trend['yoy']:+.1f}%",
        },
        {
            "key": "profit",
            "name": "利润",
            "icon": "payments",
            **profit_trend,
            "detail": None if profit_trend["yoy"] is None else f"同比 {profit_trend['yoy']:+.1f}%",
        },
        {
            "key": "margin",
            "name": "毛利率",
            "icon": "percent",
            **margin_trend,
            "detail": (
                None
                if margin_trend.get("delta") is None
                else f"{margin_trend['delta']:+.1f}pct"
            ),
        },
        {
            "key": "valuation",
            "name": "估值",
            "icon": "sell",
            "signal": {"cheap": "up", "expensive": "down", "fair": "flat"}[val_state],
            "label": val_label,
            "detail": reasons[0] if reasons else None,
        },
        {
            "key": "research",
            "name": "机构",
            "icon": "groups",
            **research_signal,
            "detail": f"买{buys}/持{holds}/卖{sells}" if research.get("report_count") else "近一月无评级",
        },
    ]

    return {
        "lights": lights,
        "trend_badge": _badge(rev_trend, profit_trend, margin_trend),
        "valuation": {
            "state": val_state,
            "label": val_label,
            "pe_ttm": pe,
            "pb_mrq": pb,
            "ps_ttm": (valuation or {}).get("ps_ttm"),
            "upside": upside,
            "range_position": range_pos,
            "reasons": reasons[:4],
            "target_min": research.get("target_min"),
            "target_median": research.get("target_median"),
            "target_max": research.get("target_max"),
            "price": research.get("price") or price_stats.get("last"),
        },
        "outlook": outlook,
        "prospect_tags": tags,
        "engines": engines[:4],
        "shrinking": shrinking[:3],
        "consensus": {
            "eps_this": research.get("consensus_eps_this"),
            "eps_next": research.get("consensus_eps_next"),
            "eps_growth": research.get("consensus_eps_growth"),
            "org_count": research.get("org_count") or 0,
            "report_count": research.get("report_count") or 0,
        },
        "action": rating.get("action"),
        "stance": rating.get("stance"),
    }


async def build_stock_analysis(code: str, *, force: bool = False) -> dict[str, Any]:
    code = str(code).zfill(6)
    if not code.isdigit() or len(code) != 6:
        raise ValueError("invalid stock code")

    now = time.time()
    if not force and code in _CACHE:
        ts, payload = _CACHE[code]
        if now - ts < _CACHE_TTL:
            return payload

    gap = 0.12

    async def _sleep() -> None:
        await asyncio.sleep(gap)

    profile = await eastmoney_finance.fetch_company_profile(code)
    await _sleep()
    annual = await eastmoney_finance.fetch_main_financials(code, report_type="年报", limit=6)
    await _sleep()
    quarters = await eastmoney_finance.fetch_main_financials(code, report_type=None, limit=16)
    await _sleep()
    business = await eastmoney_finance.fetch_business_composition(code)
    await _sleep()
    valuation = await eastmoney_fundamentals.fetch_valuation_snapshot(code)
    await _sleep()
    growth = await eastmoney_fundamentals.fetch_growth_snapshot(code)
    await _sleep()
    reports = await eastmoney_reports.fetch_reports_for_code(code, days=365)

    quote: dict[str, Any] = {"code": code, "name": profile.get("name") or code}
    bars: list[dict[str, Any]] = []
    async with httpx.AsyncClient(
        headers={
            "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
            "Referer": "https://quote.eastmoney.com/",
        }
    ) as client:
        try:
            quote = await eastmoney_quote.fetch_quote(client, code)
        except Exception:  # noqa: BLE001
            pass
        await _sleep()
        try:
            bars = await eastmoney_kline.fetch_daily_bars(client, code, limit=560)
        except Exception:  # noqa: BLE001
            bars = []
        if not bars:
            try:
                bars = await baidu_kline.fetch_daily_bars(client, code, limit=560)
            except Exception:  # noqa: BLE001
                bars = []
    if not bars:
        # 本地库回退（若此前采集过）
        bars = store.list_bars(code, limit=560)

    name = quote.get("name") or profile.get("name") or code
    price = quote.get("price") or (valuation or {}).get("close")
    research = _research_bundle(reports, price)
    latest_q, prev_q = _find_yoy_quarter(quarters)
    price_stats = _price_stats(bars)
    swot = _build_swot(
        profile=profile,
        annual=annual,
        business=business,
        valuation=valuation,
        research=research,
        quarter=latest_q,
    )
    rating = _build_rating(
        annual=annual,
        valuation=valuation,
        business=business,
        research=research,
        price_stats=price_stats,
    )
    sections = _build_narrative(
        code=code,
        name=name,
        profile=profile,
        quote=quote,
        annual=annual,
        latest_q=latest_q,
        prev_q=prev_q,
        business=business,
        valuation=valuation,
        research=research,
        rating=rating,
        price_stats=price_stats,
    )
    charts = _chart_payload(annual, bars, business, research)
    dashboard = _build_decision_dashboard(
        annual=annual,
        business=business,
        valuation=valuation,
        research=research,
        price_stats=price_stats,
        profile=profile,
        rating=rating,
    )

    # 季报同比表
    q_compare = None
    if latest_q and prev_q:
        q_compare = {
            "latest": latest_q,
            "previous": prev_q,
            "revenue_yoy": _yoy_delta(latest_q.get("revenue"), prev_q.get("revenue")),
            "profit_yoy": _yoy_delta(latest_q.get("net_profit"), prev_q.get("net_profit")),
            "deduct_yoy": _yoy_delta(
                latest_q.get("deduct_net_profit"), prev_q.get("deduct_net_profit")
            ),
            "ocf_yoy": _yoy_delta(latest_q.get("ocf"), prev_q.get("ocf")),
            "gross_margin_delta": (
                None
                if latest_q.get("gross_margin") is None or prev_q.get("gross_margin") is None
                else round(latest_q["gross_margin"] - prev_q["gross_margin"], 2)
            ),
        }

    # 风险/催化：结合 dashboard 动态裁剪
    risks: list[str] = []
    if dashboard["valuation"]["state"] == "expensive":
        risks.append("估值偏高，业绩不及预期易回调")
    if dashboard["outlook"]["signal"] == "down":
        risks.append("主业收缩，增长引擎不足")
    risks.extend(
        [
            "行业竞争/价格战压制毛利率",
            "汇率或股份支付等一次性因素扰动利润",
        ]
    )
    risks = risks[:4]

    catalysts: list[str] = [
        f"增长引擎：{e['name']}" for e in (dashboard.get("engines") or [])[:2]
    ]
    if dashboard["valuation"]["state"] == "cheap":
        catalysts.append("估值处相对低位，关注业绩兑现")
    catalysts.extend(["季报利润质量改善", "机构上调盈利预测/目标价"])
    catalysts = catalysts[:4]

    payload = {
        "code": code,
        "name": name,
        "as_of": datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M"),
        "overview": profile,
        "quote": {
            "price": price,
            "change_pct": quote.get("change_pct"),
            "amount": quote.get("amount"),
            "market_cap": (valuation or {}).get("market_cap"),
            "market_cap_yi": (
                None
                if not (valuation or {}).get("market_cap")
                else round(valuation["market_cap"] / 1e8, 1)  # type: ignore[index]
            ),
        },
        "dashboard": dashboard,
        "financials": {
            "annual": list(reversed(annual[:5])),
            "annual_newest_first": annual[:5],
            "latest_quarter": latest_q,
            "prev_year_quarter": prev_q,
            "quarter_compare": q_compare,
            "growth_snapshot": growth,
        },
        "business": {
            **business,
            "engines": dashboard.get("engines") or [],
            "shrinking": dashboard.get("shrinking") or [],
            "prospect_tags": dashboard.get("prospect_tags") or [],
        },
        "valuation": valuation,
        "research": research,
        "price": {"stats": price_stats, "bars_n": len(bars)},
        "swot": swot,
        "rating": rating,
        "sections": sections,
        "charts": charts,
        "risks": risks,
        "catalysts": catalysts,
        "disclaimer": _DISCLAIMER,
    }
    _CACHE[code] = (now, payload)
    return payload
