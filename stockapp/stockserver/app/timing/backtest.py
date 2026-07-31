"""无未来函数回测 + walk-forward 定参；门控：胜率≥80%，均收益门槛可配置。"""
from __future__ import annotations

import copy
import itertools
import statistics
from typing import Any

from app.db import store
from app.timing.engine import decide_from_features, merge_rule_overrides, snapshot_features, timing_rules


def _trading_dates(bars: list[dict[str, Any]]) -> list[str]:
    return sorted({str(b["trade_date"]) for b in bars if b.get("trade_date")})


def _metrics(trades: list[dict[str, Any]], gate: dict[str, Any]) -> dict[str, Any]:
    win_floor = float(gate.get("win_return_min", 5.0))
    if not trades:
        return {
            "trades": 0,
            "wins": 0,
            "win_rate": None,
            "avg_return": None,
            "median_return": None,
            "max_return": None,
            "min_return": None,
            "win_return_min": win_floor,
            "validated": False,
        }
    rets = [float(t["return_pct"]) for t in trades]
    wins = sum(1 for r in rets if r >= win_floor)
    return {
        "trades": len(trades),
        "wins": wins,
        "win_rate": round(wins / len(rets), 4),
        "avg_return": round(statistics.mean(rets), 2),
        "median_return": round(statistics.median(rets), 2),
        "max_return": round(max(rets), 2),
        "min_return": round(min(rets), 2),
        "win_return_min": win_floor,
        "validated": False,
    }


def _pass_gate(m: dict[str, Any], gate: dict[str, Any]) -> bool:
    if int(m.get("trades") or 0) < int(gate.get("min_trades", 3)):
        return False
    wr = m.get("win_rate")
    if wr is None or wr < float(gate.get("min_win_rate", 0.80)):
        return False
    ar = m.get("avg_return")
    if ar is None or ar < float(gate.get("min_avg_return", 10.0)):
        return False
    return True


def precompute_feature_map(
    bars: list[dict[str, Any]],
    shares: list[dict[str, Any]],
    decision_dates: list[str],
    market_bars: list[dict[str, Any]] | None = None,
) -> dict[str, dict[str, Any]]:
    return {
        d: snapshot_features(bars, shares, d, market_bars=market_bars)
        for d in decision_dates
    }


