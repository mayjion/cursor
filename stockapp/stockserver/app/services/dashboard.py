from __future__ import annotations

from typing import Any

from app.alerts.engine import evaluate_alerts
from app.allocation.engine import build_allocation
from app.collectors import eastmoney_kline, eastmoney_quote, eastmoney_shares, yahoo_proxy
from app.config import SETTINGS, events, universe
from app.db import store
from app.scoring import engine as scoring
from app.services import timing as timing_svc


def _all_etf_items() -> list[dict[str, Any]]:
    u = universe()
    items: list[dict[str, Any]] = []
    for bucket, kind in (("hot", "hot"), ("defensive", "defensive")):
        for etf in u.get(bucket, []) or []:
            items.append({**etf, "bucket": kind})
    return items


def primary_codes() -> list[str]:
    return [str(e["primary"]) for e in _all_etf_items()]


def build_universe_payload() -> dict[str, Any]:
    u = universe()
    return {
        "version": u.get("version"),
        "hot": u.get("hot", []),
        "defensive": u.get("defensive", []),
        "data_policy": "public_only",
    }


def _light(signal: str) -> str:
    return {"green": "绿灯", "yellow": "黄灯", "red": "红灯"}.get(signal, "黄灯")


def _cards_from_store() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    snaps = {s["code"]: s for s in store.list_snapshots()}
    scores = {s["code"]: s for s in store.list_scores()}
    cards: list[dict[str, Any]] = []
    for etf in _all_etf_items():
        code = str(etf["primary"])
        snap = snaps.get(code) or {}
        sc = scores.get(code) or {}
        signal = sc.get("signal") or snap.get("signal") or "yellow"
        score = sc.get("score") if sc.get("score") is not None else snap.get("score", 50.0)
        cards.append(
            {
                "id": etf.get("id"),
                "bucket": etf.get("bucket"),
                "name": etf.get("name"),
                "logic": etf.get("logic"),
                "code": code,
                "alternates": etf.get("alternates") or [],
                "quote_name": snap.get("name") or etf.get("name"),
                "price": snap.get("price"),
                "change_pct": snap.get("change_pct"),
                "score": score,
                "signal": signal,
                "signal_label": _light(signal),
                "updated_at": sc.get("updated_at") or snap.get("updated_at"),
                "factors": sc.get("factors") or etf.get("factors") or [],
            }
        )
    hot = [c for c in cards if c["bucket"] == "hot"]
    defensive = [c for c in cards if c["bucket"] == "defensive"]
    return hot, defensive


async def collect_and_score(*, force_quote: bool = False) -> dict[str, Any]:
    codes = primary_codes()
    quotes = await eastmoney_quote.refresh_codes(codes)
    bars_n = await eastmoney_kline.refresh_bars(codes, limit=320)
    shares_n = await eastmoney_shares.refresh_shares(codes, limit=500)
    ext = await yahoo_proxy.refresh_external_proxies()
    scores = scoring.rescore_universe(_all_etf_items())
    hot, defensive = _cards_from_store()
    temp = scoring.market_temperature("510300")
    allocation = build_allocation(hot, defensive, temp)
    alerts = evaluate_alerts(hot + defensive)
    store.save_alerts_cache(alerts)
    store.set_meta("last_allocation_at", store.utc_now_iso())
    bt = timing_svc.ensure_backtest(_all_etf_items(), force=True)
    return {
        "quotes": len(quotes),
        "bars": bars_n,
        "shares": shares_n,
        "ext": ext,
        "scores": len(scores),
        "alerts": len(alerts),
        "allocation_rows": len(allocation["rows"]),
        "timing_validated": bt.get("validated"),
        "at": store.utc_now_iso(),
    }


async def ensure_data(force: bool = False) -> None:
    has_bars = bool(store.list_bars("510300", limit=5))
    has_scores = bool(store.list_scores())
    if force or not has_bars or not has_scores:
        await collect_and_score(force_quote=True)
        return
    if not eastmoney_quote.cache_fresh() or not store.list_snapshots():
        await eastmoney_quote.refresh_codes(primary_codes())
        scoring.rescore_universe(_all_etf_items())
        hot, defensive = _cards_from_store()
        alerts = evaluate_alerts(hot + defensive)
        store.save_alerts_cache(alerts)
    timing_svc.ensure_backtest(_all_etf_items(), force=False)


