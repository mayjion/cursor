"""赛道轮动：按评分与市场温度分配权重，单票夹在 2%–20%。"""
from __future__ import annotations

from typing import Any

from app.db import store


def _hot_defensive_split(temp_celsius: float) -> tuple[float, float]:
    if temp_celsius < 30:
        return 0.70, 0.30
    if temp_celsius < 70:
        return 0.50, 0.50
    return 0.30, 0.70


def _allocate_bucket(
    cards: list[dict[str, Any]],
    bucket_weight: float,
    *,
    min_w: float = 0.02,
    max_w: float = 0.20,
) -> list[dict[str, Any]]:
    if not cards or bucket_weight <= 0:
        return []
    # 评分地板，避免全红时权重塌缩
    raw = [max(5.0, float(c.get("score") or 0)) for c in cards]
    total = sum(raw) or 1.0
    # 先按比例，再夹紧到单票上下限，最后归一化到 bucket_weight
    weights = [bucket_weight * (r / total) for r in raw]
    n = len(weights)
    lo = min(min_w, bucket_weight / n)
    hi = min(max_w, bucket_weight)

    for _ in range(8):
        clipped = [max(lo, min(hi, w)) for w in weights]
        s = sum(clipped)
        if abs(s - bucket_weight) < 1e-9:
            weights = clipped
            break
        # 把差额按未触边项分配
        free_idx = [
            i
            for i, w in enumerate(clipped)
            if lo < w < hi or (w == lo and s < bucket_weight) or (w == hi and s > bucket_weight)
        ]
        if not free_idx:
            weights = [bucket_weight / n] * n
            break
        diff = bucket_weight - s
        add = diff / len(free_idx)
        weights = list(clipped)
        for i in free_idx:
            weights[i] = max(lo, min(hi, weights[i] + add))

    # 最终再归一一次（夹紧后可能略偏）
    s = sum(weights) or 1.0
    weights = [w / s * bucket_weight for w in weights]

    out = []
    for c, w in zip(cards, weights):
        out.append(
            {
                "code": c["code"],
                "name": c.get("name"),
                "bucket": c.get("bucket"),
                "score": c.get("score"),
                "signal": c.get("signal"),
                "change_pct": c.get("change_pct"),
                "weight": round(w * 100.0, 2),
                "weight_frac": round(w, 6),
            }
        )
    return out


def _close_map(code: str, limit: int = 260) -> dict[str, float]:
    out: dict[str, float] = {}
    for b in store.list_bars(code, limit=limit):
        if b.get("close") is None or not b.get("trade_date"):
            continue
        out[str(b["trade_date"])] = float(b["close"])
    return out


