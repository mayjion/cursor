from __future__ import annotations

import asyncio
import json
import time
from typing import Any

import httpx

from app.config import SETTINGS
from app.db import store

# 东财公开字段：最新价/名称/涨跌幅/成交额 等
_QUOTE_FIELDS = "f57,f58,f43,f169,f170,f46,f44,f45,f47,f48,f60,f116"


def market_from_code(code: str) -> str:
    if code.startswith(("5", "6", "9")) or code.startswith(("11", "13")):
        return "sh"
    return "sz"


def secid_from_code(code: str) -> str:
    return f"1.{code}" if market_from_code(code) == "sh" else f"0.{code}"


def _signal_from_change(change_pct: float | None) -> str:
    if change_pct is None:
        return "yellow"
    if change_pct >= 1.5:
        return "green"
    if change_pct <= -1.5:
        return "red"
    return "yellow"


def _placeholder_score(change_pct: float | None) -> float:
    """Phase A：用涨跌幅映射到 0-100 占位分；Phase B 换成真实因子引擎。"""
    if change_pct is None:
        return 50.0
    # -5%~+5% → 约 25~75，再夹紧
    score = 50.0 + change_pct * 5.0
    return round(max(0.0, min(100.0, score)), 1)


async def fetch_quote(client: httpx.AsyncClient, code: str) -> dict[str, Any]:
    uri = "https://push2.eastmoney.com/api/qt/stock/get"
    params = {
        "secid": secid_from_code(code),
        "fltt": "2",
        "fields": _QUOTE_FIELDS,
        "ut": "fa5fd1943c7b386f172d6893dbfba10b",
    }
    resp = await client.get(uri, params=params, timeout=15.0)
    resp.raise_for_status()
    data = resp.json().get("data") or {}
    price = data.get("f43")
    change_pct = data.get("f170")
    try:
        price_f = float(price) if price is not None else None
    except (TypeError, ValueError):
        price_f = None
    try:
        chg_f = float(change_pct) if change_pct is not None else None
    except (TypeError, ValueError):
        chg_f = None
    try:
        amount = float(data.get("f48")) if data.get("f48") is not None else None
    except (TypeError, ValueError):
        amount = None

    name = str(data.get("f58") or code)
    score = _placeholder_score(chg_f)
    signal = _signal_from_change(chg_f)
    return {
        "code": code,
        "name": name,
        "price": price_f,
        "change_pct": chg_f,
        "amount": amount,
        "score": score,
        "signal": signal,
        "updated_at": store.utc_now_iso(),
        "raw_json": json.dumps(data, ensure_ascii=False),
    }


async def refresh_codes(codes: list[str]) -> list[dict[str, Any]]:
    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    out: list[dict[str, Any]] = []
    async with httpx.AsyncClient(
        headers={
            "User-Agent": "Mozilla/5.0 stockserver/0.1 (personal research)",
            "Referer": "https://quote.eastmoney.com/",
        }
    ) as client:
        for i, code in enumerate(codes):
            try:
                row = await fetch_quote(client, code)
                store.upsert_snapshot(row)
                out.append(row)
            except Exception as exc:  # noqa: BLE001 — 单票失败不中断
                existing = store.get_snapshot(code) or {
                    "code": code,
                    "name": code,
                    "price": None,
                    "change_pct": None,
                    "amount": None,
                    "score": 50.0,
                    "signal": "yellow",
                    "updated_at": store.utc_now_iso(),
                    "raw_json": "{}",
                }
                existing["error"] = str(exc)
                out.append(existing)
            if i + 1 < len(codes) and gap > 0:
                await asyncio.sleep(gap)
    store.set_meta("last_snapshot_at", store.utc_now_iso())
    store.set_meta("last_snapshot_count", str(len(out)))
    return out


def refresh_codes_sync(codes: list[str]) -> list[dict[str, Any]]:
    return asyncio.run(refresh_codes(codes))


def cache_fresh(ttl_sec: int | None = None) -> bool:
    ttl = ttl_sec if ttl_sec is not None else int(SETTINGS.get("snapshot_cache_ttl_sec", 300))
    ts = store.get_meta("last_snapshot_at")
    if not ts:
        return False
    try:
        # 粗略：用 epoch 差；ISO 解析失败则视为过期
        from datetime import datetime

        last = datetime.fromisoformat(ts)
        age = time.time() - last.timestamp()
        return age < ttl
    except Exception:  # noqa: BLE001
        return False
