"""A股初选：分析画像与综合评分。"""

from __future__ import annotations

from typing import Any

from app.factors.engine import max_drawdown, momentum, price_percentile, volatility


def is_st_name(name: str) -> bool:
    n = (name or "").upper()
    return "ST" in n or "退" in (name or "")


def valuation_block(bars: list[dict[str, Any]], *, lookback: int = 250) -> dict[str, Any]:
    pct = price_percentile(bars, lookback)
    mom20 = momentum(bars, 20)
    mom60 = momentum(bars, 60)
    dd = max_drawdown(bars, 60)
    vol = volatility(bars, 20)
    close = None
    if bars and bars[-1].get("close") is not None:
        close = float(bars[-1]["close"])
    return {
        "price_percentile": None if pct is None else round(pct, 4),
        "mom20": None if mom20 is None else round(mom20, 4),
        "mom60": None if mom60 is None else round(mom60, 4),
        "drawdown60": None if dd is None else round(dd, 4),
        "volatility": None if vol is None else round(vol, 4),
        "close": close,
        "bars_n": len(bars),
    }


def _score_pe(pe: float | None) -> float:
    if pe is None:
        return 40.0
    if pe <= 0:
        return 15.0
    # 甜区约 8–25 高分，25–40 尚可，>60 差
    if 8 <= pe <= 25:
        return 90.0 - abs(pe - 15) * 1.5
    if 25 < pe <= 40:
        return 75.0 - (pe - 25) * 1.2
    if 5 <= pe < 8:
        return 70.0 + (pe - 5) * 5.0
    if pe < 5:
        return 55.0
    if pe <= 60:
        return max(25.0, 55.0 - (pe - 40) * 1.5)
    return 15.0


def _score_growth(profit_yoy: float | None, revenue_yoy: float | None) -> float:
    # 输入为百分比，如 12.3
    if profit_yoy is None and revenue_yoy is None:
        return 40.0
    p = profit_yoy if profit_yoy is not None else (revenue_yoy or 0.0) * 0.8
    r = revenue_yoy if revenue_yoy is not None else p * 0.6
    # 净利增速主权重
    if p >= 40:
        ps = 95.0
    elif p >= 20:
        ps = 80.0 + (p - 20) * 0.75
    elif p >= 0:
        ps = 50.0 + p * 1.5
    elif p >= -20:
        ps = 35.0 + p * 0.75
    else:
        ps = max(5.0, 20.0 + p * 0.3)
    if r >= 20:
        rs = 85.0
    elif r >= 0:
        rs = 50.0 + r * 1.5
    else:
        rs = max(10.0, 40.0 + r)
    return max(0.0, min(100.0, ps * 0.7 + rs * 0.3))


def _score_pb(pb: float | None) -> float:
    if pb is None:
        return 45.0
    if pb <= 0:
        return 20.0
    if pb <= 1.0:
        return 92.0
    if pb <= 2.0:
        return 85.0 - (pb - 1.0) * 15.0
    if pb <= 3.5:
        return 70.0 - (pb - 2.0) * 12.0
    if pb <= 5.0:
        return 50.0 - (pb - 3.5) * 10.0
    return max(10.0, 35.0 - (pb - 5.0) * 5.0)


def _score_peg(peg: float | None, profit_yoy: float | None) -> float:
    if profit_yoy is not None and profit_yoy <= 0:
        return 25.0
    if peg is None:
        return 45.0
    if peg <= 0:
        return 25.0
    if peg < 0.8:
        return 95.0
    if peg < 1.2:
        return 85.0
    if peg < 1.8:
        return 70.0
    if peg < 2.5:
        return 50.0
    if peg < 4.0:
        return 35.0
    return 15.0