def build_return_curve(
    rows: list[dict[str, Any]],
    *,
    lookback: int = 120,
) -> dict[str, Any]:
    """
    用「当前建议权重」对历史日K做静态回测组合收益。
    说明：非动态调仓实盘；展示若按今日权重持有，历史净值与当日组合涨跌。
    """
    if not rows:
        return {
            "note": "暂无权重",
            "today_pct": None,
            "curve": [],
            "stats": {},
        }

    weights = {str(r["code"]): float(r["weight_frac"]) for r in rows if r.get("weight_frac")}
    series = {code: _close_map(code, limit=lookback + 5) for code in weights}
    date_sets = [set(s.keys()) for s in series.values() if s]
    if not date_sets:
        return {
            "note": "缺少日K，无法画收益曲线",
            "today_pct": None,
            "curve": [],
            "stats": {},
        }
    all_dates = sorted(set().union(*date_sets))
    usable: list[str] = []
    for d in all_dates:
        covered = sum(weights[c] for c, s in series.items() if d in s)
        if covered >= 0.85:
            usable.append(d)
    usable = usable[-(lookback + 1) :]
    if len(usable) < 3:
        return {
            "note": "可对齐交易日不足",
            "today_pct": None,
            "curve": [],
            "stats": {},
        }

    daily_rets: list[dict[str, Any]] = []
    nav = 1.0
    curve: list[dict[str, Any]] = [{"date": usable[0], "nav": 1.0, "daily_pct": 0.0}]
    for i in range(1, len(usable)):
        d0, d1 = usable[i - 1], usable[i]
        port_ret = 0.0
        w_used = 0.0
        for code, w in weights.items():
            s = series[code]
            if d0 in s and d1 in s and s[d0] > 0:
                port_ret += w * (s[d1] / s[d0] - 1.0)
                w_used += w
        if w_used > 0 and abs(w_used - 1.0) > 1e-6:
            port_ret = port_ret / w_used
        nav *= 1.0 + port_ret
        daily_rets.append({"date": d1, "daily_pct": round(port_ret * 100.0, 4)})
        curve.append(
            {
                "date": d1,
                "nav": round(nav, 6),
                "daily_pct": round(port_ret * 100.0, 4),
                "cum_pct": round((nav - 1.0) * 100.0, 4),
            }
        )

    today_pct: float | None = 0.0
    today_w = 0.0
    today_parts: list[dict[str, Any]] = []
    for r in rows:
        chg = r.get("change_pct")
        if chg is None:
            snap = store.get_snapshot(str(r["code"])) or {}
            chg = snap.get("change_pct")
        if chg is None:
            continue
        w = float(r["weight_frac"])
        today_pct += w * float(chg)
        today_w += w
        today_parts.append(
            {
                "code": r["code"],
                "name": r.get("name"),
                "weight": r.get("weight"),
                "change_pct": round(float(chg), 4),
                "contrib_pct": round(w * float(chg), 4),
            }
        )
    if today_w > 0 and abs(today_w - 1.0) > 1e-6:
        today_pct = today_pct / today_w
    elif today_w <= 0 and curve:
        today_pct = float(curve[-1].get("daily_pct") or 0.0)
    elif today_w <= 0:
        today_pct = None

    if today_pct is not None and today_w > 0:
        today_pct = round(float(today_pct), 4)

    def _window_pct(n: int) -> float | None:
        if len(curve) <= n:
            if len(curve) < 2:
                return None
            return round((curve[-1]["nav"] / curve[0]["nav"] - 1.0) * 100.0, 2)
        return round((curve[-1]["nav"] / curve[-(n + 1)]["nav"] - 1.0) * 100.0, 2)

    stats = {
        "today_pct": today_pct,
        "d5_pct": _window_pct(5),
        "d20_pct": _window_pct(20),
        "d60_pct": _window_pct(60),
        "full_pct": round((curve[-1]["nav"] - 1.0) * 100.0, 2) if curve else None,
        "points": len(curve),
        "from": curve[0]["date"] if curve else None,
        "to": curve[-1]["date"] if curve else None,
    }

    if curve and today_pct is not None and today_w > 0:
        curve[-1] = {
            **curve[-1],
            "today_mark": True,
            "today_pct": today_pct,
        }

    return {
        "note": "按当前建议权重静态加权回测（非历史动态调仓）；当日为快照涨跌幅加权",
        "today_pct": today_pct,
        "today_parts": sorted(today_parts, key=lambda x: abs(x["contrib_pct"]), reverse=True),
        "curve": curve,
        "daily": daily_rets[-60:],
        "stats": stats,
    }


def build_allocation(
    hot: list[dict[str, Any]],
    defensive: list[dict[str, Any]],
    temperature: dict[str, Any],
) -> dict[str, Any]:
    temp = float(temperature.get("celsius") or 50.0)
    hot_w, def_w = _hot_defensive_split(temp)
    hot_alloc = _allocate_bucket(hot, hot_w)
    def_alloc = _allocate_bucket(defensive, def_w, min_w=0.05, max_w=0.35)
    rows = sorted(hot_alloc + def_alloc, key=lambda x: x["weight"], reverse=True)
    returns = build_return_curve(rows, lookback=120)
    return {
        "hot_pct": round(hot_w * 100.0, 1),
        "defensive_pct": round(def_w * 100.0, 1),
        "temperature_celsius": temp,
        "rule": "单票高景气 2%–20%；稳健 5%–35%；按评分加权后夹紧再归一",
        "rows": rows,
        "returns": returns,
    }
