"""扩大训练池：拉 ETF 列表 → 采集日K/份额（东财优先，新浪净值回退）→ walk-forward 重训。"""
from __future__ import annotations

import asyncio
from typing import Any

from app.collectors import eastmoney_kline, eastmoney_shares, etf_universe, sina_nav
from app.config import reload_configs
from app.db import store
from app.db.store import init_db
from app.services import timing as timing_svc
from app.timing.engine import timing_rules


async def collect_train_data(items: list[dict[str, Any]]) -> dict[str, Any]:
    codes = [str(x["primary"]) for x in items]
    bars_n = 0
    shares_n = 0
    batch = 12
    # 东财日K（可能限流）
    for i in range(0, len(codes), batch):
        chunk = codes[i : i + batch]
        try:
            bars_n += await eastmoney_kline.refresh_bars(chunk, limit=320)
        except Exception as exc:  # noqa: BLE001
            print("eastmoney_kline batch fail", i, exc, flush=True)
        try:
            shares_n += await eastmoney_shares.refresh_shares(chunk, limit=500)
        except Exception as exc:  # noqa: BLE001
            print("eastmoney_shares batch fail", i, exc, flush=True)
        await asyncio.sleep(0.5)

    # 缺 K 的用新浪净值回退
    need = [c for c in codes if len(store.list_bars(c, limit=400)) < 80]
    sina_n = 0
    if need:
        print("sina_nav fallback for", len(need), "codes", flush=True)
        sina_n = await sina_nav.refresh_bars(need, limit=320)

    # 再补一次份额缺口
    need_sh = [c for c in codes if len(store.list_shares(c, limit=10)) < 5]
    if need_sh:
        shares_n += await eastmoney_shares.refresh_shares(need_sh, limit=500)

    return {
        "codes": len(codes),
        "bars": bars_n,
        "shares": shares_n,
        "sina_bars": sina_n,
        "usable": sum(
            1
            for c in codes
            if len(store.list_bars(c, limit=400)) >= 80 and len(store.list_shares(c, limit=10)) >= 5
        ),
    }


async def main() -> None:
    reload_configs()
    init_db()
    cfg = timing_rules()
    top_n = int((cfg.get("backtest") or {}).get("train_top_n", 100))
    print("building train universe top_n=", top_n, flush=True)
    items = await etf_universe.build_train_universe(top_n=top_n)
    path = etf_universe.save_train_universe(items)
    print("saved", path, "count", len(items), flush=True)
    print("collecting bars/shares ...", flush=True)
    coll = await collect_train_data(items)
    print("collect", coll, flush=True)

    usable = [
        x
        for x in items
        if len(store.list_bars(str(x["primary"]), limit=400)) >= 80
        and len(store.list_shares(str(x["primary"]), limit=10)) >= 5
    ]
    etf_universe.save_train_universe(usable)
    print("usable saved", len(usable), flush=True)

    print("walk-forward retrain ...", flush=True)
    bt = timing_svc.ensure_backtest(usable, force=True)
    print("validated", bt.get("validated"), flush=True)
    print("gate", bt.get("gate"), flush=True)
    print("train_universe_size", bt.get("train_universe_size"), flush=True)
    print("selected", bt.get("selected_rules"), flush=True)
    for w, v in (bt.get("by_window") or {}).items():
        m = v.get("metrics") or {}
        tm = v.get("train_metrics") or {}
        print(
            f"W{w} TEST n={m.get('trades')} wr={m.get('win_rate')} avg={m.get('avg_return')} "
            f"TRAIN n={tm.get('trades')} wr={tm.get('win_rate')} avg={tm.get('avg_return')}",
            flush=True,
        )


if __name__ == "__main__":
    asyncio.run(main())
