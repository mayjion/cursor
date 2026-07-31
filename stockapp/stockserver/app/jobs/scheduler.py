from __future__ import annotations

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.services import dashboard as dash
from app.services import stock_screen as stock_svc

logger = logging.getLogger("stockserver.jobs")
_scheduler: AsyncIOScheduler | None = None


async def _daily_collect() -> None:
    try:
        result = await dash.collect_and_score(force_quote=True)
        logger.info("daily collect done: %s", result)
    except Exception:  # noqa: BLE001
        logger.exception("daily collect failed")


async def _daily_stock_screen() -> None:
    try:
        result = await stock_svc.ensure_pool(force=True)
        logger.info(
            "stock screen done: pool=%s stats=%s",
            len(result.get("pool") or []),
            result.get("stats"),
        )
    except Exception:  # noqa: BLE001
        logger.exception("stock screen failed")


def start_scheduler() -> AsyncIOScheduler:
    global _scheduler
    if _scheduler is not None:
        return _scheduler
    sched = AsyncIOScheduler(timezone="Asia/Shanghai")
    # 每个交易日收盘后附近跑一次（含周末空跑可接受）
    sched.add_job(_daily_collect, "cron", hour=16, minute=10, id="daily_collect")
    # 盘中轻量：仅刷新行情+重算（有缓存日K时）
    sched.add_job(_daily_collect, "cron", hour=11, minute=35, id="midday_collect")
    # A股初选推荐池（收盘后）
    sched.add_job(_daily_stock_screen, "cron", hour=16, minute=30, id="daily_stock_screen")
    sched.start()
    _scheduler = sched
    logger.info("scheduler started")
    return sched


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
