"""涨停观察榜服务：缓存读取 + 强制重跑。"""
from __future__ import annotations

from typing import Any

from app.config import SETTINGS, load_yaml
from app.db import store
from app.limitup.pipeline import run_limitup_board


def _empty() -> dict[str, Any]:
    cfg = load_yaml("limitup_board.yaml")
    return {
        "updated_at": None,
        "cfg": {
            "min_market_cap_yi": cfg.get("min_market_cap_yi"),
            "watch_flow_to_mcap": cfg.get("watch_flow_to_mcap"),
            "focus_flow_to_mcap": cfg.get("focus_flow_to_mcap"),
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


async def ensure_board(*, force: bool = False) -> dict[str, Any]:
    cached = store.load_json_meta("limitup_board")
    if cached and not force:
        cached["disclaimer"] = SETTINGS.get("disclaimer")
        cached["empty"] = not bool(cached.get("focus") or cached.get("watch"))
        return cached
    result = await run_limitup_board(force=True)
    result["disclaimer"] = SETTINGS.get("disclaimer")
    result["empty"] = not bool(result.get("focus") or result.get("watch"))
    return result


def get_cached_board() -> dict[str, Any]:
    cached = store.load_json_meta("limitup_board")
    if not cached:
        return _empty()
    cached["disclaimer"] = SETTINGS.get("disclaimer")
    cached["empty"] = not bool(cached.get("focus") or cached.get("watch"))
    return cached
