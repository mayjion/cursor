"""涨停观察榜规则（与 judgment_t1low 冻结标准一致）。"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


def is_limit_up(chg: float, code: str) -> bool:
    c = str(code).zfill(6)
    if c.startswith(("300", "301", "688", "689")):
        return chg >= 19.5
    return chg >= 9.7


def _f(v: Any) -> float | None:
    if v is None or v == "" or v == "-":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


@dataclass
class LimitupEval:
    ok: bool
    pool: str | None  # watch | focus | None
    reason: str
    code: str
    name: str
    signal_date: str
    market_cap_yi: float
    signal_chg: float
    flow_sum_10: float
    flow_near5: float
    flow_prev5: float
    flow_to_mcap: float
    vol_ma_ratio: float
    up_days: int
    entry_hint: str
    target_ret: float
    floor_ret: float
    score: float

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def evaluate_limitup_bar(
    *,
    code: str,
    name: str,
    market_cap_yi: float,
    bars: list[dict[str, Any]],
    flows: dict[str, float],
    cfg: dict[str, Any],
    signal_index: int | None = None,
) -> LimitupEval:
    """对某根K线作为涨停信号日做过滤。默认取最后一根可完整评估的 bar。"""
    w = int(cfg.get("flow_window") or 10)
    target = float(cfg.get("target_ret") or 0.10)
    floor = float(cfg.get("floor_ret") or 0.08)
    entry_hint = (
        f"涨停次日最低价买入；{int(cfg.get('forward_days') or 10)}日内"
        f"最高价涨幅≥{target:.0%}（底线{floor:.0%}）可视为达标"
    )

    def fail(reason: str, **extra: Any) -> LimitupEval:
        return LimitupEval(
            ok=False,
            pool=None,
            reason=reason,
            code=code,
            name=name,
            signal_date=str(extra.get("signal_date") or ""),
            market_cap_yi=market_cap_yi,
            signal_chg=float(extra.get("signal_chg") or 0),
            flow_sum_10=float(extra.get("flow_sum_10") or 0),
            flow_near5=float(extra.get("flow_near5") or 0),
            flow_prev5=float(extra.get("flow_prev5") or 0),
            flow_to_mcap=float(extra.get("flow_to_mcap") or 0),
            vol_ma_ratio=float(extra.get("vol_ma_ratio") or 0),
            up_days=int(extra.get("up_days") or 0),
            entry_hint=entry_hint,
            target_ret=target,
            floor_ret=floor,
            score=0.0,
        )

    if market_cap_yi < float(cfg.get("min_market_cap_yi") or 100):
        return fail("市值未达100亿")
    if cfg.get("exclude_st", True) and "ST" in (name or "").upper():
        return fail("ST")
    if cfg.get("exclude_bj", True) and str(code).startswith(("4", "8")):
        return fail("北交所")

    if len(bars) < w + 1:
        return fail("K线不足")

    i = signal_index if signal_index is not None else len(bars) - 1
    if i < w or i >= len(bars):
        return fail("信号日索引无效")

    sig = bars[i]
    chg = float(sig.get("change_pct") or 0)
    signal_date = str(sig.get("trade_date") or sig.get("date") or "")
    if not is_limit_up(chg, code):
        return fail("非涨停", signal_date=signal_date, signal_chg=chg)

    pre = bars[i - w : i]
    vols = [float(b.get("volume") or 0) for b in pre]
    if any(v <= 0 for v in vols):
        return fail("前量无效", signal_date=signal_date, signal_chg=chg)

    prev5, near5 = vols[:5], vols[5:]
    ma_prev = sum(prev5) / 5
    ma_near = sum(near5) / 5
    if ma_prev <= 0:
        return fail("前量均值为0", signal_date=signal_date, signal_chg=chg)
    vol_ratio = ma_near / ma_prev
    min_vol = float(cfg.get("min_vol_ma_ratio") or 1.1)
    max_vol = float(cfg.get("max_vol_ma_ratio") or 0)
    if vol_ratio < min_vol:
        return fail(
            f"放量不足({vol_ratio:.2f}<{min_vol})",
            signal_date=signal_date,
            signal_chg=chg,
            vol_ma_ratio=vol_ratio,
        )
    if max_vol > 0 and vol_ratio > max_vol:
        return fail(
            f"放量过大({vol_ratio:.2f}>{max_vol})",
            signal_date=signal_date,
            signal_chg=chg,
            vol_ma_ratio=vol_ratio,
        )

    chain = prev5[-1:] + near5
    up_days = sum(1 for j in range(1, len(chain)) if chain[j] > chain[j - 1])
    if up_days < int(cfg.get("min_up_days_in_5") or 3):
        return fail(
            f"放量天数不足({up_days})",
            signal_date=signal_date,
            signal_chg=chg,
            vol_ma_ratio=vol_ratio,
            up_days=up_days,
        )

    if cfg.get("reject_pulse_fake", True):
        spike = float(cfg.get("pulse_spike") or 3.0)
        for j, v in enumerate(vols):
            if v > spike * ma_prev:
                after = vols[j + 1 : j + 3]
                if after and (sum(after) / len(after)) < 1.1 * ma_prev:
                    return fail(
                        "脉冲假放量",
                        signal_date=signal_date,
                        signal_chg=chg,
                        vol_ma_ratio=vol_ratio,
                        up_days=up_days,
                    )

    flow_vals: list[float] = []
    for b in pre:
        d = str(b.get("trade_date") or b.get("date") or "")
        if d not in flows:
            return fail(
                "主力数据缺失",
                signal_date=signal_date,
                signal_chg=chg,
                vol_ma_ratio=vol_ratio,
                up_days=up_days,
            )
        flow_vals.append(float(flows[d]))

    flow_sum = sum(flow_vals)
    flow_prev5 = sum(flow_vals[:5])
    flow_near5 = sum(flow_vals[5:])
    if cfg.get("require_flow_sum_positive", True) and flow_sum <= 0:
        return fail(
            "10日主力累计≤0",
            signal_date=signal_date,
            signal_chg=chg,
            vol_ma_ratio=vol_ratio,
            up_days=up_days,
            flow_sum_10=flow_sum,
        )

    mcap_yuan = market_cap_yi * 1e8
    flow_to_mcap = (flow_sum / mcap_yuan) if mcap_yuan > 0 else 0.0
    watch_th = float(cfg.get("watch_flow_to_mcap") or 0.005)
    focus_th = float(cfg.get("focus_flow_to_mcap") or 0.008)

    if flow_to_mcap < watch_th:
        return fail(
            f"主力/市值不足({flow_to_mcap:.2%}<{watch_th:.2%})",
            signal_date=signal_date,
            signal_chg=chg,
            vol_ma_ratio=vol_ratio,
            up_days=up_days,
            flow_sum_10=flow_sum,
            flow_near5=flow_near5,
            flow_prev5=flow_prev5,
            flow_to_mcap=flow_to_mcap,
        )

    pool = "watch"
    if flow_to_mcap >= focus_th:
        pool = "focus"
        if cfg.get("focus_require_vol_band"):
            vmin = float(cfg.get("focus_vol_min") or 1.2)
            vmax = float(cfg.get("focus_vol_max") or 1.6)
            if not (vmin <= vol_ratio <= vmax):
                pool = "watch"
        if cfg.get("focus_require_flow_accel") and flow_near5 < flow_prev5:
            pool = "watch"

    # 评分：主力强度为主，放量温和加分
    score = min(100.0, flow_to_mcap / focus_th * 70.0)
    if 1.2 <= vol_ratio <= 1.8:
        score += 15.0
    if flow_near5 >= flow_prev5:
        score += 10.0
    if pool == "focus":
        score += 5.0
    score = round(min(100.0, score), 2)

    return LimitupEval(
        ok=True,
        pool=pool,
        reason="ok",
        code=str(code).zfill(6),
        name=name,
        signal_date=signal_date,
        market_cap_yi=round(market_cap_yi, 2),
        signal_chg=round(chg, 2),
        flow_sum_10=round(flow_sum, 2),
        flow_near5=round(flow_near5, 2),
        flow_prev5=round(flow_prev5, 2),
        flow_to_mcap=round(flow_to_mcap, 6),
        vol_ma_ratio=round(vol_ratio, 3),
        up_days=up_days,
        entry_hint=entry_hint,
        target_ret=target,
        floor_ret=floor,
        score=score,
    )
