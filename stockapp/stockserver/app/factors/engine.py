from __future__ import annotations

import math
from typing import Any


def _closes(bars: list[dict[str, Any]]) -> list[float]:
    return [float(b["close"]) for b in bars if b.get("close") is not None]


def momentum(bars: list[dict[str, Any]], days: int) -> float | None:
    closes = _closes(bars)
    if len(closes) <= days:
        return None
    p0, p1 = closes[-(days + 1)], closes[-1]
    if p0 <= 0:
        return None
    return (p1 - p0) / p0


def volatility(bars: list[dict[str, Any]], days: int = 20) -> float | None:
    closes = _closes(bars)
    if len(closes) < days + 1:
        return None
    rets = []
    window = closes[-(days + 1) :]
    for i in range(1, len(window)):
        if window[i - 1] > 0:
            rets.append(window[i] / window[i - 1] - 1.0)
    if len(rets) < 5:
        return None
    mean = sum(rets) / len(rets)
    var = sum((r - mean) ** 2 for r in rets) / len(rets)
    return math.sqrt(var) * math.sqrt(252)


def price_percentile(bars: list[dict[str, Any]], lookback: int = 250) -> float | None:
    """收盘价近 lookback 交易日分位（公开代理估值冷热）。"""
    closes = _closes(bars)
    if len(closes) < 30:
        return None
    window = closes[-lookback:] if len(closes) >= lookback else closes
    last = window[-1]
    below = sum(1 for c in window if c <= last)
    return below / len(window)


def max_drawdown(bars: list[dict[str, Any]], lookback: int = 60) -> float | None:
    closes = _closes(bars)
    if len(closes) < 10:
        return None
    window = closes[-lookback:] if len(closes) >= lookback else closes
    peak = window[0]
    dd = 0.0
    for c in window:
        peak = max(peak, c)
        if peak > 0:
            dd = min(dd, c / peak - 1.0)
    return dd


def flow_burst(shares: list[dict[str, Any]]) -> float | None:
    """
    季报净申购环比倍数（公开期间申购−赎回）。
    返回 log1p(multiple) 风格的突发强度；无季报则用近20日日净申购相对强度。
    """
    quarters = [
        s
        for s in shares
        if s.get("quarter_net") is not None
        and (s.get("apply_share") is not None or s.get("redeem_share") is not None)
    ]
    if len(quarters) >= 2:
        prev = float(quarters[-2]["quarter_net"] or 0)
        cur = float(quarters[-1]["quarter_net"] or 0)
        if cur <= 0:
            return 0.0
        if prev <= 0:
            return 2.0  # 由负转正，给中等突发分
        return min(cur / prev, 20.0)

    # 日频兜底：近20日净流入 / 前20日绝对值均值
    nets = [float(s["daily_net"]) for s in shares if s.get("daily_net") is not None]
    if len(nets) < 40:
        return None
    recent = sum(nets[-20:])
    prior = nets[-40:-20]
    base = sum(abs(x) for x in prior) / len(prior)
    if base < 1e-9:
        return 1.0 if recent > 0 else 0.0
    return max(0.0, min(recent / base, 20.0))


def score_momentum(m: float | None) -> float | None:
    if m is None:
        return None
    # -20%~+20% → 0~100
    return max(0.0, min(100.0, 50.0 + m * 250.0))


def score_volatility(v: float | None) -> float | None:
    if v is None:
        return None
    # 低波动更好（稳健向）；年化 10%~50% 映射
    # 波动越低分越高
    return max(0.0, min(100.0, 100.0 - (v - 0.10) / 0.40 * 100.0))


def score_percentile_inverse(p: float | None) -> float | None:
    """价位/估值分位越低越好（便宜）。"""
    if p is None:
        return None
    return max(0.0, min(100.0, (1.0 - p) * 100.0))


def score_flow(burst: float | None) -> float | None:
    if burst is None:
        return None
    # 1x→50, 2x→70, 3x→85, ≥5x→100
    if burst <= 0:
        return 20.0
    return max(0.0, min(100.0, 40.0 + math.log2(1.0 + burst) * 25.0))


