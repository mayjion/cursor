"""择时服务：回测缓存 + 今日门控行动。"""
from __future__ import annotations

from typing import Any

from app.db import store
from app.timing.backtest import backtest_code, run_universe_backtest
from app.timing.engine import decide, timing_rules


ACTION_LABEL = {
    "add": "建议加仓",
    "reduce": "若持有建议减仓",
    "hold": "观望",
}


def active_rules() -> dict[str, Any]:
    """今日决策优先用 walk-forward 选定参数；否则用 yaml 先验。"""
    base = timing_rules()
    sel = store.load_json_meta("timing_selected_rules")
    if not sel:
        return base
    import copy

    cfg = copy.deepcopy(base)
    if sel.get("add"):
        cfg["add"] = sel["add"]
    if sel.get("reduce"):
        cfg["reduce"] = sel["reduce"]
    return cfg


def ensure_backtest(items: list[dict[str, Any]] | None = None, *, force: bool = False) -> dict[str, Any]:
    """优先用扩大训练池回测；无训练池时退回观察池 items。"""
    cached = store.load_json_meta("timing_backtest")
    if cached and not force:
        return cached
    from app.collectors.etf_universe import load_train_universe

    train_items = load_train_universe()
    pool = train_items if train_items else (items or [])
    if not pool:
        raise ValueError("no ETF universe for backtest")
    result = run_universe_backtest(pool)
    result["watchlist_note"] = "规则在扩大训练池上定参；今日行动仍只针对观察池"
    store.save_json_meta("timing_backtest", result)
    store.set_meta("last_timing_backtest_at", store.utc_now_iso())
    return result


def _latest_as_of(code: str) -> str | None:
    bars = store.list_bars(code, limit=5)
    if not bars:
        return None
    return str(bars[-1]["trade_date"])


def build_live_actions(
    items: list[dict[str, Any]],
    backtest: dict[str, Any],
) -> dict[str, Any]:
    """今日点位决策；加仓受一年回测门控。"""
    validated = bool(backtest.get("validated"))
    primary = str(backtest.get("primary_window") or 252)
    per_code = backtest.get("per_code") or {}
    actions: list[dict[str, Any]] = []

    for etf in items:
        code = str(etf["primary"])
        bucket = str(etf.get("bucket") or "hot")
        bars = store.list_bars(code, limit=320)
        shares = store.list_shares(code, limit=800)
        as_of = _latest_as_of(code)
        if not as_of:
            continue

        # 回测末若仍持仓，用该入场价评估减仓；否则按未持仓评估加仓
        open_pos = None
        code_bt = (per_code.get(code) or {}).get(primary) or {}
        # 重新跑一次窗口末状态太重；用 backtest_code 的 open 需在 run 时保留。
        # 简化：live 默认未持仓看加仓；同时给 reduce 条件用「假设已持有」检查表。
        dec = decide(
            as_of=as_of,
            bars=bars,
            shares=shares,
            bucket=bucket,
            in_position=False,
            entry_price=None,
            rules=active_rules(),
        )
        # 另算「若已持仓」减仓探针：用 20 日前收盘近似入场（仅作风险提示，不作为回测）
        reduce_probe = None
        if len(bars) > 21 and bars[-21].get("close"):
            reduce_probe = decide(
                as_of=as_of,
                bars=bars,
                shares=shares,
                bucket=bucket,
                in_position=True,
                entry_price=float(bars[-21]["close"]),
                hold_days=20,
                rules=active_rules(),
            )

        action = dec["action"]
        gated = False
        gate_note = None
        if action == "add" and not validated:
            gated = True
            gate_note = "测试窗未达门控（胜率≥80%，均收益≥2.5%），今日不推加仓"
            action = "hold"
            dec = {
                **dec,
                "action": "hold",
                "blockers": list(dec.get("blockers") or []) + [gate_note],
                "reasons": list(dec.get("reasons") or []) + [gate_note],
            }

        # 若点位未加仓，但「若持有」探针触发减仓，抬升为 reduce 提示
        if action == "hold" and reduce_probe and reduce_probe.get("action") == "reduce":
            action = "reduce"
            dec = {
                **reduce_probe,
                "action": "reduce",
                "reasons": ["【若已持有】" + r for r in (reduce_probe.get("reasons") or [])],
            }

        m252 = ((per_code.get(code) or {}).get("252") or {}).get("metrics") or {}
        actions.append(
            {
                "code": code,
                "name": etf.get("name"),
                "bucket": bucket,
                "as_of": as_of,
                "action": action,
                "action_label": ACTION_LABEL.get(action, action),
                "priority": dec.get("priority"),
                "fitness": dec.get("fitness"),
                "reasons": dec.get("reasons") or [],
                "blockers": dec.get("blockers") or [],
                "checks": dec.get("checks") or [],
                "features": dec.get("features") or {},
                "gated_add": gated,
                "gate_note": gate_note,
                "code_backtest": {
                    "win_rate": m252.get("win_rate"),
                    "avg_return": m252.get("avg_return"),
                    "trades": m252.get("trades"),
                    "validated": m252.get("validated"),
                },
            }
        )

    order = {"add": 0, "reduce": 1, "hold": 2}
    actions.sort(
        key=lambda a: (
            order.get(a["action"], 9),
            -(a.get("fitness") or 0),
            a.get("code") or "",
        )
    )
    return {
        "validated": validated,
        "disclosure": backtest.get("disclosure"),
        "gate": backtest.get("gate"),
        "primary_window": backtest.get("primary_window"),
        "benchmark": backtest.get("benchmark"),
        "by_window": {
            k: {
                "window": v.get("window"),
                "metrics": v.get("metrics"),
                "train_metrics": v.get("train_metrics"),
                "trades_preview": (v.get("trades") or [])[:8],
                "train_codes": v.get("train_codes") or v.get("codes"),
            }
            for k, v in (backtest.get("by_window") or {}).items()
        },
        "train_universe_size": backtest.get("train_universe_size"),
        "actions": actions,
        "add_count": sum(1 for a in actions if a["action"] == "add"),
        "reduce_count": sum(1 for a in actions if a["action"] == "reduce"),
        "updated_at": store.utc_now_iso(),
    }


def build_code_timing(code: str, etf: dict[str, Any], backtest: dict[str, Any]) -> dict[str, Any]:
    live = build_live_actions([etf], backtest)
    row = next((a for a in live["actions"] if a["code"] == code), None)
    primary = str(backtest.get("primary_window") or 252)
    hist = (backtest.get("per_code") or {}).get(code) or {}
    # 附带该票完整交易列表（一年）
    bt = backtest_code(code, bucket=str(etf.get("bucket") or "hot"), window=int(primary))
    return {
        "live": row,
        "validated_pool": bool(backtest.get("validated")),
        "windows": hist,
        "trades": bt.get("trades") or [],
        "metrics": (bt.get("metrics") or {}),
        "disclosure": backtest.get("disclosure"),
    }