def fundamental_valuation_score(fund: dict[str, Any] | None) -> tuple[float, dict[str, Any]]:
    """综合 PE/增速/PB/PEG → 0-100 估值分。"""
    fund = fund or {}
    pe = fund.get("pe_ttm")
    pb = fund.get("pb_mrq")
    profit_yoy = fund.get("profit_yoy")
    revenue_yoy = fund.get("revenue_yoy")
    peg = fund.get("peg")
    pe_s = _score_pe(None if pe is None else float(pe))
    g_s = _score_growth(
        None if profit_yoy is None else float(profit_yoy),
        None if revenue_yoy is None else float(revenue_yoy),
    )
    pb_s = _score_pb(None if pb is None else float(pb))
    peg_s = _score_peg(
        None if peg is None else float(peg),
        None if profit_yoy is None else float(profit_yoy),
    )
    total = pe_s * 0.35 + g_s * 0.35 + pb_s * 0.20 + peg_s * 0.10
    parts = {
        "pe_score": round(pe_s, 1),
        "growth_score": round(g_s, 1),
        "pb_score": round(pb_s, 1),
        "peg_score": round(peg_s, 1),
        "pe_ttm": pe,
        "pb_mrq": pb,
        "profit_yoy": profit_yoy,
        "revenue_yoy": revenue_yoy,
        "peg": peg,
    }
    return round(max(0.0, min(100.0, total)), 1), parts


def score_candidate(
    *,
    valuation_score: float | None,
    price_pct: float | None,
    upside: float | None,
    ownership: dict[str, Any] | None,
    research: dict[str, Any] | None,
    vol: float | None,
    dd: float | None,
    weights: dict[str, float],
) -> tuple[float, str, dict[str, float]]:
    """返回 (0-100分, 信号灯, 分项)。"""
    # 低估：综合估值分；一年价格分位仅弱修正
    if valuation_score is None:
        undervalue = 40.0
    else:
        undervalue = float(valuation_score)
    if price_pct is not None:
        # 分位低略加分，高略减（最多 ±8）
        undervalue = max(0.0, min(100.0, undervalue + (0.45 - float(price_pct)) * 16.0))

    if upside is None or upside <= 0:
        upside_s = 20.0
    else:
        upside_s = max(0.0, min(100.0, 40.0 + upside * 80.0))

    ownership = ownership or {}
    if ownership.get("strength") is not None:
        insider_s = float(ownership["strength"])
    else:
        n = int(ownership.get("event_count") or 0)
        amt = float(ownership.get("total_amount") or 0)
        insider_s = max(0.0, min(100.0, 35.0 + n * 12.0 + min(30.0, amt / 1e6 * 3.0)))

    research = research or {}
    rc = int(research.get("report_count") or 0)
    oc = int(research.get("org_count") or 0)
    research_s = max(0.0, min(100.0, 30.0 + rc * 10.0 + oc * 8.0))
    if research.get("target_source") == "aim":
        research_s = min(100.0, research_s + 8.0)

    risk_s = 70.0
    if vol is not None:
        risk_s -= max(0.0, (vol - 0.25) / 0.35 * 40.0)
    if dd is not None:
        risk_s -= max(0.0, (-dd - 0.10) / 0.25 * 35.0)
    risk_s = max(0.0, min(100.0, risk_s))

    parts = {
        "undervalue": round(undervalue, 1),
        "upside": round(upside_s, 1),
        "insider": round(insider_s, 1),
        "research": round(research_s, 1),
        "risk": round(risk_s, 1),
    }
    w_u = float(weights.get("undervalue", 0.30))
    w_up = float(weights.get("upside", 0.25))
    w_i = float(weights.get("insider", 0.20))
    w_r = float(weights.get("research", 0.15))
    w_risk = float(weights.get("risk", 0.10))
    total_w = w_u + w_up + w_i + w_r + w_risk
    if total_w <= 0:
        total_w = 1.0
    score = (
        undervalue * w_u
        + upside_s * w_up
        + insider_s * w_i
        + research_s * w_r
        + risk_s * w_risk
    ) / total_w
    score = round(max(0.0, min(100.0, score)), 1)
    if score >= 70:
        signal = "green"
    elif score >= 50:
        signal = "yellow"
    else:
        signal = "red"
    return score, signal, parts


