#!/usr/bin/env python3
"""涨停观察规则：历史抽样胜率验证（T+1 最低价入场）。

信号日=涨停日；次日最低价买入；未来10个交易日（含买入日）
最高价相对入场价涨幅 ≥ success_ret 视为成功。默认目标 ≥8%，要求胜率≥80%。

用法:
  cd stockserver && .venv/bin/python scripts/validate_limitup_rules.py --rounds 5 --n 20 --limit-up-only
  cd stockserver && .venv/bin/python scripts/validate_limitup_rules.py --probe
  cd stockserver && .venv/bin/python scripts/validate_limitup_rules.py --summary
"""

from __future__ import annotations

import argparse
import asyncio
import json
import random
import statistics
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data" / "rule_validation"
OUT_DIR.mkdir(parents=True, exist_ok=True)
RESULTS_FILE = OUT_DIR / "runs_t1low.jsonl"
SUMMARY_FILE = OUT_DIR / "summary_t1low.md"
JUDGMENT_FILE = OUT_DIR / "judgment_t1low.md"
UNIVERSE_CACHE = OUT_DIR / "universe_cache.json"
UNIVERSE_CACHE_TTL_SEC = 6 * 3600
BAR_CACHE_DIR = OUT_DIR / "cache_bars"
FLOW_CACHE_DIR = OUT_DIR / "cache_flows"
BAR_CACHE_DIR.mkdir(parents=True, exist_ok=True)
FLOW_CACHE_DIR.mkdir(parents=True, exist_ok=True)

HEADERS = {
    "User-Agent": "Mozilla/5.0 stockserver-rule-validate/0.1",
    "Referer": "https://quote.eastmoney.com/",
}

CLIST_URLS = [
    "https://push2delay.eastmoney.com/api/qt/clist/get",
    "https://push2.eastmoney.com/api/qt/clist/get",
    "https://82.push2.eastmoney.com/api/qt/clist/get",
]

DEFAULT_RULES = {
    "min_market_cap_yi": 100.0,
    "max_market_cap_yi": 0.0,  # 0=不设上限
    "lookback_bars": 260,
    "flow_window": 10,
    "forward_days": 10,
    "success_ret": 0.08,
    "entry_mode": "t1_low",  # 涨停次日最低价
    "require_flow_sum_positive": True,
    "require_flow_accelerate": True,
    "min_flow_to_mcap": 0.005,
    "min_vol_ma_ratio": 1.20,
    "max_vol_ma_ratio": 1.80,
    "min_up_days_in_5": 3,
    "reject_pulse_fake": True,
    "pulse_spike": 3.0,
    "min_signal_day_chg": 9.7,
    "prefer_limit_up": True,
}


@dataclass
class SignalHit:
    code: str
    name: str
    signal_date: str
    buy_date: str
    market_cap_yi: float
    flow_sum_10: float
    flow_near5: float
    flow_prev5: float
    flow_to_mcap: float
    vol_ma_ratio: float
    up_days: int
    signal_chg: float
    entry_low: float
    fwd_max_high_ret: float
    fwd_max_close_ret: float
    fwd_d10_close_ret: float
    success: bool
    is_limit_up: bool


def _f(v: Any) -> float | None:
    if v is None or v == "" or v == "-":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _secid(code: str) -> str:
    return f"1.{code}" if code.startswith(("5", "6", "9")) else f"0.{code}"


def _load_universe_cache(min_yi: float) -> list[dict[str, Any]] | None:
    if not UNIVERSE_CACHE.exists():
        return None
    try:
        raw = json.loads(UNIVERSE_CACHE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if abs(float(raw.get("min_yi") or 0) - min_yi) > 1e-6:
        return None
    ts = float(raw.get("ts") or 0)
    if time.time() - ts > UNIVERSE_CACHE_TTL_SEC:
        return None
    rows = raw.get("rows")
    return rows if isinstance(rows, list) and rows else None


def _save_universe_cache(min_yi: float, rows: list[dict[str, Any]]) -> None:
    payload = {"ts": time.time(), "min_yi": min_yi, "rows": rows}
    UNIVERSE_CACHE.write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8"
    )