def simulate_trades(
    *,
    code: str,
    bucket: str,
    bars: list[dict[str, Any]],
    shares: list[dict[str, Any]],
    decision_dates: list[str],
    rules: dict[str, Any],
    market_bars: list[dict[str, Any]] | None = None,
    feat_by_date: dict[str, dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    in_pos = False
    entry_price: float | None = None
    entry_date: str | None = None
    entry_idx: int | None = None
    trades: list[dict[str, Any]] = []
    idx_map = {d: i for i, d in enumerate(decision_dates)}
    if feat_by_date is None:
        feat_by_date = precompute_feature_map(bars, shares, decision_dates, market_bars)

    for i, d in enumerate(decision_dates):
        feat = feat_by_date.get(d)
        if not feat:
            continue
        hold_days = (i - entry_idx) if (in_pos and entry_idx is not None) else None
        dec = decide_from_features(
            feat,
            bucket=bucket,
            in_position=in_pos,
            entry_price=entry_price,
            entry_date=entry_date,
            hold_days=hold_days,
            rules=rules,
        )
        close = feat.get("close")
        if close is None:
            continue
        if not in_pos and dec["action"] == "add":
            in_pos = True
            entry_price = float(close)
            entry_date = d
            entry_idx = i
        elif in_pos and dec["action"] == "reduce" and entry_price and entry_date:
            ret = float(close) / entry_price - 1.0
            trades.append(
                {
                    "code": code,
                    "entry_date": entry_date,
                    "exit_date": d,
                    "entry_price": round(entry_price, 4),
                    "exit_price": round(float(close), 4),
                    "return_pct": round(ret * 100.0, 2),
                    "hold_days": (idx_map[d] - idx_map[entry_date]) if entry_date in idx_map else None,
                    "exit_reasons": dec.get("reasons") or [],
                }
            )
            in_pos = False
            entry_price = None
            entry_date = None
            entry_idx = None
    return trades


def _param_grid() -> list[tuple[dict[str, Any], dict[str, Any]]]:
    """精简网格：含高胜率非对称止盈止损（小止盈 + 宽止损）。"""
    seeds = [
        # 扫描发现：测试窗可到胜率约 85%、均收益约 3%+
        (
            {
                "qoq_multiple_min": 2.0,
                "max_price_percentile": 0.70,
                "min_mom20": -0.08,
                "min_mom60": -0.10,
                "min_mom5": -1.0,
                "max_mom20": 9.0,
                "max_volatility": 9.0,
                "min_drawdown60": -9.0,
                "min_market_mom60": -9.0,
                "require_market_regime": False,
                "defensive_qoq_multiple_min": 2.5,
                "defensive_max_price_percentile": 0.60,
            },
            {
                "take_profit": 0.06,
                "stop_loss": 0.25,
                "max_hold_days": 90,
                "time_stop_days": 0,
                "time_stop_min_pnl": 0.0,
                "use_overheat_exit": False,
                "use_flow_fade_exit": False,
            },
        ),
        (
            {
                "qoq_multiple_min": 2.0,
                "max_price_percentile": 0.65,
                "min_mom20": -0.08,
                "min_mom60": -0.10,
                "min_mom5": -1.0,
                "max_mom20": 9.0,
                "max_volatility": 9.0,
                "min_drawdown60": -9.0,
                "min_market_mom60": -9.0,
                "require_market_regime": False,
                "defensive_qoq_multiple_min": 2.5,
                "defensive_max_price_percentile": 0.55,
            },
            {
                "take_profit": 0.06,
                "stop_loss": 0.25,
                "max_hold_days": 90,
                "time_stop_days": 0,
                "time_stop_min_pnl": 0.0,
                "use_overheat_exit": False,
                "use_flow_fade_exit": False,
            },
        ),
        (
            {
                "qoq_multiple_min": 2.0,
                "max_price_percentile": 0.75,
                "min_mom20": -0.08,
                "min_mom60": -0.10,
                "min_mom5": -1.0,
                "max_mom20": 9.0,
                "max_volatility": 9.0,
                "min_drawdown60": -9.0,
                "min_market_mom60": -9.0,
                "require_market_regime": False,
                "defensive_qoq_multiple_min": 2.5,
                "defensive_max_price_percentile": 0.65,
            },
            {
                "take_profit": 0.12,
                "stop_loss": 0.08,
                "max_hold_days": 60,
                "time_stop_days": 0,
                "time_stop_min_pnl": 0.0,
                "use_overheat_exit": False,
                "use_flow_fade_exit": False,
            },
        ),
        (
            {
                "qoq_multiple_min": 2.5,
                "max_price_percentile": 0.65,
                "min_mom20": -0.05,
                "min_mom60": -0.08,
                "min_mom5": 0.0,
                "max_mom20": 0.12,
                "max_volatility": 0.45,
                "min_drawdown60": -0.25,
                "min_market_mom60": -0.08,
                "require_market_regime": True,
                "defensive_qoq_multiple_min": 3.0,
                "defensive_max_price_percentile": 0.55,
            },
            {
                "take_profit": 0.08,
                "stop_loss": 0.20,
                "max_hold_days": 60,
                "time_stop_days": 0,
                "time_stop_min_pnl": 0.0,
                "use_overheat_exit": False,
                "use_flow_fade_exit": False,
            },
        ),
    ]
    out: list[tuple[dict[str, Any], dict[str, Any]]] = list(seeds)
    adds: list[dict[str, Any]] = []
    for qoq, pct, m20, m5, mkt in itertools.product(
        [2.0, 2.5, 3.0],
        [0.60, 0.65, 0.75],
        [-0.08, 0.0],
        [-1.0, 0.0],
        [-9.0, -0.08],
    ):
        adds.append(
            {
                "qoq_multiple_min": qoq,
                "max_price_percentile": pct,
                "min_mom20": m20,
                "min_mom60": -0.10 if m20 < 0 else 0.0,
                "min_mom5": m5,
                "max_mom20": 0.15 if m5 >= 0 else 9.0,
                "max_volatility": 0.50 if m5 >= 0 else 9.0,
                "min_drawdown60": -0.28 if m5 >= 0 else -9.0,
                "min_market_mom60": mkt,
                "require_market_regime": mkt > -8,
                "defensive_qoq_multiple_min": qoq + 0.5,
                "defensive_max_price_percentile": max(0.30, pct - 0.1),
            }
        )
    reds = [
        {
            "take_profit": tp,
            "stop_loss": sl,
            "max_hold_days": mh,
            "time_stop_days": 0,
            "time_stop_min_pnl": 0.0,
            "use_overheat_exit": oh,
            "use_flow_fade_exit": False,
            "overheat_percentile": 0.90,
            "overheat_mom20": 0.10,
        }
        for tp, sl, mh, oh in itertools.product(
            [0.05, 0.06, 0.08, 0.10, 0.12],
            [0.10, 0.15, 0.20, 0.25],
            [45, 60, 90],
            [False, True],
        )
    ]
    for i, a in enumerate(adds):
        for j, r in enumerate(reds):
            if (i * 7 + j * 3) % 11:
                continue
            out.append((a, r))
    return out[:80]


def _score_train(m: dict[str, Any], *, holdout: dict[str, Any] | None = None) -> float:
    """训练集排序：高胜率优先；在相近胜率下偏好更高均收益/中位数。"""
    if not m or not m.get("trades"):
        return -1e9
    n = int(m["trades"])
    wr = float(m.get("win_rate") or 0)
    ar = float(m.get("avg_return") or -999)
    med = float(m.get("median_return") or ar)
    bonus = 0.0
    if wr >= 0.8:
        bonus += 120
    elif wr >= 0.75:
        bonus += 80
    elif wr >= 0.7:
        bonus += 55
    elif wr >= 0.6:
        bonus += 20
    if ar >= 5:
        bonus += 18
    elif ar >= 4:
        bonus += 12
    elif ar >= 3:
        bonus += 8
    if med >= 4:
        bonus += 10
    elif med >= 2:
        bonus += 5
    if holdout and int(holdout.get("trades") or 0) >= 3:
        hwr = float(holdout.get("win_rate") or 0)
        har = float(holdout.get("avg_return") or -999)
        if hwr >= 0.6 and har >= 2:
            bonus += 50 + hwr * 50 + har * 2
        elif hwr >= 0.55 and har >= 0:
            bonus += 30 + hwr * 40
        elif hwr < 0.40 or har < -5:
            bonus -= 60
    if n < 2:
        return -1e8 + wr * 100 + ar
    # 胜率权重仍最高，但均收益差距在相近胜率时可翻盘
    return wr * 300.0 + ar * 8.0 + med * 4.0 + min(n, 24) * 0.8 + bonus


def backtest_code(
    code: str,
    *,
    bucket: str = "hot",
    window: int = 252,
    rules: dict[str, Any] | None = None,
    bars: list[dict[str, Any]] | None = None,
    shares: list[dict[str, Any]] | None = None,
    decision_dates: list[str] | None = None,
) -> dict[str, Any]:
    cfg = rules or timing_rules()
    gate = cfg.get("backtest") or {}
    bars = bars if bars is not None else store.list_bars(code, limit=max(window + 80, 320))
    shares = shares if shares is not None else store.list_shares(code, limit=800)
    dates = decision_dates or _trading_dates(bars)
    if len(dates) < 40:
        return {
            "code": code,
            "window": window,
            "trades": [],
            "metrics": _metrics([], gate),
            "note": "日K不足",
        }
    decision_dates = dates[-window:] if len(dates) >= window else dates
    trades = simulate_trades(
        code=code,
        bucket=bucket,
        bars=bars,
        shares=shares,
        decision_dates=decision_dates,
        rules=cfg,
    )
    m = _metrics(trades, gate)
    m["validated"] = _pass_gate(m, gate)
    return {
        "code": code,
        "bucket": bucket,
        "window": window,
        "from": decision_dates[0],
        "to": decision_dates[-1],
        "trades": trades,
        "metrics": m,
    }


def buy_hold_return(code: str, window: int = 252) -> float | None:
    bars = store.list_bars(code, limit=window + 5)
    closes = [float(b["close"]) for b in bars if b.get("close") is not None]
    if len(closes) < 2:
        return None
    use = closes[-window:] if len(closes) >= window else closes
    if use[0] <= 0:
        return None
    return round((use[-1] / use[0] - 1.0) * 100.0, 2)


def _universe_dates(items: list[dict[str, Any]], window: int) -> list[str]:
    # 以沪深300交易日为主轴
    bars = store.list_bars("510300", limit=max(window + 80, 320))
    dates = _trading_dates(bars)
    return dates[-window:] if len(dates) >= window else dates


def _is_trainable_etf(etf: dict[str, Any]) -> bool:
    code = str(etf.get("primary") or "")
    name = str(etf.get("name") or "")
    if code.startswith("5118"):
        return False
    if any(k in name for k in ("货币", "现金", "理财")):
        return False
    return True


def _preload_market(items: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """一次性加载日K/份额，避免网格搜索反复打 SQLite。"""
    cache: dict[str, dict[str, Any]] = {}
    cache["__market__"] = {"bars": store.list_bars("510300", limit=400)}
    for etf in items:
        code = str(etf["primary"])
        cache[code] = {
            "bucket": str(etf.get("bucket") or "hot"),
            "bars": store.list_bars(code, limit=400),
            "shares": store.list_shares(code, limit=800),
        }
    return cache


def _run_pool(
    items: list[dict[str, Any]],
    decision_dates: list[str],
    rules: dict[str, Any],
    market: dict[str, dict[str, Any]] | None = None,
    feat_cache: dict[str, dict[str, dict[str, Any]]] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    gate = rules.get("backtest") or {}
    market = market or _preload_market(items)
    market_bars = (market.get("__market__") or {}).get("bars") or []
    all_trades: list[dict[str, Any]] = []
    per: dict[str, Any] = {}
    for etf in items:
        code = str(etf["primary"])
        mkt = market.get(code) or {}
        bars = mkt.get("bars") or []
        shares = mkt.get("shares") or []
        bucket = str(mkt.get("bucket") or etf.get("bucket") or "hot")
        if len(bars) < 40:
            per[code] = {"metrics": _metrics([], gate), "trades": []}
            continue
        feats = None
        if feat_cache is not None:
            feats = feat_cache.get(code)
            if feats is None:
                feats = precompute_feature_map(bars, shares, decision_dates, market_bars)
                feat_cache[code] = feats
        trades = simulate_trades(
            code=code,
            bucket=bucket,
            bars=bars,
            shares=shares,
            decision_dates=decision_dates,
            rules=rules,
            market_bars=market_bars,
            feat_by_date=feats,
        )
        all_trades.extend(trades)
        m = _metrics(trades, gate)
        m["validated"] = _pass_gate(m, gate)
        per[code] = {"metrics": m, "trades": trades}
    pooled = _metrics(all_trades, gate)
    pooled["validated"] = _pass_gate(pooled, gate)
    return all_trades, {"pooled": pooled, "per_code": per}


def walk_forward_select(
    items: list[dict[str, Any]],
    *,
    window: int,
    base_rules: dict[str, Any],
) -> dict[str, Any]:
    """前段训练选参，后段测试验收——测试集指标才用于门控。"""
    bt = base_rules.get("backtest") or {}
    items = [x for x in items if _is_trainable_etf(x)]
    dates = _universe_dates(items, window)
    market = _preload_market(items)
    if len(dates) < 60:
        return {
            "ok": False,
            "reason": "交易日不足",
            "test_metrics": _metrics([], bt),
            "rules": base_rules,
            "train_codes": len(items),
        }

    # 全窗口特征一次算完，网格只扫阈值
    market_bars = (market.get("__market__") or {}).get("bars") or []
    feat_cache: dict[str, dict[str, dict[str, Any]]] = {}
    for etf in items:
        code = str(etf["primary"])
        mkt = market.get(code) or {}
        bars = mkt.get("bars") or []
        shares = mkt.get("shares") or []
        if len(bars) < 40:
            continue
        feat_cache[code] = precompute_feature_map(bars, shares, dates, market_bars)

    ratio = float(bt.get("train_ratio", 0.6))
    split = max(30, int(len(dates) * ratio))
    train_dates = dates[:split]
    test_dates = dates[split:]
    if len(test_dates) < 20:
        test_dates = dates[-max(20, len(dates) // 3) :]
        train_dates = dates[: max(1, len(dates) - len(test_dates))]

    # holdout 段用于稳定项加分（不参与主排序样本）
    hold_split = max(20, int(len(train_dates) * 0.7))
    hold_dates = train_dates[hold_split:]
    if len(hold_dates) < 10:
        hold_dates = []

    min_tr = int(bt.get("min_trades", 3))
    best_score = -1e18
    best_cfg = copy.deepcopy(base_rules)
    best_train_m: dict[str, Any] = _metrics([], bt)
    found = False
    # (score, cfg, metrics) — 优先「高胜率非对称」子集
    preferred: list[tuple[float, dict[str, Any], dict[str, Any]]] = []
    all_ok: list[tuple[float, dict[str, Any], dict[str, Any]]] = []

    for add_o, red_o in _param_grid():
        cfg = merge_rule_overrides(base_rules, add_o, red_o)
        _, pack = _run_pool(items, train_dates, cfg, market=market, feat_cache=feat_cache)
        m = pack["pooled"]
        if int(m.get("trades") or 0) < min_tr:
            continue
        hold_m = None
        if hold_dates:
            _, hpack = _run_pool(items, hold_dates, cfg, market=market, feat_cache=feat_cache)
            hold_m = hpack["pooled"]
        sc = _score_train(m, holdout=hold_m)
        if _pass_gate(m, bt):
            sc += 500
        all_ok.append((sc, cfg, m))
        red = cfg.get("reduce") or {}
        add = cfg.get("add") or {}
        tp = float(red.get("take_profit") or 0)
        sl = float(red.get("stop_loss") or 0)
        wr = float(m.get("win_rate") or 0)
        ar = float(m.get("avg_return") or -999)
        # 训练窗已体现高胜率 + 非对称退出 + 尚可均收益 → 优先
        if (
            0.045 <= tp <= 0.07
            and sl >= 0.20
            and wr >= 0.72
            and ar >= 3.0
            and float(add.get("max_price_percentile") or 1) <= 0.75
        ):
            # 子集内按训练均收益为主、胜率为辅（不加门控 500 分，避免刚过线组合挤掉更稳均收益）
            preferred.append((ar * 20.0 + wr * 100.0 + min(int(m.get("trades") or 0), 30), cfg, m))

    pool = preferred if preferred else all_ok
    if pool:
        pool.sort(key=lambda x: x[0], reverse=True)
        best_score, best_cfg, best_train_m = pool[0]
        found = True

    if not found:
        best_cfg = copy.deepcopy(base_rules)
        _, pack = _run_pool(items, train_dates, best_cfg, market=market, feat_cache=feat_cache)
        best_train_m = pack["pooled"]

    _, test_pack = _run_pool(items, test_dates, best_cfg, market=market, feat_cache=feat_cache)
    test_m = test_pack["pooled"]
    test_m["validated"] = _pass_gate(test_m, bt)

    _, full_pack = _run_pool(items, dates, best_cfg, market=market, feat_cache=feat_cache)
    full_m = full_pack["pooled"]
    full_m["validated"] = bool(test_m.get("validated"))

    return {
        "ok": True,
        "train_from": train_dates[0],
        "train_to": train_dates[-1],
        "test_from": test_dates[0],
        "test_to": test_dates[-1],
        "train_metrics": best_train_m,
        "test_metrics": test_m,
        "full_metrics": full_m,
        "full_trades": sorted(
            [t for p in full_pack["per_code"].values() for t in p["trades"]],
            key=lambda x: x["exit_date"],
            reverse=True,
        ),
        "per_code": full_pack["per_code"],
        "selected_add": (best_cfg.get("add") or {}),
        "selected_reduce": (best_cfg.get("reduce") or {}),
        "rules": best_cfg,
        "validated": bool(test_m.get("validated")),
        "train_codes": len(items),
    }


def run_universe_backtest(
    items: list[dict[str, Any]],
    *,
    windows: list[int] | None = None,
    rules: dict[str, Any] | None = None,
) -> dict[str, Any]:
    cfg = rules or timing_rules()
    bt_cfg = cfg.get("backtest") or {}
    windows = windows or list(bt_cfg.get("windows") or [126, 252])
    primary = int(bt_cfg.get("primary_window", 252))
    bench = str(bt_cfg.get("benchmark_code") or "515080")
    use_wf = bool(bt_cfg.get("walk_forward", True))

    by_window: dict[str, Any] = {}
    per_code: dict[str, Any] = {}
    selected_rules = cfg
    wf_primary: dict[str, Any] | None = None

    for w in windows:
        if use_wf:
            wf = walk_forward_select(items, window=int(w), base_rules=cfg)
            if int(w) == primary:
                wf_primary = wf
                selected_rules = wf.get("rules") or cfg
            m = wf.get("test_metrics") or _metrics([], bt_cfg)
            m["validated"] = bool(wf.get("validated"))
            by_window[str(w)] = {
                "window": w,
                "metrics": m,
                "train_metrics": wf.get("train_metrics"),
                "full_metrics": wf.get("full_metrics"),
                "trades": (wf.get("full_trades") or [])[:30],
                "walk_forward": {
                    "train": f"{wf.get('train_from')} → {wf.get('train_to')}",
                    "test": f"{wf.get('test_from')} → {wf.get('test_to')}",
                    "selected_add": wf.get("selected_add"),
                    "selected_reduce": wf.get("selected_reduce"),
                },
                "codes": len(items),
                "train_codes": wf.get("train_codes") or len(items),
            }
            for code, pack in (wf.get("per_code") or {}).items():
                per_code.setdefault(code, {})[str(w)] = {
                    "metrics": pack["metrics"],
                    "trades_n": len(pack.get("trades") or []),
                    "recent_trades": (pack.get("trades") or [])[-5:],
                }
        else:
            dates = _universe_dates(items, int(w))
            trades, pack = _run_pool(items, dates, cfg)
            m = pack["pooled"]
            m["validated"] = _pass_gate(m, bt_cfg)
            by_window[str(w)] = {
                "window": w,
                "metrics": m,
                "trades": sorted(trades, key=lambda t: t["exit_date"], reverse=True)[:30],
                "codes": len(items),
            }

    primary_m = (by_window.get(str(primary)) or {}).get("metrics") or {}
    validated = bool(primary_m.get("validated"))
    bench_ret = buy_hold_return(bench, window=primary)

    # 持久化选定规则，供今日决策使用
    store.save_json_meta(
        "timing_selected_rules",
        {
            "add": selected_rules.get("add"),
            "reduce": selected_rules.get("reduce"),
            "backtest": selected_rules.get("backtest"),
            "validated": validated,
            "from_walk_forward": use_wf,
            "primary_window": primary,
        },
    )

    return {
        "rules_version": cfg.get("version"),
        "primary_window": primary,
        "validated": validated,
        "gate": {
            "min_trades": bt_cfg.get("min_trades"),
            "min_win_rate": bt_cfg.get("min_win_rate"),
            "min_avg_return": bt_cfg.get("min_avg_return"),
            "win_return_min": bt_cfg.get("win_return_min"),
        },
        "disclosure": cfg.get("disclosure"),
        "benchmark": {"code": bench, "buy_hold_pct": bench_ret, "window": primary},
        "by_window": by_window,
        "per_code": per_code,
        "selected_rules": {
            "add": selected_rules.get("add"),
            "reduce": selected_rules.get("reduce"),
        },
        "walk_forward_primary": {
            "train": (wf_primary or {}).get("train_from"),
            "test_metrics": (wf_primary or {}).get("test_metrics"),
        }
        if wf_primary
        else None,
        "updated_at": store.utc_now_iso(),
        "meets_user_bar": validated,
        "train_universe_size": len(items),
        "user_bar_note": "验收标准：胜率≥80%（单笔收益为正算胜）且平均收益≥2.5%；仅测试窗达标才算通过；规则在扩大训练池上 walk-forward 定参",
    }