def _proxy_momentum_score(ext_bars_list: list[list[dict[str, Any]]], days: int = 20) -> dict[str, Any]:
    """多个外盘序列等权 20 日动量 → 得分。"""
    moms: list[float] = []
    for bars in ext_bars_list:
        m = momentum(bars, days)
        if m is not None:
            moms.append(m)
    if not moms:
        return {"raw": None, "score": None, "source": "proxy", "note": "外盘序列不足"}
    avg = sum(moms) / len(moms)
    return {
        "raw": avg,
        "score": score_momentum(avg),
            "source": "proxy",
            "note": "东财美股公开日K动量代理",
        }


def compute_public_factors(
    bars: list[dict[str, Any]],
    shares: list[dict[str, Any]],
    *,
    proxy_bars: dict[str, list[list[dict[str, Any]]]] | None = None,
) -> dict[str, dict[str, Any]]:
    """计算可公开落地的通用因子原始值与 0-100 得分。"""
    mom20 = momentum(bars, 20)
    mom60 = momentum(bars, 60)
    vol = volatility(bars, 20)
    pct = price_percentile(bars, 250)
    burst = flow_burst(shares)
    dd = max_drawdown(bars, 60)

    amounts = [float(b["amount"]) for b in bars if b.get("amount") is not None]
    turnover_raw = None
    turnover_score = None
    if len(amounts) >= 40:
        recent = sum(amounts[-20:]) / 20.0
        hist = amounts[-250:] if len(amounts) >= 250 else amounts
        below = sum(1 for a in hist if a <= recent)
        turnover_raw = below / len(hist)
        turnover_score = max(0.0, min(100.0, turnover_raw * 100.0))

    out: dict[str, dict[str, Any]] = {
        "mom20": {
            "raw": mom20,
            "score": score_momentum(mom20),
            "source": "public",
        },
        "mom60": {
            "raw": mom60,
            "score": score_momentum(mom60),
            "source": "public",
        },
        "volatility": {
            "raw": vol,
            "score": score_volatility(vol),
            "source": "public",
        },
        "pe_pct": {
            # 无公开 PE 序列时，用价格分位作估值冷热代理
            "raw": pct,
            "score": score_percentile_inverse(pct),
            "source": "proxy",
            "note": "价格分位代理估值百分位",
        },
        "pb_pct": {
            "raw": pct,
            "score": score_percentile_inverse(pct),
            "source": "proxy",
            "note": "价格分位代理",
        },
        "flow_burst": {
            "raw": burst,
            "score": score_flow(burst),
            "source": "public",
        },
        "turnover_proxy": {
            "raw": turnover_raw if turnover_raw is not None else mom20,
            "score": turnover_score if turnover_score is not None else score_momentum(mom20),
            "source": "public",
            "note": "成交额近20日相对一年分位" if turnover_raw is not None else "暂用动量近似活跃度",
        },
        "drawdown": {
            "raw": dd,
            "score": None if dd is None else max(0.0, min(100.0, 100.0 + dd * 200.0)),
            "source": "public",
        },
        "northbound_proxy": {
            "raw": turnover_raw if turnover_raw is not None else mom20,
            "score": turnover_score if turnover_score is not None else score_momentum(mom20),
            "source": "proxy",
            "note": "宽基成交活跃度代理北向/资金热度",
        },
    }

    proxy_bars = proxy_bars or {}
    for fid, series_list in proxy_bars.items():
        out[fid] = _proxy_momentum_score(series_list)

    # 债券：TLT 上涨（收益率下行）对债券 ETF 偏利多；对红利用同向即可
    if "bond_yield_proxy" in proxy_bars:
        out["bond_yield_proxy"] = _proxy_momentum_score(proxy_bars["bond_yield_proxy"])
        note = out["bond_yield_proxy"].get("note") or ""
        out["bond_yield_proxy"]["note"] = (note + " · TLT 代理利率环境").strip(" ·")

    return out
