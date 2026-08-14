#!/usr/bin/env python3
"""手动跑一轮涨停观察榜。"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.db.store import init_db  # noqa: E402
from app.limitup.pipeline import run_limitup_board  # noqa: E402


async def main() -> None:
    init_db()
    result = await run_limitup_board(force=True)
    print(
        "updated",
        result.get("updated_at"),
        "focus",
        result.get("stats", {}).get("focus_n"),
        "watch",
        result.get("stats", {}).get("watch_n"),
        "candidates",
        result.get("stats", {}).get("candidates"),
    )


if __name__ == "__main__":
    asyncio.run(main())
