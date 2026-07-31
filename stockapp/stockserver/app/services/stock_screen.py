"""A股推荐池服务：缓存读取 + 强制重跑。"""
from __future__ import annotations

from typing import Any

from app.config import SETTINGS, load_yaml
from app.db import store
from app.stock_screen.pipeline import run_stock_screen


def _empty_pool() -> dict[str, Any]:
    cfg = load_yaml("stock_screen.yaml")
    return {
        "updated_at": None,
        "cfg": {
            "insider_days": cfg.get("insider_days"),
            "min_upside": cfg.get("min_upside"),
            "max_price_percentile": cfg.get("max_price_percentile"),
            "pool_size": cfg.get("pool_size"),
        },
        "stats": {},
        "pool": [],
        "details": {},
        "disclosure": cfg.get("disclosure"),
        "data_policy": "public_only",
        "disclaimer": SETTINGS.get("disclaimer"),
        "empty": True,
    }


async def ensure_pool(*, force: bool = False) -> dict[str, Any]:
    cached = store.load_json_meta("stock_screen_pool")
    if cached and not force:
        cached["disclaimer"] = SETTINGS.get("disclaimer")
        cached["empty"] = not bool(cached.get("pool"))
        return cached
    result = await run_stock_screen(force_bars=True)
    result["disclaimer"] = SETTINGS.get("disclaimer")
    result["empty"] = not bool(result.get("pool"))
    return result


def get_cached_pool() -> dict[str, Any]:
    cached = store.load_json_meta("stock_screen_pool")
    if not cached:
        return _empty_pool()
    cached["disclaimer"] = SETTINGS.get("disclaimer")
    cached["empty"] = not bool(cached.get("pool"))
    return cached


def get_stock_detail(code: str) -> dict[str, Any] | None:
    code = str(code).zfill(6)
    cached = store.load_json_meta("stock_screen_pool") or {}
    details = cached.get("details") or {}
    row = details.get(code)
    if not row:
        return None
    return {
        **row,
        "updated_at": cached.get("updated_at"),
        "disclosure": cached.get("disclosure"),
        "disclaimer": SETTINGS.get("disclaimer"),
        "cfg": cached.get("cfg"),
    }
