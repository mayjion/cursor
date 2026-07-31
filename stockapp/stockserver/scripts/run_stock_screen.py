"""一键跑 A 股初选推荐池。"""
from __future__ import annotations

import asyncio
import json

from app.config import reload_configs
from app.db.store import init_db
from app.stock_screen.pipeline import run_stock_screen


async def main() -> None:
    reload_configs()
    init_db()
    print("running stock screen ...", flush=True)
    result = await run_stock_screen(force_bars=True)
    print("updated_at", result.get("updated_at"), flush=True)
    print("stats", json.dumps(result.get("stats") or {}, ensure_ascii=False), flush=True)
    pool = result.get("pool") or []
    print("pool_n", len(pool), flush=True)
    for row in pool[:15]:
        print(
            f"  {row['code']} {row['name']} score={row.get('score')} "
            f"val={row.get('valuation_score')} pe={row.get('pe_ttm')} "
            f"upside={row.get('upside')} src={row.get('target_source')} "
            f"own={row.get('ownership_sources')} reports={row.get('report_count')}",
            flush=True,
        )
    if pool:
        code = pool[0]["code"]
        detail = (result.get("details") or {}).get(code) or {}
        print("sample_checks", detail.get("checks"), flush=True)


if __name__ == "__main__":
    asyncio.run(main())
