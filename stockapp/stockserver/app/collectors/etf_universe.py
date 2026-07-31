"""东财公开 ETF 列表（按成交额），用于扩大择时训练样本。"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx
import yaml

from app.config import CONFIG_DIR, SETTINGS

_HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver/0.3 (personal research)",
    "Referer": "https://quote.eastmoney.com/",
}

# 常见高流动性 ETF 种子（接口失败时兜底）
_SEED_CODES = [
    "510300", "510500", "510050", "159915", "588000", "588080", "512480",
    "512760", "515790", "512660", "512010", "512690", "159819", "512170",
    "159992", "515050", "512800", "512000", "159949", "588200", "513100",
    "513050", "513180", "513520", "513330", "159941", "511010", "511260",
    "515080", "512890", "159905", "510880", "159995", "588290", "588730",
    "159770", "159305", "159748", "159273", "159779", "159329", "159299",
    "159651", "560010", "563000", "159629", "512880", "512400", "159766",
    "159840", "516160", "159755", "512980", "515030", "159869", "512710",
    "159967", "512070", "159928", "510230", "512200", "159611", "588050",
    "516510", "159819", "515220", "512480", "159851", "512660", "513060",
    "513130", "159501", "560080", "159732", "512670", "515880", "159996",
    "588000", "159869", "512480", "159992", "515790", "512690", "159819",
]


async def fetch_etf_board(
    client: httpx.AsyncClient,
    *,
    page: int = 1,
    page_size: int = 100,
    sort_by_amount: bool = True,
) -> tuple[int, list[dict[str, Any]]]:
    params = {
        "pn": str(page),
        "pz": str(page_size),
        "po": "1",
        "np": "1",
        "fltt": "2",
        "invt": "2",
        "fid": "f6" if sort_by_amount else "f3",
        "fs": "b:MK0021,b:MK0022,b:MK0023,b:MK0024",
        "fields": "f12,f14,f2,f3,f6",
        "ut": "fa5fd1943c7b386f172d6893dbfba10b",
    }
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            resp = await client.get(
                "https://push2.eastmoney.com/api/qt/clist/get",
                params=params,
                timeout=30.0,
            )
            resp.raise_for_status()
            data = resp.json().get("data") or {}
            total = int(data.get("total") or 0)
            out: list[dict[str, Any]] = []
            for item in data.get("diff") or []:
                if not isinstance(item, dict):
                    continue
                code = str(item.get("f12") or "").zfill(6)
                if len(code) != 6:
                    continue
                name = str(item.get("f14") or code)
                try:
                    amount = float(item["f6"]) if item.get("f6") is not None else None
                except (TypeError, ValueError):
                    amount = None
                out.append({"code": code, "name": name, "amount": amount})
            return total, out
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.5 * (attempt + 1))
    if last_err:
        raise last_err
    return 0, []


async def build_train_universe(*, top_n: int = 80) -> list[dict[str, Any]]:
    """拉取成交额靠前的 ETF，合并种子与观察池。"""
    from app.config import universe

    gap = float(SETTINGS.get("request_gap_ms", 120)) / 1000.0
    seen: set[str] = set()
    rows: list[dict[str, Any]] = []

    def _add(code: str, name: str, *, source: str) -> None:
        if code in seen:
            return
        seen.add(code)
        rows.append(
            {
                "id": f"train_{code}",
                "name": name,
                "primary": code,
                "bucket": "hot",
                "source": source,
            }
        )

    # 观察池优先纳入
    u = universe()
    for bucket in ("hot", "defensive"):
        for etf in u.get(bucket, []) or []:
            _add(str(etf["primary"]), str(etf.get("name") or etf["primary"]), source="watchlist")

    for code in _SEED_CODES:
        _add(code, code, source="seed")

    async with httpx.AsyncClient(headers=_HEADERS) as client:
        page = 1
        while len([r for r in rows if r["source"] == "board"]) < top_n and page <= 8:
            try:
                total, batch = await fetch_etf_board(client, page=page, page_size=100)
            except Exception:  # noqa: BLE001
                break
            if not batch:
                break
            for item in batch:
                if len(seen) >= top_n + 20:
                    break
                _add(item["code"], item["name"], source="board")
            page += 1
            if page * 100 >= total:
                break
            if gap:
                await asyncio.sleep(gap)

    # 截断到 top_n（watchlist 全保留）
    watch = [r for r in rows if r["source"] == "watchlist"]
    others = [r for r in rows if r["source"] != "watchlist"]
    need = max(0, top_n - len(watch))
    final = watch + others[:need]
    return final


def save_train_universe(items: list[dict[str, Any]]) -> str:
    path = CONFIG_DIR / "etf_train_universe.yaml"
    payload = {
        "version": 1,
        "note": "择时训练池：公开 ETF 列表 + 观察池；仅用于回测定参",
        "count": len(items),
        "items": items,
    }
    path.write_text(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return str(path)


def load_train_universe() -> list[dict[str, Any]]:
    path = CONFIG_DIR / "etf_train_universe.yaml"
    if not path.exists():
        return []
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    items = data.get("items") or []
    return [x for x in items if isinstance(x, dict) and x.get("primary")]
