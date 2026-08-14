"""涨停观察榜流水线：候选 → 规则过滤 → 观察池/重点池。"""
from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any

import httpx

from app.collectors.limitup_pool import (
    fetch_bars_for_code,
    fetch_money_flow_map,
    fetch_zt_pool_candidates,
)
from app.config import SETTINGS, load_yaml
from app.db import store
from app.limitup.rules import evaluate_limitup_bar, is_limit_up


def board_cfg() -> dict[str, Any]:
    return load_yaml("limitup_board.yaml")


def _empty_payload(cfg: dict[str, Any]) -> dict[str, Any]:
    return {
        "updated_at": None,
        "cfg": {
            "min_market_cap_yi": cfg.get("min_market_cap_yi"),
            "watch_flow_to_mcap": cfg.get("watch_flow_to_mcap"),
            "focus_flow_to_mcap": cfg.get("focus_flow_to_mcap"),
            "min_vol_ma_ratio": cfg.get("min_vol_ma_ratio"),
            "target_ret": cfg.get("target_ret"),
            "floor_ret": cfg.get("floor_ret"),
            "entry_mode": cfg.get("entry_mode"),
            "forward_days": cfg.get("forward_days"),
        },
        "stats": {},
        "focus": [],
        "watch": [],
        "rejected": [],
        "disclosure": cfg.get("disclosure"),
        "data_policy": "public_only",
        "disclaimer": SETTINGS.get("disclaimer"),
        "empty": True,
    }


async def run_limitup_board(*, force: bool = True) -> dict[str, Any]:
    cfg = board_cfg()
    if not force:
        cached = store.load_json_meta("limitup_board")
        if cached:
            cached["disclaimer"] = SETTINGS.get("disclaimer")
            cached["empty"] = not bool(cached.get("focus") or cached.get("watch"))
            return cached

    gap = float(cfg.get("request_gap_ms") or SETTINGS.get("request_gap_ms", 200)) / 1000.0
    min_yi = float(cfg.get("min_market_cap_yi") or 100)
    max_n = int(cfg.get("max_candidates") or 120)

    headers = {
        "User-Agent": "Mozilla/5.0 stockserver/0.3",
        "Referer": "https://quote.eastmoney.com/",
    }
    async with httpx.AsyncClient(headers=headers, timeout=30.0) as client:
        candidates = await fetch_zt_pool_candidates(
            client,
            pagesize=int(cfg.get("zt_pool_pagesize") or 200),
            min_market_cap_yi=min_yi,
        )
        candidates = candidates[:max_n]

        focus: list[dict[str, Any]] = []
        watch: list[dict[str, Any]] = []
        rejected: list[dict[str, Any]] = []
        fail_reasons: dict[str, int] = {}

        for i, cand in enumerate(candidates):
            code = str(cand["code"]).zfill(6)
            name = str(cand.get("name") or code)
            mcap = float(cand.get("market_cap_yi") or 0)
            try:
                bars = await fetch_bars_for_code(client, code, limit=40)
                await asyncio.sleep(gap)
                flows = await fetch_money_flow_map(client, code, limit=30)
                await asyncio.sleep(gap)

                # 优先用最近一根涨停K；兼容盘中/数据滞后
                sig_idx: int | None = None
                for j in range(len(bars) - 1, max(len(bars) - 6, -1), -1):
                    chg = float(bars[j].get("change_pct") or 0)
                    if is_limit_up(chg, code):
                        sig_idx = j
                        break
                if sig_idx is None:
                    rejected.append(
                        {
                            "code": code,
                            "name": name,
                            "market_cap_yi": mcap,
                            "reason": "近端K线无涨停",
                            "signal_chg": cand.get("change_pct"),
                        }
                    )
                    fail_reasons["近端K线无涨停"] = (
                        fail_reasons.get("近端K线无涨停", 0) + 1
                    )
                    continue

                ev = evaluate_limitup_bar(
                    code=code,
                    name=name,
                    market_cap_yi=mcap,
                    bars=bars,
                    flows=flows,
                    cfg=cfg,
                    signal_index=sig_idx,
                )
                row = {
                    **ev.to_dict(),
                    "price": cand.get("price"),
                    "source": cand.get("source"),
                }
                if ev.ok and ev.pool == "focus":
                    focus.append(row)
                elif ev.ok and ev.pool == "watch":
                    watch.append(row)
                else:
                    rejected.append(
                        {
                            "code": code,
                            "name": name,
                            "market_cap_yi": mcap,
                            "reason": ev.reason,
                            "signal_chg": ev.signal_chg,
                            "flow_to_mcap": ev.flow_to_mcap,
                            "vol_ma_ratio": ev.vol_ma_ratio,
                        }
                    )
                    fail_reasons[ev.reason] = fail_reasons.get(ev.reason, 0) + 1
            except Exception as exc:  # noqa: BLE001
                rejected.append(
                    {
                        "code": code,
                        "name": name,
                        "market_cap_yi": mcap,
                        "reason": f"fetch_error:{exc}",
                    }
                )
                fail_reasons["fetch_error"] = fail_reasons.get("fetch_error", 0) + 1
            if (i + 1) % 20 == 0:
                await asyncio.sleep(0.3)

    focus.sort(key=lambda r: float(r.get("score") or 0), reverse=True)
    watch.sort(key=lambda r: float(r.get("score") or 0), reverse=True)

    payload = {
        "updated_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "cfg": {
            "min_market_cap_yi": cfg.get("min_market_cap_yi"),
            "watch_flow_to_mcap": cfg.get("watch_flow_to_mcap"),
            "focus_flow_to_mcap": cfg.get("focus_flow_to_mcap"),
            "min_vol_ma_ratio": cfg.get("min_vol_ma_ratio"),
            "target_ret": cfg.get("target_ret"),
            "floor_ret": cfg.get("floor_ret"),
            "entry_mode": cfg.get("entry_mode"),
            "forward_days": cfg.get("forward_days"),
        },
        "stats": {
            "candidates": len(candidates),
            "focus_n": len(focus),
            "watch_n": len(watch),
            "rejected_n": len(rejected),
            "fail_reasons": fail_reasons,
        },
        "focus": focus,
        "watch": watch,
        "rejected": rejected[:80],
        "disclosure": cfg.get("disclosure"),
        "data_policy": "public_only",
        "disclaimer": SETTINGS.get("disclaimer"),
        "empty": not (focus or watch),
    }
    store.save_json_meta("limitup_board", payload)
    store.set_meta("last_limitup_board_at", payload["updated_at"])
    return payload
