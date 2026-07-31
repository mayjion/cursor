from __future__ import annotations

from typing import Any

from app.collectors.yahoo_proxy import PROXY_MAP, ext_code
from app.db import store
from app.factors.engine import compute_public_factors, price_percentile


def _signal(score: float) -> str:
    if score >= 70:
        return "green"
    if score >= 40:
        return "yellow"
    return "red"


def _load_proxy_bars(factor_cfg: list[dict[str, Any]]) -> dict[str, list[list[dict[str, Any]]]]:
    needed = {
        str(f.get("id"))
        for f in factor_cfg
        if str(f.get("source")) == "proxy" and str(f.get("id")) in PROXY_MAP
    }
    out: dict[str, list[list[dict[str, Any]]]] = {}
    for fid in needed:
        series: list[list[dict[str, Any]]] = []
        for sym in PROXY_MAP[fid]:
            bars = store.list_bars(ext_code(sym), limit=320)
            if bars:
                series.append(bars)
        if series:
            out[fid] = series
    return out


def score_etf(code: str, factor_cfg: list[dict[str, Any]]) -> dict[str, Any]:
    bars = store.list_bars(code, limit=320)
    shares = store.list_shares(code, limit=500)
    proxy_bars = _load_proxy_bars(factor_cfg)
    computed = compute_public_factors(bars, shares, proxy_bars=proxy_bars)

    details: list[dict[str, Any]] = []
    num = 0.0
    den = 0.0
    for f in factor_cfg:
        fid = str(f.get("id") or "")
        src = str(f.get("source") or "stub")
        weight = float(f.get("weight") or 0)
        name = str(f.get("name") or fid)
        if src == "stub" or weight <= 0:
            details.append(
                {
                    "id": fid,
                    "name": name,
                    "source": src,
                    "weight": weight,
                    "score": None,
                    "raw": None,
                    "used": False,
                    "note": "占位/未实现",
                }
            )
            continue
        hit = computed.get(fid)
        if not hit or hit.get("score") is None:
            details.append(
                {
                    "id": fid,
                    "name": name,
                    "source": src,
                    "weight": weight,
                    "score": None,
                    "raw": None if not hit else hit.get("raw"),
                    "used": False,
                    "note": (hit or {}).get("note") or "数据不足",
                }
            )
            continue
        s = float(hit["score"])
        num += s * weight
        den += weight
        details.append(
            {
                "id": fid,
                "name": name,
                "source": hit.get("source") or src,
                "weight": weight,
                "score": round(s, 1),
                "raw": hit.get("raw"),
                "used": True,
                "note": hit.get("note"),
            }
        )

    score = round(num / den, 1) if den > 0 else 50.0
    return {
        "code": code,
        "score": score,
        "signal": _signal(score),
        "factor_json": details,
        "temperature_contrib": None,
        "updated_at": store.utc_now_iso(),
    }


def market_temperature(hs300_code: str = "510300") -> dict[str, Any]:
    """用沪深300近一年价格分位作市场温度（公开代理）。"""
    bars = store.list_bars(hs300_code, limit=320)
    pct = price_percentile(bars, 250)
    if pct is None:
        return {
            "celsius": 50.0,
            "zone": "中性",
            "allocation_hint": "高景气50% : 稳健50%",
            "basis": "暂无足够日K，温度占位 50°C",
            "price_percentile": None,
        }
    temp = round(pct * 100.0, 1)
    if temp < 30:
        zone = "偏低/偏冷"
        alloc = "高景气70% : 稳健30%"
    elif temp < 70:
        zone = "中性"
        alloc = "高景气50% : 稳健50%"
    else:
        zone = "偏热"
        alloc = "高景气30% : 稳健70%"
    return {
        "celsius": temp,
        "zone": zone,
        "allocation_hint": alloc,
        "basis": "沪深300近一年收盘价分位（公开代理估值温度）",
        "price_percentile": round(pct, 4),
    }


def rescore_universe(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for etf in items:
        code = str(etf["primary"])
        row = score_etf(code, etf.get("factors") or [])
        store.upsert_score(row)
        store.append_score_history(code, float(row["score"]), str(row["signal"]))
        snap = store.get_snapshot(code)
        if snap:
            snap["score"] = row["score"]
            snap["signal"] = row["signal"]
            store.upsert_snapshot(snap)
        out.append(row)
    store.set_meta("last_score_at", store.utc_now_iso())
    return out
