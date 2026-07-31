"""自选股服务：服务端持久化 + 加入后收益率统计。"""

from __future__ import annotations

from typing import Any

from app.collectors import eastmoney_quote, sina_stock
from app.collectors.eastmoney_quote import market_from_code
from app.db import store


def _asset_type_from_code(code: str) -> str:
    c = str(code).zfill(6)
    if c.startswith(("51", "56", "58", "15")):
        return "etf"
    return "stock"


def _f(v: Any) -> float | None:
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


async def _quotes_for(codes: list[str]) -> dict[str, dict[str, Any]]:
    if not codes:
        return {}
    out: dict[str, dict[str, Any]] = {}
    # 新浪批量快
    try:
        out.update(await sina_stock.fetch_quotes(codes))
    except Exception:  # noqa: BLE001
        pass
    missing = [c for c in codes if c not in out or out[c].get("price") is None]
    if missing:
        import httpx

        async with httpx.AsyncClient(
            headers={
                "User-Agent": "Mozilla/5.0 stockserver/0.3",
                "Referer": "https://quote.eastmoney.com/",
            }
        ) as client:
            for code in missing:
                try:
                    q = await eastmoney_quote.fetch_quote(client, code)
                    if q.get("price") is not None:
                        out[code] = q
                except Exception:  # noqa: BLE001
                    continue
    return out


def _enrich_item(row: dict[str, Any], quote: dict[str, Any] | None) -> dict[str, Any]:
    add_price = _f(row.get("add_price"))
    cur = _f((quote or {}).get("price"))
    chg = _f((quote or {}).get("change_pct"))
    name = str((quote or {}).get("name") or row.get("name") or row["code"])
    ret = None
    if add_price is not None and add_price > 0 and cur is not None:
        ret = cur / add_price - 1.0
    return {
        "id": row["code"],
        "code": row["code"],
        "name": name,
        "market": row.get("market") or market_from_code(row["code"]),
        "asset_type": row.get("asset_type") or _asset_type_from_code(row["code"]),
        "index_name": row.get("index_name") or "",
        "added_at": row.get("added_at"),
        "add_price": add_price,
        "price": cur,
        "change_pct": chg,
        "return_pct": None if ret is None else round(ret, 6),
        "note": row.get("note") or "",
    }


def _stats(items: list[dict[str, Any]]) -> dict[str, Any]:
    rets = [
        float(i["return_pct"])
        for i in items
        if i.get("return_pct") is not None
    ]
    if not rets:
        return {
            "count": len(items),
            "priced_count": 0,
            "avg_return_pct": None,
            "median_return_pct": None,
            "win_count": 0,
            "lose_count": 0,
            "win_rate": None,
            "best": None,
            "worst": None,
        }
    ordered = sorted(rets)
    mid = ordered[len(ordered) // 2]
    if len(ordered) % 2 == 0:
        mid = (ordered[len(ordered) // 2 - 1] + ordered[len(ordered) // 2]) / 2.0
    win = sum(1 for r in rets if r > 0)
    lose = sum(1 for r in rets if r < 0)
    best_item = max(items, key=lambda x: x.get("return_pct") if x.get("return_pct") is not None else -1e9)
    worst_item = min(items, key=lambda x: x.get("return_pct") if x.get("return_pct") is not None else 1e9)
    return {
        "count": len(items),
        "priced_count": len(rets),
        "avg_return_pct": round(sum(rets) / len(rets), 6),
        "median_return_pct": round(mid, 6),
        "win_count": win,
        "lose_count": lose,
        "win_rate": round(win / len(rets), 4) if rets else None,
        "best": {
            "code": best_item["code"],
            "name": best_item["name"],
            "return_pct": best_item.get("return_pct"),
        },
        "worst": {
            "code": worst_item["code"],
            "name": worst_item["name"],
            "return_pct": worst_item.get("return_pct"),
        },
    }


async def list_watchlist(*, with_quotes: bool = True) -> dict[str, Any]:
    rows = store.list_watchlist_rows()
    quotes: dict[str, dict[str, Any]] = {}
    if with_quotes and rows:
        quotes = await _quotes_for([r["code"] for r in rows])
    items = [_enrich_item(r, quotes.get(r["code"])) for r in rows]
    return {
        "ok": True,
        "updated_at": store.utc_now_iso(),
        "items": items,
        "stats": _stats(items),
        "data_policy": "public_only",
    }


async def add_watchlist_item(
    *,
    code: str,
    name: str | None = None,
    market: str | None = None,
    asset_type: str | None = None,
    index_name: str = "",
    note: str = "",
) -> dict[str, Any]:
    code = str(code).zfill(6)
    if len(code) != 6 or not code.isdigit():
        raise ValueError("invalid code")
    existing = store.get_watchlist_row(code)
    quotes = await _quotes_for([code])
    q = quotes.get(code) or {}
    price = _f(q.get("price"))
    resolved_name = name or str(q.get("name") or code)
    resolved_market = market or market_from_code(code)
    resolved_type = asset_type or _asset_type_from_code(code)
    if existing:
        # 已存在：更新名称等，保留原加入价与时间
        store.upsert_watchlist_row(
            {
                **existing,
                "name": resolved_name,
                "market": resolved_market,
                "asset_type": resolved_type,
                "index_name": index_name or existing.get("index_name") or "",
                "note": note or existing.get("note") or "",
            }
        )
        row = store.get_watchlist_row(code) or existing
        item = _enrich_item(row, q)
        return {"ok": True, "created": False, "item": item}
    store.upsert_watchlist_row(
        {
            "code": code,
            "name": resolved_name,
            "market": resolved_market,
            "asset_type": resolved_type,
            "index_name": index_name or "",
            "added_at": store.utc_now_iso(),
            "add_price": price,
            "note": note or "",
        }
    )
    row = store.get_watchlist_row(code)
    assert row is not None
    return {"ok": True, "created": True, "item": _enrich_item(row, q)}


async def add_watchlist_batch(items: list[dict[str, Any]]) -> dict[str, Any]:
    created = 0
    skipped = 0
    out_items: list[dict[str, Any]] = []
    for raw in items:
        code = str(raw.get("code") or "").zfill(6)
        if len(code) != 6:
            continue
        if store.get_watchlist_row(code):
            skipped += 1
            continue
        result = await add_watchlist_item(
            code=code,
            name=raw.get("name"),
            market=raw.get("market"),
            asset_type=raw.get("asset_type"),
            index_name=str(raw.get("index_name") or ""),
            note=str(raw.get("note") or ""),
        )
        if result.get("created"):
            created += 1
        out_items.append(result["item"])
    payload = await list_watchlist(with_quotes=True)
    payload["created"] = created
    payload["skipped"] = skipped
    payload["batch_items"] = out_items
    return payload


def remove_watchlist_item(code: str) -> dict[str, Any]:
    ok = store.delete_watchlist_row(code)
    return {"ok": ok, "code": str(code).zfill(6)}


def remove_watchlist_batch(codes: list[str]) -> dict[str, Any]:
    n = store.delete_watchlist_rows(codes)
    return {"ok": True, "deleted": n}