async def build_dashboard(force_refresh: bool = False) -> dict[str, Any]:
    await ensure_data(force=force_refresh)
    hot, defensive = _cards_from_store()
    temperature = scoring.market_temperature("510300")
    allocation = build_allocation(hot, defensive, temperature)
    alerts, alerts_at = store.load_alerts_cache()
    if not alerts:
        alerts = evaluate_alerts(hot + defensive)
        store.save_alerts_cache(alerts)
        alerts_at = store.utc_now_iso()
    wmap = {r["code"]: r["weight"] for r in allocation["rows"]}
    for c in hot + defensive:
        c["alloc_weight"] = wmap.get(c["code"])

    items = _all_etf_items()
    backtest = timing_svc.ensure_backtest(items, force=force_refresh)
    timing = timing_svc.build_live_actions(items, backtest)
    # 把 timing action 挂到卡片
    amap = {a["code"]: a for a in timing["actions"]}
    for c in hot + defensive:
        a = amap.get(c["code"])
        if a:
            c["timing_action"] = a["action"]
            c["timing_label"] = a["action_label"]
            c["timing_fitness"] = a["fitness"]

    return {
        "disclaimer": SETTINGS.get("disclaimer"),
        "data_policy": "全部公开数据，零付费源",
        "phase": "C+",
        "last_snapshot_at": store.get_meta("last_snapshot_at"),
        "last_bars_at": store.get_meta("last_bars_at"),
        "last_shares_at": store.get_meta("last_shares_at"),
        "last_ext_at": store.get_meta("last_ext_at"),
        "last_score_at": store.get_meta("last_score_at"),
        "last_alerts_at": alerts_at,
        "last_timing_backtest_at": store.get_meta("last_timing_backtest_at"),
        "temperature": temperature,
        "timing": timing,
        "allocation": allocation,
        "alerts": alerts[:12],
        "alert_count": len(alerts),
        "hot": hot,
        "defensive": defensive,
        "events": (events().get("events") or [])[:20],
    }


async def build_etf_detail(code: str, force_refresh: bool = False) -> dict[str, Any] | None:
    etf = next((e for e in _all_etf_items() if str(e["primary"]) == code), None)
    if etf is None:
        return None
    await ensure_data(force=force_refresh)
    snap = store.get_snapshot(code) or {}
    sc = store.get_score(code) or {}
    bars = store.list_bars(code, limit=120)
    signal = sc.get("signal") or snap.get("signal") or "yellow"
    score = sc.get("score") if sc.get("score") is not None else snap.get("score", 50.0)
    closes = [
        {"date": b["trade_date"], "close": b["close"]}
        for b in bars
        if b.get("close") is not None
    ]
    hot, defensive = _cards_from_store()
    allocation = build_allocation(hot, defensive, scoring.market_temperature("510300"))
    weight = next((r["weight"] for r in allocation["rows"] if r["code"] == code), None)
    backtest = timing_svc.ensure_backtest(_all_etf_items(), force=False)
    timing = timing_svc.build_code_timing(code, etf, backtest)
    return {
        "id": etf.get("id"),
        "bucket": etf.get("bucket"),
        "name": etf.get("name"),
        "logic": etf.get("logic"),
        "code": code,
        "alternates": etf.get("alternates") or [],
        "quote_name": snap.get("name") or etf.get("name"),
        "price": snap.get("price"),
        "change_pct": snap.get("change_pct"),
        "amount": snap.get("amount"),
        "score": score,
        "signal": signal,
        "signal_label": _light(signal),
        "alloc_weight": weight,
        "updated_at": sc.get("updated_at") or snap.get("updated_at"),
        "factors": sc.get("factors") or etf.get("factors") or [],
        "closes": closes,
        "score_history": store.list_score_history(code, limit=30),
        "timing": timing,
        "disclaimer": SETTINGS.get("disclaimer"),
    }


async def build_alerts(force_refresh: bool = False) -> dict[str, Any]:
    await ensure_data(force=force_refresh)
    hot, defensive = _cards_from_store()
    alerts = evaluate_alerts(hot + defensive)
    store.save_alerts_cache(alerts)
    return {
        "phase": "C+",
        "updated_at": store.utc_now_iso(),
        "count": len(alerts),
        "alerts": alerts,
        "disclaimer": SETTINGS.get("disclaimer"),
    }


async def build_timing(force_refresh: bool = False) -> dict[str, Any]:
    await ensure_data(force=force_refresh)
    items = _all_etf_items()
    backtest = timing_svc.ensure_backtest(items, force=force_refresh)
    return timing_svc.build_live_actions(items, backtest)


async def build_timing_backtest(window: int | None = None, force: bool = False) -> dict[str, Any]:
    await ensure_data(force=False)
    items = _all_etf_items()
    backtest = timing_svc.ensure_backtest(items, force=force)
    if window is None:
        return backtest
    w = str(window)
    return {
        "window": window,
        "validated_pool": backtest.get("validated"),
        "slice": (backtest.get("by_window") or {}).get(w),
        "per_code": {
            code: (windows or {}).get(w)
            for code, windows in (backtest.get("per_code") or {}).items()
        },
        "disclosure": backtest.get("disclosure"),
        "updated_at": backtest.get("updated_at"),
    }