async def fetch_large_cap_universe(
    client: httpx.AsyncClient,
    *,
    min_yi: float = 100.0,
    pages: int = 8,
    use_cache: bool = True,
) -> list[dict[str, Any]]:
    if use_cache:
        cached = _load_universe_cache(min_yi)
        if cached:
            print(f"  universe cache hit: {len(cached)} stocks")
            return cached

    out: list[dict[str, Any]] = []
    for page in range(1, pages + 1):
        params = {
            "pn": str(page),
            "pz": "100",
            "po": "1",
            "np": "1",
            "fltt": "2",
            "invt": "2",
            "fid": "f20",
            "fs": "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048",
            "fields": "f12,f14,f2,f3,f5,f6,f20,f21",
            "ut": "b2884a393a59ad64002292a3e90d46a5",
        }
        page_ok = False
        diff: list[Any] = []
        for attempt in range(4):
            url = CLIST_URLS[attempt % len(CLIST_URLS)]
            try:
                resp = await client.get(
                    url,
                    params=params,
                    timeout=25.0,
                )
                resp.raise_for_status()
                diff = ((resp.json().get("data") or {}).get("diff")) or []
                page_ok = True
                if not diff:
                    break
                for row in diff:
                    if not isinstance(row, dict):
                        continue
                    code = str(row.get("f12") or "").zfill(6)
                    name = str(row.get("f14") or "")
                    if not code.isdigit() or len(code) != 6:
                        continue
                    if "ST" in name.upper():
                        continue
                    if code.startswith(("4", "8")):
                        continue
                    mcap = _f(row.get("f20"))
                    if mcap is None or mcap <= min_yi * 1e8:
                        continue
                    out.append(
                        {
                            "code": code,
                            "name": name,
                            "market_cap_yi": round(mcap / 1e8, 2),
                            "price": _f(row.get("f2")),
                            "change_pct": _f(row.get("f3")),
                        }
                    )
                break
            except Exception as exc:  # noqa: BLE001
                await asyncio.sleep(0.6 * (attempt + 1))
                if attempt == 3:
                    print(f"  universe page {page} failed: {exc}")
        if not page_ok:
            continue
        if not diff:
            break
        await asyncio.sleep(0.2)
    seen: set[str] = set()
    uniq: list[dict[str, Any]] = []
    for r in out:
        if r["code"] in seen:
            continue
        seen.add(r["code"])
        uniq.append(r)
    if uniq:
        _save_universe_cache(min_yi, uniq)
    return uniq



def _cache_load(path: Path) -> Any | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _cache_save(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False), encoding="utf-8")


def _sina_symbol(code: str) -> str:
    return f"sh{code}" if code.startswith(("5", "6", "9")) else f"sz{code}"


async def fetch_klines(
    client: httpx.AsyncClient, code: str, *, limit: int = 260
) -> list[dict[str, Any]]:
    """优先新浪日K，其次百度；东财 his 作为末选。"""
    cpath = BAR_CACHE_DIR / f"{code}.json"
    cached = _cache_load(cpath)
    if isinstance(cached, list) and len(cached) >= min(120, limit // 2):
        return cached[-limit:]

    last_err: Exception | None = None

    # 1) Sina
    for attempt in range(3):
        try:
            resp = await client.get(
                "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData",
                params={
                    "symbol": _sina_symbol(code),
                    "scale": "240",
                    "ma": "no",
                    "datalen": str(max(limit, 300)),
                },
                timeout=25.0,
                headers={**HEADERS, "Referer": "https://finance.sina.com.cn/"},
            )
            resp.raise_for_status()
            rows = resp.json()
            if not isinstance(rows, list) or not rows:
                raise RuntimeError("sina empty kline")
            out: list[dict[str, Any]] = []
            prev_close: float | None = None
            for row in rows:
                if not isinstance(row, dict):
                    continue
                close = _f(row.get("close"))
                if close is None:
                    continue
                chg = 0.0
                if prev_close and prev_close > 0:
                    chg = (close / prev_close - 1.0) * 100.0
                out.append(
                    {
                        "date": str(row.get("day") or ""),
                        "open": _f(row.get("open")),
                        "high": _f(row.get("high")),
                        "low": _f(row.get("low")),
                        "close": close,
                        "volume": _f(row.get("volume")) or 0.0,
                        "amount": None,
                        "change_pct": chg,
                    }
                )
                prev_close = close
            if out:
                _cache_save(cpath, out)
                return out[-limit:]
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.5 * (attempt + 1))

    # 2) Baidu
    for attempt in range(2):
        try:
            resp = await client.get(
                "https://finance.pae.baidu.com/vapi/v1/getquotation",
                params={
                    "srcid": "5353",
                    "code": code,
                    "market": "ab",
                    "newFormat": "1",
                    "group": "quotation_kline_ab",
                    "query": code,
                    "is_kc": "0",
                    "ktype": "day",
                    "count": str(max(limit, 320)),
                },
                timeout=30.0,
                headers={**HEADERS, "Referer": "https://gushitong.baidu.com/"},
            )
            resp.raise_for_status()
            md = ((resp.json().get("Result") or {}).get("newMarketData")) or {}
            raw = md.get("marketData") or ""
            if not isinstance(raw, str) or not raw:
                raise RuntimeError("baidu empty kline")
            out = []
            for line in raw.split(";"):
                p = line.split(",")
                if len(p) < 10:
                    continue
                out.append(
                    {
                        "date": p[1],
                        "open": _f(p[2]),
                        "close": _f(p[3]),
                        "volume": _f(p[4]) or 0.0,
                        "high": _f(p[5]),
                        "low": _f(p[6]),
                        "amount": _f(p[7]),
                        "change_pct": _f(p[9]) or 0.0,
                    }
                )
            if out:
                _cache_save(cpath, out)
                return out[-limit:]
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            await asyncio.sleep(0.8 * (attempt + 1))

    if last_err:
        raise last_err
    return []


