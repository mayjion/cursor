"""点位择时决策：任意 as_of 只用当日及之前可见数据（无未来函数）。"""
from __future__ import annotations

from typing import Any

from app.config import load_yaml
from app.factors.engine import flow_burst, max_drawdown, momentum, price_percentile, volatility


def timing_rules() -> dict[str, Any]:
    return load_yaml("timing_rules.yaml")


def cut_bars(bars: list[dict[str, Any]], as_of: str) -> list[dict[str, Any]]:
    return [b for b in bars if str(b.get("trade_date") or "") <= as_of]


def cut_shares(shares: list[dict[str, Any]], as_of: str) -> list[dict[str, Any]]:
    return [s for s in shares if str(s.get("change_date") or "") <= as_of]


def _close_on(bars: list[dict[str, Any]], as_of: str) -> float | None:
    for b in reversed(bars):
        if str(b.get("trade_date")) == as_of and b.get("close") is not None:
            return float(b["close"])
    for b in reversed(bars):
        if str(b.get("trade_date") or "") <= as_of and b.get("close") is not None:
            return float(b["close"])
    return None


def snapshot_features(
    bars: list[dict[str, Any]],
    shares: list[dict[str, Any]],
    as_of: str,
    *,
    market_bars: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    b = cut_bars(bars, as_of)
    s = cut_shares(shares, as_of)
    mom5 = momentum(b, 5)
    mom20 = momentum(b, 20)
    mom60 = momentum(b, 60)
    pct = price_percentile(b, 250)
    burst = flow_burst(s)
    vol = volatility(b, 20)
    dd = max_drawdown(b, 60)
    mkt_mom60 = None
    if market_bars is not None:
        mb = cut_bars(market_bars, as_of)
        mkt_mom60 = momentum(mb, 60)
    return {
        "as_of": as_of,
        "mom5": mom5,
        "mom20": mom20,
        "mom60": mom60,
        "price_percentile": pct,
        "flow_burst": burst,
        "volatility": vol,
        "drawdown60": dd,
        "market_mom60": mkt_mom60,
        "close": _close_on(b, as_of),
        "bars_n": len(b),
        "shares_n": len(s),
    }


def decide_from_features(
    feat: dict[str, Any],
    *,
    bucket: str = "hot",
    in_position: bool = False,
    entry_price: float | None = None,
    entry_date: str | None = None,
    hold_days: int | None = None,
    rules: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """基于已截断特征做决策（回测网格可复用特征缓存）。"""
    cfg = rules or timing_rules()
    add_cfg = cfg.get("add") or {}
    red_cfg = cfg.get("reduce") or {}
    reasons: list[str] = []
    blockers: list[str] = []
    checks: list[dict[str, Any]] = []

    burst = feat.get("flow_burst")
    pct = feat.get("price_percentile")
    mom5 = feat.get("mom5")
    mom20 = feat.get("mom20")
    mom60 = feat.get("mom60")
    vol = feat.get("volatility")
    dd = feat.get("drawdown60")
    mkt_mom60 = feat.get("market_mom60")
    close = feat.get("close")

    qoq_min = float(
        add_cfg.get("defensive_qoq_multiple_min")
        if bucket == "defensive"
        else add_cfg.get("qoq_multiple_min", 3.0)
    )
    max_pct = float(
        add_cfg.get("defensive_max_price_percentile")
        if bucket == "defensive"
        else add_cfg.get("max_price_percentile", 0.50)
    )
    min_mom = float(add_cfg.get("min_mom20", 0.0))
    min_mom60 = float(add_cfg.get("min_mom60", 0.0))
    min_mom5 = float(add_cfg.get("min_mom5", -1.0))
    max_mom20 = float(add_cfg.get("max_mom20", 9.0))
    max_vol = float(add_cfg.get("max_volatility", 9.0))
    min_dd = float(add_cfg.get("min_drawdown60", -9.0))  # 如 -0.25：跌幅不能更深
    min_mkt = float(add_cfg.get("min_market_mom60", -9.0))

    if in_position and entry_price and entry_price > 0 and close is not None:
        pnl = close / entry_price - 1.0
        tp = float(red_cfg.get("take_profit", 0.50))
        sl = float(red_cfg.get("stop_loss", 0.12))
        max_hold = int(red_cfg.get("max_hold_days", 120))
        time_stop = int(red_cfg.get("time_stop_days", 0) or 0)
        time_stop_min = float(red_cfg.get("time_stop_min_pnl", 0.0))

        if pnl >= tp:
            reasons.append(f"浮盈 {pnl*100:.1f}% ≥ 止盈 {tp*100:.0f}%")
            return _out("reduce", feat, reasons, blockers, checks, priority=90, fitness=85)
        if pnl <= -sl:
            reasons.append(f"浮亏 {pnl*100:.1f}% ≤ 止损 -{sl*100:.0f}%")
            return _out("reduce", feat, reasons, blockers, checks, priority=85, fitness=70)

        hd = hold_days
        if hd is None and entry_date:
            hd = 0
        if time_stop > 0 and hd is not None and hd >= time_stop and pnl < time_stop_min:
            reasons.append(
                f"持仓 {hd} 日未达进度（{pnl*100:+.1f}% < {time_stop_min*100:.0f}%），时间止损"
            )
            return _out("reduce", feat, reasons, blockers, checks, priority=65, fitness=55)
        if hd is not None and hd >= max_hold:
            reasons.append(f"持仓满 {max_hold} 个决策日，到期减仓（收益 {pnl*100:+.1f}%）")
            return _out("reduce", feat, reasons, blockers, checks, priority=55, fitness=50)

        if red_cfg.get("use_overheat_exit"):
            oh_pct = float(red_cfg.get("overheat_percentile", 0.92))
            oh_mom = float(red_cfg.get("overheat_mom20", 0.12))
            overheat = pct is not None and mom20 is not None and pct >= oh_pct and mom20 >= oh_mom
            checks.append(
                {"id": "overheat", "ok": overheat, "detail": f"分位={_fmt(pct)} mom20={_fmt_pct(mom20)}"}
            )
            if overheat:
                reasons.append("持仓期过热，建议减仓")
                return _out("reduce", feat, reasons, blockers, checks, priority=70, fitness=60)

        if red_cfg.get("use_flow_fade_exit"):
            fade = float(red_cfg.get("flow_fade_max", 0.3))
            flow_fade = burst is not None and burst < fade
            checks.append({"id": "flow_fade", "ok": flow_fade, "detail": f"flow_burst={_fmt(burst)}"})
            if flow_fade:
                reasons.append(f"净申购消退（{burst:.2f}x），建议减仓")
                return _out("reduce", feat, reasons, blockers, checks, priority=60, fitness=55)

        reasons.append(f"持仓中，浮盈亏 {pnl*100:+.1f}%，等待止盈 {tp*100:.0f}% / 止损 {sl*100:.0f}%")
        return _out("hold", feat, reasons, blockers, checks, priority=10, fitness=40)

    # —— 加仓：资金突发 + 偏低区 + 短线反弹确认，并避开追高/高波/弱市 ——
    flow_ok = burst is not None and burst >= qoq_min
    checks.append(
        {"id": "flow_burst", "ok": flow_ok, "detail": f"净申购突发 {_fmt(burst)}（≥{qoq_min}x）"}
    )
    if flow_ok:
        reasons.append(f"净申购突发 {burst:.2f}x ≥ {qoq_min}x")
    else:
        blockers.append(f"净申购未达 {qoq_min}x（当前 {_fmt(burst)}）")

    pct_ok = pct is not None and pct <= max_pct
    checks.append(
        {
            "id": "price_percentile",
            "ok": pct_ok,
            "detail": f"一年价格分位 {_fmt(pct)}（≤{max_pct:.0%}）",
        }
    )
    if pct_ok:
        reasons.append(f"价格分位 {pct:.0%} ≤ {max_pct:.0%}，偏低区")
    else:
        blockers.append(f"价格分位未达偏低区（{_fmt(pct)}）")

    mom_ok = mom20 is not None and mom20 >= min_mom
    checks.append(
        {"id": "mom20", "ok": mom_ok, "detail": f"20日动量 {_fmt_pct(mom20)}（≥{min_mom:.0%}）"}
    )
    if mom_ok:
        reasons.append(f"20日动量 {_fmt_pct(mom20)}")
    else:
        blockers.append(f"20日动量不足（{_fmt_pct(mom20)}）")

    mom60_ok = mom60 is not None and mom60 >= min_mom60
    checks.append(
        {"id": "mom60", "ok": mom60_ok, "detail": f"60日动量 {_fmt_pct(mom60)}（≥{min_mom60:.0%}）"}
    )
    if mom60_ok:
        reasons.append(f"60日动量 {_fmt_pct(mom60)}")
    else:
        blockers.append(f"60日动量不足（{_fmt_pct(mom60)}）")

    # 短线反弹确认（默认关闭：min_mom5=-1）
    mom5_ok = mom5 is not None and mom5 >= min_mom5
    if min_mom5 > -0.99:
        checks.append(
            {"id": "mom5", "ok": mom5_ok, "detail": f"5日动量 {_fmt_pct(mom5)}（≥{min_mom5:.0%}）"}
        )
        if mom5_ok:
            reasons.append(f"5日反弹 {_fmt_pct(mom5)}")
        else:
            blockers.append(f"5日动量未确认反弹（{_fmt_pct(mom5)}）")
    else:
        mom5_ok = True

    # 反追高
    chase_ok = mom20 is None or mom20 <= max_mom20
    if max_mom20 < 8:
        checks.append(
            {"id": "max_mom20", "ok": chase_ok, "detail": f"20日动量 {_fmt_pct(mom20)}（≤{max_mom20:.0%}）"}
        )
        if not chase_ok:
            blockers.append(f"20日动量过高，疑似追高（{_fmt_pct(mom20)}）")
        elif mom20 is not None:
            reasons.append(f"未追高（mom20 {_fmt_pct(mom20)}）")
    else:
        chase_ok = True

    vol_ok = vol is None or vol <= max_vol
    if max_vol < 8:
        checks.append(
            {"id": "volatility", "ok": vol_ok, "detail": f"年化波动 {_fmt(vol)}（≤{max_vol:.2f}）"}
        )
        if not vol_ok:
            blockers.append(f"波动过高（{_fmt(vol)}）")
    else:
        vol_ok = True

    dd_ok = dd is None or dd >= min_dd
    if min_dd > -8:
        checks.append(
            {"id": "drawdown60", "ok": dd_ok, "detail": f"60日回撤 {_fmt_pct(dd)}（≥{min_dd:.0%}）"}
        )
        if not dd_ok:
            blockers.append(f"回撤过深，回避下跌刀（{_fmt_pct(dd)}）")
    else:
        dd_ok = True

    mkt_ok = True
    if add_cfg.get("require_market_regime", True) and min_mkt > -8:
        mkt_ok = mkt_mom60 is not None and mkt_mom60 >= min_mkt
        checks.append(
            {
                "id": "market_regime",
                "ok": mkt_ok,
                "detail": f"沪深300 60日动量 {_fmt_pct(mkt_mom60)}（≥{min_mkt:.0%}）",
            }
        )
        if mkt_ok:
            reasons.append(f"市场环境可接受（300 mom60 {_fmt_pct(mkt_mom60)}）")
        else:
            blockers.append(f"市场偏弱（300 mom60 {_fmt_pct(mkt_mom60)}）")

    all_ok = (
        flow_ok
        and pct_ok
        and mom_ok
        and mom60_ok
        and mom5_ok
        and chase_ok
        and vol_ok
        and dd_ok
        and mkt_ok
        and close is not None
    )
    if all_ok:
        fitness = 55.0
        if burst is not None:
            fitness += min(25.0, (burst - qoq_min) * 8.0)
        if pct is not None:
            fitness += max(0.0, (max_pct - pct) * 50.0)
        if mom5 is not None and mom5 > 0:
            fitness += min(8.0, mom5 * 80.0)
        return _out(
            "add",
            feat,
            reasons,
            blockers,
            checks,
            priority=100,
            fitness=min(100.0, round(fitness, 1)),
        )

    return _out("hold", feat, reasons, blockers, checks, priority=5, fitness=20.0)


def decide(
    *,
    as_of: str,
    bars: list[dict[str, Any]],
    shares: list[dict[str, Any]],
    bucket: str = "hot",
    in_position: bool = False,
    entry_price: float | None = None,
    entry_date: str | None = None,
    hold_days: int | None = None,
    rules: dict[str, Any] | None = None,
    market_bars: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """返回 action: add | reduce | hold。仅依赖 as_of 截断特征。"""
    cfg = rules or timing_rules()
    add_cfg = cfg.get("add") or {}
    if market_bars is None and add_cfg.get("require_market_regime", True):
        try:
            from app.db import store

            market_bars = store.list_bars("510300", limit=320)
        except Exception:  # noqa: BLE001
            market_bars = None
    feat = snapshot_features(bars, shares, as_of, market_bars=market_bars)
    return decide_from_features(
        feat,
        bucket=bucket,
        in_position=in_position,
        entry_price=entry_price,
        entry_date=entry_date,
        hold_days=hold_days,
        rules=cfg,
    )


def merge_rule_overrides(base: dict[str, Any], add_o: dict[str, Any], red_o: dict[str, Any]) -> dict[str, Any]:
    import copy

    cfg = copy.deepcopy(base)
    cfg.setdefault("add", {}).update(add_o)
    cfg.setdefault("reduce", {}).update(red_o)
    return cfg


def _out(
    action: str,
    feat: dict[str, Any],
    reasons: list[str],
    blockers: list[str],
    checks: list[dict[str, Any]],
    *,
    priority: int,
    fitness: float,
) -> dict[str, Any]:
    return {
        "action": action,
        "priority": priority,
        "fitness": fitness,
        "reasons": reasons,
        "blockers": blockers,
        "checks": checks,
        "features": feat,
    }


def _fmt(v: float | None) -> str:
    if v is None:
        return "—"
    return f"{v:.2f}"


def _fmt_pct(v: float | None) -> str:
    if v is None:
        return "—"
    return f"{v*100:.1f}%"