def build_analysis(
    *,
    code: str,
    name: str,
    price: float | None,
    change_pct: float | None,
    bars: list[dict[str, Any]],
    ownership: dict[str, Any] | None,
    research: dict[str, Any] | None,
    fundamentals: dict[str, Any] | None,
    cfg: dict[str, Any],
) -> dict[str, Any]:
    lookback = int(cfg.get("price_lookback", 250))
    min_upside = float(cfg.get("min_upside", 0.30))
    min_val = float(cfg.get("min_valuation_score", 55))
    val = valuation_block(bars, lookback=lookback)
    px = price if price is not None else val.get("close")

    research = dict(research or {})
    upside = research.get("upside")
    tmed = research.get("target_median")
    if px and px > 0 and tmed:
        upside = float(tmed) / float(px) - 1.0
        research["upside"] = round(upside, 4)
        research["price"] = px

    fund_score, fund_parts = fundamental_valuation_score(fundamentals)
    val = {
        **val,
        **fund_parts,
        "valuation_score": fund_score,
    }

    own = ownership or {}
    sources = own.get("sources") or []
    source_label = "+".join(sources) if sources else "无"
    checks = {
        "ownership": {
            "ok": bool(sources),
            "detail": (
                f"所有权信号：{source_label}"
                + (
                    f"（增持{own.get('event_count')}）"
                    if "insider" in sources
                    else ""
                )
                + ("；含回购" if own.get("has_buyback") else "")
                + ("；含大股东增持计划" if own.get("has_holder_increase") else "")
            ),
        },
        "research_upside": {
            "ok": upside is not None and float(upside) >= min_upside,
            "detail": (
                f"目标价中枢 {tmed}（{research.get('target_source') or '?'}），"
                f"上行 {float(upside)*100:.1f}%（≥{min_upside*100:.0f}%）"
                if upside is not None and tmed
                else "无有效目标价或上行不足"
            ),
        },
        "valuation_ok": {
            "ok": fund_score >= min_val,
            "detail": (
                f"综合估值分 {fund_score}（≥{min_val}；"
                f"PE={fund_parts.get('pe_ttm')} PB={fund_parts.get('pb_mrq')} "
                f"净利同比={fund_parts.get('profit_yoy')} PEG={fund_parts.get('peg')}）"
            ),
        },
    }
    passed = all(c["ok"] for c in checks.values())
    score, signal, parts = score_candidate(
        valuation_score=fund_score,
        price_pct=val.get("price_percentile"),
        upside=None if upside is None else float(upside),
        ownership=own,
        research=research,
        vol=val.get("volatility"),
        dd=val.get("drawdown60"),
        weights=cfg.get("weights") or {},
    )
    insider_view = None
    if own:
        insider_view = {
            "sources": sources,
            "strength": own.get("strength"),
            "event_count": own.get("event_count", 0),
            "total_shares": (own.get("insider") or {}).get("total_shares"),
            "total_amount": own.get("total_amount"),
            "person_count": own.get("person_count"),
            "persons": own.get("persons") or [],
            "latest_date": own.get("latest_date"),
            "events": own.get("events") or [],
            "has_buyback": own.get("has_buyback"),
            "has_holder_increase": own.get("has_holder_increase"),
            "buybacks": ((own.get("ann") or {}).get("buybacks") or [])[:5],
            "holder_increases": ((own.get("ann") or {}).get("holder_increases") or [])[:5],
        }
    return {
        "code": code,
        "name": name,
        "price": px,
        "change_pct": change_pct,
        "passed": passed,
        "checks": checks,
        "score": score,
        "signal": signal,
        "score_parts": parts,
        "valuation": val,
        "fundamentals": fundamentals,
        "insider": insider_view,
        "research": research or None,
        "disclosure": cfg.get("disclosure"),
    }