async def fetch_flows(
    client: httpx.AsyncClient, code: str, *, limit: int = 160
) -> dict[str, float]:
    """优先新浪主力净流入(r0_net)；东财 fflow 作为回退。"""
    cpath = FLOW_CACHE_DIR / f"{code}.json"
    cached = _cache_load(cpath)
    if isinstance(cached, dict) and len(cached) >= max(40, limit // 3):
        return {str(k): float(v) for k, v in cached.items()}

    out: dict[str, float] = {}
    daima = _sina_symbol(code)
    page_size = 60
    pages = max(1, (limit + page_size - 1) // page_size)
    for page in range(1, pages + 1):
        ok = False
        for attempt in range(3):
            try:
                resp = await client.get(
                    "https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/MoneyFlow.ssl_qsfx_zjlrqs",
                    params={
                        "page": str(page),
                        "num": str(page_size),
                        "sort": "opendate",
                        "asc": "0",
                        "daima": daima,
                    },
                    timeout=25.0,
                    headers={
                        **HEADERS,
                        "Referer": "https://vip.stock.finance.sina.com.cn/",
                    },
                )
                resp.raise_for_status()
                rows = resp.json()
                if not isinstance(rows, list) or not rows:
                    ok = True
                    break
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    d = str(row.get("opendate") or "")
                    v = _f(row.get("r0_net"))
                    if v is None:
                        v = _f(row.get("netamount"))
                    if d and v is not None:
                        out[d] = v
                ok = True
                break
            except Exception:  # noqa: BLE001
                await asyncio.sleep(0.4 * (attempt + 1))
        if not ok:
            break
        await asyncio.sleep(0.08)
        if len(out) >= limit:
            break

    if len(out) >= max(20, limit // 3):
        _cache_save(cpath, out)
        return out

    for host in (
        "https://push2his.eastmoney.com",
        "https://push2delay.eastmoney.com",
    ):
        try:
            resp = await client.get(
                f"{host}/api/qt/stock/fflow/daykline/get",
                params={
                    "lmt": str(limit),
                    "klt": "101",
                    "secid": _secid(code),
                    "fields1": "f1,f2,f3,f7",
                    "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63,f64,f65",
                    "ut": "b2884a393a59ad64002292a3e90d46a5",
                },
                timeout=30.0,
            )
            resp.raise_for_status()
            klines = (resp.json().get("data") or {}).get("klines") or []
            for line in klines:
                if not isinstance(line, str):
                    continue
                p = line.split(",")
                if len(p) < 2:
                    continue
                v = _f(p[1])
                if v is not None:
                    out[p[0]] = v
            if out:
                _cache_save(cpath, out)
                return out
        except Exception:  # noqa: BLE001
            continue
    if out:
        _cache_save(cpath, out)
    return out


def _is_limit_up(chg: float, code: str) -> bool:
    if code.startswith(("300", "301", "688", "689")):
        return chg >= 19.5
    return chg >= 9.7


def scan_signals(
    *,
    code: str,
    name: str,
    market_cap_yi: float,
    bars: list[dict[str, Any]],
    flows: dict[str, float],
    rules: dict[str, Any],
) -> list[SignalHit]:
    w = int(rules["flow_window"])
    fwd = int(rules["forward_days"])
    # 需要：信号日 + 次日买入 + 共 fwd 根K（含买入日）
    if len(bars) < w + fwd + 2:
        return []

    max_mcap = float(rules.get("max_market_cap_yi") or 0)
    if max_mcap > 0 and market_cap_yi > max_mcap:
        return []
    if market_cap_yi < float(rules.get("min_market_cap_yi") or 0):
        return []

    hits: list[SignalHit] = []
    # i = 涨停日；i+1 = 买入日；窗口 [i+1, i+fwd]
    for i in range(w, len(bars) - fwd):
        sig = bars[i]
        chg = float(sig.get("change_pct") or 0)
        if rules.get("prefer_limit_up"):
            if not _is_limit_up(chg, code):
                continue
        elif chg < float(rules["min_signal_day_chg"]):
            continue

        pre = bars[i - w : i]
        if len(pre) < w:
            continue
        vols = [float(b["volume"] or 0) for b in pre]
        if any(v <= 0 for v in vols):
            continue
        prev5 = vols[:5]
        near5 = vols[5:]
        ma_prev = sum(prev5) / 5
        ma_near = sum(near5) / 5
        if ma_prev <= 0:
            continue
        vol_ratio = ma_near / ma_prev
        if vol_ratio < float(rules["min_vol_ma_ratio"]):
            continue
        max_vol = float(rules.get("max_vol_ma_ratio") or 0)
        if max_vol > 0 and vol_ratio > max_vol:
            continue

        chain = prev5[-1:] + near5
        up_days = sum(1 for j in range(1, len(chain)) if chain[j] > chain[j - 1])
        if up_days < int(rules["min_up_days_in_5"]):
            continue

        if rules.get("reject_pulse_fake"):
            spike = float(rules["pulse_spike"])
            pulsed = False
            for j, v in enumerate(vols):
                if v > spike * ma_prev:
                    after = vols[j + 1 : j + 3]
                    if after and (sum(after) / len(after)) < 1.1 * ma_prev:
                        pulsed = True
                        break
            if pulsed:
                continue

        flow_vals: list[float] = []
        ok_flow = True
        for b in pre:
            d = b["date"]
            if d not in flows:
                ok_flow = False
                break
            flow_vals.append(flows[d])
        if not ok_flow or len(flow_vals) < w:
            continue
        flow_sum = sum(flow_vals)
        flow_prev5 = sum(flow_vals[:5])
        flow_near5 = sum(flow_vals[5:])
        if rules.get("require_flow_sum_positive") and flow_sum <= 0:
            continue
        if rules.get("require_flow_accelerate") and flow_near5 < flow_prev5:
            continue
        mcap_yuan = market_cap_yi * 1e8
        flow_to_mcap = (flow_sum / mcap_yuan) if mcap_yuan > 0 else 0.0
        min_ratio = float(rules.get("min_flow_to_mcap") or 0)
        if min_ratio > 0 and flow_to_mcap < min_ratio:
            continue

        buy = bars[i + 1]
        entry = float(buy.get("low") or 0)
        if entry <= 0:
            continue
        # 含买入日共 fwd 个交易日
        window = bars[i + 1 : i + 1 + fwd]
        if len(window) < fwd:
            continue
        max_high = max(float(b.get("high") or 0) for b in window)
        max_close = max(float(b.get("close") or 0) for b in window)
        d10_close = float(window[-1].get("close") or 0)
        if max_high <= 0:
            continue
        max_high_ret = max_high / entry - 1.0
        max_close_ret = max_close / entry - 1.0
        d10_ret = d10_close / entry - 1.0
        success = max_high_ret >= float(rules["success_ret"])

        hits.append(
            SignalHit(
                code=code,
                name=name,
                signal_date=str(sig["date"]),
                buy_date=str(buy["date"]),
                market_cap_yi=market_cap_yi,
                flow_sum_10=round(flow_sum, 2),
                flow_near5=round(flow_near5, 2),
                flow_prev5=round(flow_prev5, 2),
                flow_to_mcap=round(flow_to_mcap, 6),
                vol_ma_ratio=round(vol_ratio, 3),
                up_days=up_days,
                signal_chg=round(chg, 2),
                entry_low=round(entry, 4),
                fwd_max_high_ret=round(max_high_ret, 4),
                fwd_max_close_ret=round(max_close_ret, 4),
                fwd_d10_close_ret=round(d10_ret, 4),
                success=success,
                is_limit_up=_is_limit_up(chg, code),
            )
        )
    return hits


async def run_one_round(
    *,
    n: int,
    seed: int | None,
    rules: dict[str, Any],
) -> dict[str, Any]:
    rng = random.Random(seed)
    async with httpx.AsyncClient(headers=HEADERS) as client:
        universe = await fetch_large_cap_universe(
            client, min_yi=float(rules["min_market_cap_yi"])
        )
        if len(universe) < n:
            raise RuntimeError(f"市值池不足：仅 {len(universe)} 只")
        sample = rng.sample(universe, n)

        all_hits: list[SignalHit] = []
        per_stock: list[dict[str, Any]] = []
        for i, s in enumerate(sample):
            code = s["code"]
            try:
                bars = await fetch_klines(
                    client, code, limit=int(rules["lookback_bars"])
                )
                await asyncio.sleep(0.55)
                flows = await fetch_flows(client, code, limit=160)
                await asyncio.sleep(0.55)
                hits = scan_signals(
                    code=code,
                    name=s["name"],
                    market_cap_yi=float(s["market_cap_yi"]),
                    bars=bars,
                    flows=flows,
                    rules=rules,
                )
                hits = sorted(hits, key=lambda h: h.signal_date, reverse=True)[:5]
                all_hits.extend(hits)
                per_stock.append(
                    {
                        "code": code,
                        "name": s["name"],
                        "market_cap_yi": s["market_cap_yi"],
                        "signals": len(hits),
                        "successes": sum(1 for h in hits if h.success),
                    }
                )
                print(
                    f"  [{i + 1}/{n}] {code} {s['name']} "
                    f"signals={len(hits)} ok={sum(1 for h in hits if h.success)}"
                )
            except Exception as exc:  # noqa: BLE001
                print(f"  [{i + 1}/{n}] {code} FAIL {exc}")
                per_stock.append(
                    {
                        "code": code,
                        "name": s["name"],
                        "market_cap_yi": s["market_cap_yi"],
                        "signals": 0,
                        "successes": 0,
                        "error": str(exc),
                    }
                )

    total = len(all_hits)
    wins = sum(1 for h in all_hits if h.success)
    limit_hits = [h for h in all_hits if h.is_limit_up]
    limit_wins = sum(1 for h in limit_hits if h.success)

    def _wr(a: int, b: int) -> float | None:
        return None if b == 0 else round(a / b, 4)

    return {
        "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "seed": seed,
        "n_stocks": n,
        "rules": rules,
        "signal_count": total,
        "success_count": wins,
        "win_rate": _wr(wins, total),
        "limit_up_signal_count": len(limit_hits),
        "limit_up_success_count": limit_wins,
        "limit_up_win_rate": _wr(limit_wins, len(limit_hits)),
        "avg_fwd_max_high_ret": (
            None
            if not all_hits
            else round(statistics.mean(h.fwd_max_high_ret for h in all_hits), 4)
        ),
        "median_fwd_max_high_ret": (
            None
            if not all_hits
            else round(statistics.median(h.fwd_max_high_ret for h in all_hits), 4)
        ),
        "stocks": per_stock,
        "hits": [asdict(h) for h in all_hits],
    }


def append_run(payload: dict[str, Any]) -> None:
    with RESULTS_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def load_runs() -> list[dict[str, Any]]:
    if not RESULTS_FILE.exists():
        return []
    rows: list[dict[str, Any]] = []
    for line in RESULTS_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def write_summary(runs: list[dict[str, Any]]) -> str:
    if not runs:
        text = "# 规则验证汇总（T+1最低价）\n\n暂无运行记录。\n"
        SUMMARY_FILE.write_text(text, encoding="utf-8")
        return text

    # 仅统计 entry_mode=t1_low
    runs = [
        r
        for r in runs
        if (r.get("rules") or {}).get("entry_mode", "t1_low") == "t1_low"
    ]

    total_sig = sum(int(r.get("signal_count") or 0) for r in runs)
    total_win = sum(int(r.get("success_count") or 0) for r in runs)
    wrs = [r["win_rate"] for r in runs if r.get("win_rate") is not None]

    all_hits: list[dict[str, Any]] = []
    for r in runs:
        all_hits.extend(r.get("hits") or [])

    # 去重
    seen: set[tuple[str, str]] = set()
    uniq: list[dict[str, Any]] = []
    for h in all_hits:
        k = (str(h.get("code")), str(h.get("signal_date")))
        if k in seen:
            continue
        seen.add(k)
        uniq.append(h)
    all_hits = uniq

    def bucket_wr(pred, thr: float | None = None) -> tuple[int, int, float | None]:
        sub = [h for h in all_hits if pred(h)]
        if not sub:
            return 0, 0, None
        if thr is None:
            w = sum(1 for h in sub if h.get("success"))
        else:
            w = sum(1 for h in sub if (h.get("fwd_max_high_ret") or 0) >= thr)
        return w, len(sub), round(w / len(sub), 4)

    buckets = {
        "全部信号(规则内success)": bucket_wr(lambda h: True),
        "主力/市值≥0.5%": bucket_wr(lambda h: (h.get("flow_to_mcap") or 0) >= 0.005),
        "主力/市值≥0.8%": bucket_wr(lambda h: (h.get("flow_to_mcap") or 0) >= 0.008),
        "放量1.2~1.6": bucket_wr(
            lambda h: 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.6
        ),
        "放量1.2~1.8": bucket_wr(
            lambda h: 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8
        ),
        "市值100~800": bucket_wr(lambda h: 100 <= (h.get("market_cap_yi") or 0) <= 800),
        "市值>800": bucket_wr(lambda h: (h.get("market_cap_yi") or 0) > 800),
        "近5资金≥前5": bucket_wr(
            lambda h: (h.get("flow_near5") or 0) >= (h.get("flow_prev5") or 0)
        ),
    }

    lines = [
        "# 涨停观察规则 · T+1最低价入场验证汇总",
        "",
        "- 口径：涨停次日最低价买入；含买入日共10个交易日最高价涨幅达标即成功",
        f"- 累计轮次：{len(runs)}",
        f"- 去重信号：{len(all_hits)}，规则内成功：{sum(1 for h in all_hits if h.get('success'))}，"
        f"胜率：{(round(sum(1 for h in all_hits if h.get('success'))/len(all_hits),4) if all_hits else None)}",
        f"- 各轮胜率：{wrs}",
        "",
        "## 分桶（按各轮规则内 success 标记）",
        "",
        "| 分桶 | 成功 | 样本 | 胜率 |",
        "|---|---:|---:|---:|",
    ]
    for name, (w, n, wr) in buckets.items():
        lines.append(f"| {name} | {w} | {n} | {wr if wr is not None else '—'} |")

    lines += ["", "## 不同目标涨幅（全样本重算）", "", "| 目标 | 成功 | 样本 | 胜率 |", "|---|---:|---:|---:|"]
    for thr in (0.08, 0.10, 0.12, 0.15):
        w, n, wr = bucket_wr(lambda h: True, thr)
        lines.append(f"| ≥{thr:.0%} | {w} | {n} | {wr if wr is not None else '—'} |")

    lines.append("")
    text_out = "\n".join(lines) + "\n"
    SUMMARY_FILE.write_text(text_out, encoding="utf-8")
    return text_out


def probe_filters(runs: list[dict[str, Any]], *, min_n: int = 12) -> str:
    """在已有命中上网格搜索：胜率≥80%，尽量提高目标涨幅。"""
    hits: list[dict[str, Any]] = []
    for r in runs:
        if (r.get("rules") or {}).get("entry_mode", "t1_low") != "t1_low":
            continue
        hits.extend(r.get("hits") or [])
    seen: set[tuple[str, str]] = set()
    uniq: list[dict[str, Any]] = []
    for h in hits:
        k = (str(h.get("code")), str(h.get("signal_date")))
        if k in seen:
            continue
        seen.add(k)
        uniq.append(h)
    hits = uniq

    def ok(sub, thr):
        if len(sub) < min_n:
            return None
        w = sum(1 for h in sub if (h.get("fwd_max_high_ret") or 0) >= thr)
        return w, len(sub), w / len(sub)

    filters = {
        "涨停基础(已入池)": lambda h: True,
        "flow/mcap≥0.5%": lambda h: (h.get("flow_to_mcap") or 0) >= 0.005,
        "flow/mcap≥0.8%": lambda h: (h.get("flow_to_mcap") or 0) >= 0.008,
        "flow/mcap≥1.0%": lambda h: (h.get("flow_to_mcap") or 0) >= 0.010,
        "vol∈[1.2,1.6]": lambda h: 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.6,
        "vol∈[1.2,1.8]": lambda h: 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8,
        "vol∈[1.2,1.5]": lambda h: 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.5,
        "near≥prev": lambda h: (h.get("flow_near5") or 0) >= (h.get("flow_prev5") or 0),
        "flow>1亿": lambda h: (h.get("flow_sum_10") or 0) > 1e8,
        "flow>3亿": lambda h: (h.get("flow_sum_10") or 0) > 3e8,
        "flow/mcap≥0.5% & vol∈[1.2,1.8]": lambda h: (h.get("flow_to_mcap") or 0) >= 0.005
        and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8,
        "flow/mcap≥0.5% & vol∈[1.2,1.6]": lambda h: (h.get("flow_to_mcap") or 0) >= 0.005
        and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.6,
        "flow/mcap≥0.8% & vol∈[1.2,1.8]": lambda h: (h.get("flow_to_mcap") or 0) >= 0.008
        and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8,
        "flow/mcap≥0.5% & near≥prev": lambda h: (h.get("flow_to_mcap") or 0) >= 0.005
        and (h.get("flow_near5") or 0) >= (h.get("flow_prev5") or 0),
        "flow/mcap≥0.5% & vol∈[1.2,1.8] & near≥prev": lambda h: (
            (h.get("flow_to_mcap") or 0) >= 0.005
            and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8
            and (h.get("flow_near5") or 0) >= (h.get("flow_prev5") or 0)
        ),
        "flow/mcap≥0.8% & vol∈[1.2,1.6] & near≥prev": lambda h: (
            (h.get("flow_to_mcap") or 0) >= 0.008
            and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.6
            and (h.get("flow_near5") or 0) >= (h.get("flow_prev5") or 0)
        ),
        "flow>1亿 & vol∈[1.2,1.8]": lambda h: (h.get("flow_sum_10") or 0) > 1e8
        and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8,
        "flow>3亿 & vol∈[1.2,1.8] & near≥prev": lambda h: (h.get("flow_sum_10") or 0) > 3e8
        and 1.2 <= (h.get("vol_ma_ratio") or 0) <= 1.8
        and (h.get("flow_near5") or 0) >= (h.get("flow_prev5") or 0),
    }

    rows = []
    for thr in (0.08, 0.10, 0.12, 0.15, 0.18, 0.20):
        for name, pred in filters.items():
            sub = [h for h in hits if pred(h)]
            res = ok(sub, thr)
            if not res:
                continue
            w, n, rate = res
            if rate >= 0.80:
                avg = statistics.mean(h.get("fwd_max_high_ret") or 0 for h in sub)
                rows.append((thr, rate, n, w, avg, name))

    rows.sort(key=lambda x: (x[0], x[1], x[2]), reverse=True)

    lines = [
        "# T+1最低价 · 胜率≥80% 条件探测",
        "",
        f"- 去重信号样本：{len(hits)}",
        f"- 最低样本数门槛：{min_n}",
        "- 成功定义：买入日起10日内最高价 / 次日最低价 - 1 ≥ 目标涨幅",
        "- 市值：仅要求 >100亿（不强制 <800亿）",
        "",
    ]
    if not rows:
        lines.append("**未找到同时满足 胜率≥80% 且样本≥门槛 的组合。** 需要继续扩样本或放宽门槛。")
        # show best near-80
        near = []
        for thr in (0.08, 0.10, 0.12):
            for name, pred in filters.items():
                sub = [h for h in hits if pred(h)]
                if len(sub) < max(8, min_n // 2):
                    continue
                w = sum(1 for h in sub if (h.get("fwd_max_high_ret") or 0) >= thr)
                rate = w / len(sub)
                near.append((thr, rate, len(sub), w, name))
        near.sort(key=lambda x: (x[0], x[1], x[2]), reverse=True)
        lines += ["", "## 接近80%的组合（参考）", ""]
        for thr, rate, n, w, name in near[:20]:
            lines.append(f"- 目标≥{thr:.0%} | 胜率{rate:.1%} ({w}/{n}) | {name}")
    else:
        lines += [
            "## 达标组合（按目标涨幅优先，再按胜率/样本）",
            "",
            "| 目标涨幅 | 胜率 | 成功/样本 | 平均最大涨幅 | 条件 |",
            "|---:|---:|---:|---:|---|",
        ]
        for thr, rate, n, w, avg, name in rows[:40]:
            lines.append(
                f"| ≥{thr:.0%} | {rate:.1%} | {w}/{n} | {avg:.1%} | {name} |"
            )

        # pick recommended: highest thr with n>=min_n and rate>=0.8
        best = rows[0]
        # among max thr, pick highest rate then n
        max_thr = max(r[0] for r in rows)
        cand = [r for r in rows if r[0] == max_thr]
        cand.sort(key=lambda x: (x[1], x[2]), reverse=True)
        best = cand[0]
        lines += [
            "",
            "## 建议冻结标准",
            "",
            f"- **目标涨幅：≥{best[0]:.0%}**（不低于8%）",
            f"- **条件：{best[5]}**",
            f"- **样本胜率：{best[1]:.1%}（{best[3]}/{best[2]}）**",
            f"- **平均最大涨幅：{best[4]:.1%}**",
            "- 入场：涨停次日最低价；持有观察窗：含买入日共10个交易日",
            "- 市值：>100亿；非ST；非北交；信号日涨停",
            "",
        ]

    out = "\n".join(lines) + "\n"
    JUDGMENT_FILE.write_text(out, encoding="utf-8")
    SUMMARY_FILE.write_text(write_summary(runs) + "\n---\n\n" + out, encoding="utf-8")
    return out


async def amain() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=20)
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--probe", action="store_true", help="基于已有命中网格搜索≥80%条件")
    parser.add_argument("--min-n", type=int, default=12, help="probe最小样本")
    parser.add_argument("--vol-ratio", type=float, default=None)
    parser.add_argument("--max-vol-ratio", type=float, default=None)
    parser.add_argument("--min-chg", type=float, default=None)
    parser.add_argument("--flow-mcap", type=float, default=None)
    parser.add_argument("--max-mcap", type=float, default=None)
    parser.add_argument("--limit-up-only", action="store_true")
    parser.add_argument("--success-ret", type=float, default=None)
    parser.add_argument("--no-flow-accel", action="store_true")
    args = parser.parse_args()

    if args.summary:
        print(write_summary(load_runs()))
        return
    if args.probe:
        print(probe_filters(load_runs(), min_n=args.min_n))
        return

    rules = dict(DEFAULT_RULES)
    if args.vol_ratio is not None:
        rules["min_vol_ma_ratio"] = args.vol_ratio
    if args.max_vol_ratio is not None:
        rules["max_vol_ma_ratio"] = args.max_vol_ratio
    if args.min_chg is not None:
        rules["min_signal_day_chg"] = args.min_chg
    if args.flow_mcap is not None:
        rules["min_flow_to_mcap"] = args.flow_mcap
    if args.max_mcap is not None:
        rules["max_market_cap_yi"] = args.max_mcap
    if args.limit_up_only:
        rules["prefer_limit_up"] = True
    if args.success_ret is not None:
        rules["success_ret"] = args.success_ret
    if args.no_flow_accel:
        rules["require_flow_accelerate"] = False

    for r in range(args.rounds):
        seed = args.seed if args.seed is not None else int(time.time()) + r * 17
        print(f"\n=== Round {r + 1}/{args.rounds} seed={seed} ===")
        try:
            payload = await run_one_round(n=args.n, seed=seed, rules=rules)
        except Exception as exc:  # noqa: BLE001
            print(f"  round failed: {exc}; sleep and continue")
            await asyncio.sleep(2.0)
            continue
        if int(payload.get("signal_count") or 0) > 0:
            append_run(payload)
        elif any(s.get("error") for s in (payload.get("stocks") or [])):
            print("  skip append: mostly failed fetches")
        else:
            append_run(payload)
        print(
            f"signals={payload['signal_count']} "
            f"wins={payload['success_count']} "
            f"win_rate={payload['win_rate']} "
            f"avg_high_ret={payload.get('avg_fwd_max_high_ret')}"
        )
        await asyncio.sleep(0.8)

    print("\n" + write_summary(load_runs()))
    print("\n" + probe_filters(load_runs(), min_n=args.min_n))


if __name__ == "__main__":
    asyncio.run(amain())
