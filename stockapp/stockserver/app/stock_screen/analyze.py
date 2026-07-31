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


def score_candidate(
    *,
    price_pct: float | None,
    upside: float | None,
    insider: dict[str, Any] | None,
    research: dict[str, Any] | None,
    vol: float | None,
    dd: float | None,
    weights: dict[str, float],
    max_price_percentile: float,
) -> tuple[float, str, dict[str, float]]:
    """返回 (0-100分, 信号灯, 分项)。"""
    # 低估：分位越低越好
    if price_pct is None:
        undervalue = 40.0
    else:
        # 0 → 100, threshold → ~55, 更高更差
        undervalue = max(0.0, min(100.0, (max_price_percentile - price_pct) / max(max_price_percentile, 1e-6) * 70.0 + 30.0))

    # 上行空间：30%→55, 50%→75, 100%→100
    if upside is None or upside <= 0:
        upside_s = 20.0
    else:
        upside_s = max(0.0, min(100.0, 40.0 + upside * 80.0))

    # 增持强度：次数 + 金额粗映射
    insider = insider or {}
    n = int(insider.get("event_count") or 0)
    amt = float(insider.get("total_amount") or 0)
    insider_s = max(0.0, min(100.0, 35.0 + n * 12.0 + min(30.0, amt / 1e6 * 3.0)))

    # 研报一致性：报告数 + 机构数
    research = research or {}
    rc = int(research.get("report_count") or 0)
    oc = int(research.get("org_count") or 0)
    research_s = max(0.0, min(100.0, 30.0 + rc * 10.0 + oc * 8.0))

    # 风险：波动高/回撤深扣分（输出为「风险健康分」，越高越好）
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
    insider: dict[str, Any] | None,
    research: dict[str, Any] | None,
    cfg: dict[str, Any],
) -> dict[str, Any]:
    lookback = int(cfg.get("price_lookback", 250))
    max_pct = float(cfg.get("max_price_percentile", 0.35))
    min_upside = float(cfg.get("min_upside", 0.30))
    val = valuation_block(bars, lookback=lookback)
    px = price if price is not None else val.get("close")

    # 用现价重算上行（研报聚合时可能尚未有价）
    research = dict(research or {})
    upside = research.get("upside")
    tmed = research.get("target_median")
    if px and px > 0 and tmed:
        upside = float(tmed) / float(px) - 1.0
        research["upside"] = round(upside, 4)
        research["price"] = px

    pct = val.get("price_percentile")
    checks = {
        "insider_3m": {
            "ok": bool(insider and int(insider.get("event_count") or 0) > 0),
            "detail": (
                f"近{cfg.get('insider_days', 90)}日增持 {insider.get('event_count')} 次"
                if insider
                else "无高管增持"
            ),
        },
        "research_upside": {
            "ok": upside is not None and float(upside) >= min_upside,
            "detail": (
                f"目标价中枢 {tmed}，上行 {float(upside)*100:.1f}%（≥{min_upside*100:.0f}%）"
                if upside is not None and tmed
                else "无有效目标价或上行不足"
            ),
        },
        "valuation_low": {
            "ok": pct is not None and float(pct) <= max_pct,
            "detail": (
                f"一年价格分位 {float(pct)*100:.1f}%（≤{max_pct*100:.0f}%）"
                if pct is not None
                else "日K不足，无法估分位"
            ),
        },
    }
    passed = all(c["ok"] for c in checks.values())
    score, signal, parts = score_candidate(
        price_pct=None if pct is None else float(pct),
        upside=None if upside is None else float(upside),
        insider=insider,
        research=research,
        vol=val.get("volatility"),
        dd=val.get("drawdown60"),
        weights=cfg.get("weights") or {},
        max_price_percentile=max_pct,
    )
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
        "insider": {
            "event_count": (insider or {}).get("event_count", 0),
            "total_shares": (insider or {}).get("total_shares"),
            "total_amount": (insider or {}).get("total_amount"),
            "person_count": (insider or {}).get("person_count"),
            "persons": (insider or {}).get("persons") or [],
            "latest_date": (insider or {}).get("latest_date"),
            "events": (insider or {}).get("events") or [],
        }
        if insider
        else None,
        "research": research or None,
        "disclosure": cfg.get("disclosure"),
    }
