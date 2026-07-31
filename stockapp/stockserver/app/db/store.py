from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from app.config import DATA_DIR, SETTINGS


def _db_path() -> Path:
    path = Path(SETTINGS.get("db_path", "data/stockserver.db"))
    if not path.is_absolute():
        path = DATA_DIR.parent / path
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def init_db() -> None:
    with connect() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS snapshots (
              code TEXT PRIMARY KEY,
              name TEXT,
              price REAL,
              change_pct REAL,
              amount REAL,
              score REAL,
              signal TEXT,
              updated_at TEXT NOT NULL,
              raw_json TEXT
            );

            CREATE TABLE IF NOT EXISTS bars (
              code TEXT NOT NULL,
              trade_date TEXT NOT NULL,
              open REAL,
              close REAL,
              high REAL,
              low REAL,
              volume REAL,
              amount REAL,
              change_pct REAL,
              PRIMARY KEY(code, trade_date)
            );

            CREATE TABLE IF NOT EXISTS shares (
              code TEXT NOT NULL,
              change_date TEXT NOT NULL,
              total_share REAL,
              apply_share REAL,
              redeem_share REAL,
              quarter_net REAL,
              share_change_q REAL,
              daily_net REAL,
              PRIMARY KEY(code, change_date)
            );

            CREATE TABLE IF NOT EXISTS scores (
              code TEXT PRIMARY KEY,
              score REAL NOT NULL,
              signal TEXT NOT NULL,
              factor_json TEXT,
              temperature_contrib REAL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS score_history (
              code TEXT NOT NULL,
              as_of TEXT NOT NULL,
              score REAL NOT NULL,
              signal TEXT,
              PRIMARY KEY(code, as_of)
            );

            CREATE TABLE IF NOT EXISTS alerts_cache (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              payload_json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_bars_code_date ON bars(code, trade_date);
            CREATE INDEX IF NOT EXISTS idx_shares_code_date ON shares(code, change_date);
            CREATE INDEX IF NOT EXISTS idx_score_hist_code ON score_history(code, as_of);
            """
        )


@contextmanager
def connect() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(_db_path())
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def upsert_snapshot(row: dict[str, Any]) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO snapshots(code, name, price, change_pct, amount, score, signal, updated_at, raw_json)
            VALUES(:code, :name, :price, :change_pct, :amount, :score, :signal, :updated_at, :raw_json)
            ON CONFLICT(code) DO UPDATE SET
              name=excluded.name,
              price=excluded.price,
              change_pct=excluded.change_pct,
              amount=excluded.amount,
              score=excluded.score,
              signal=excluded.signal,
              updated_at=excluded.updated_at,
              raw_json=excluded.raw_json
            """,
            row,
        )


def get_snapshot(code: str) -> dict[str, Any] | None:
    with connect() as conn:
        cur = conn.execute("SELECT * FROM snapshots WHERE code=?", (code,))
        row = cur.fetchone()
        return dict(row) if row else None


def list_snapshots() -> list[dict[str, Any]]:
    with connect() as conn:
        cur = conn.execute("SELECT * FROM snapshots ORDER BY code")
        return [dict(r) for r in cur.fetchall()]


def replace_bars(code: str, bars: list[dict[str, Any]]) -> None:
    with connect() as conn:
        conn.execute("DELETE FROM bars WHERE code=?", (code,))
        conn.executemany(
            """
            INSERT INTO bars(code, trade_date, open, close, high, low, volume, amount, change_pct)
            VALUES(:code, :trade_date, :open, :close, :high, :low, :volume, :amount, :change_pct)
            """,
            bars,
        )


def list_bars(code: str, limit: int = 320) -> list[dict[str, Any]]:
    with connect() as conn:
        cur = conn.execute(
            """
            SELECT * FROM bars WHERE code=?
            ORDER BY trade_date DESC LIMIT ?
            """,
            (code, limit),
        )
        rows = [dict(r) for r in cur.fetchall()]
    rows.reverse()
    return rows


def replace_shares(code: str, rows: list[dict[str, Any]]) -> None:
    with connect() as conn:
        conn.execute("DELETE FROM shares WHERE code=?", (code,))
        conn.executemany(
            """
            INSERT INTO shares(
              code, change_date, total_share, apply_share, redeem_share,
              quarter_net, share_change_q, daily_net
            ) VALUES(
              :code, :change_date, :total_share, :apply_share, :redeem_share,
              :quarter_net, :share_change_q, :daily_net
            )
            """,
            rows,
        )


def list_shares(code: str, limit: int = 500) -> list[dict[str, Any]]:
    with connect() as conn:
        cur = conn.execute(
            """
            SELECT * FROM shares WHERE code=?
            ORDER BY change_date DESC LIMIT ?
            """,
            (code, limit),
        )
        rows = [dict(r) for r in cur.fetchall()]
    rows.reverse()
    return rows


def upsert_score(row: dict[str, Any]) -> None:
    payload = dict(row)
    if isinstance(payload.get("factor_json"), (dict, list)):
        payload["factor_json"] = json.dumps(payload["factor_json"], ensure_ascii=False)
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO scores(code, score, signal, factor_json, temperature_contrib, updated_at)
            VALUES(:code, :score, :signal, :factor_json, :temperature_contrib, :updated_at)
            ON CONFLICT(code) DO UPDATE SET
              score=excluded.score,
              signal=excluded.signal,
              factor_json=excluded.factor_json,
              temperature_contrib=excluded.temperature_contrib,
              updated_at=excluded.updated_at
            """,
            payload,
        )


def get_score(code: str) -> dict[str, Any] | None:
    with connect() as conn:
        cur = conn.execute("SELECT * FROM scores WHERE code=?", (code,))
        row = cur.fetchone()
        if not row:
            return None
        d = dict(row)
        try:
            d["factors"] = json.loads(d.get("factor_json") or "[]")
        except json.JSONDecodeError:
            d["factors"] = []
        return d


def list_scores() -> list[dict[str, Any]]:
    with connect() as conn:
        cur = conn.execute("SELECT * FROM scores")
        out = []
        for row in cur.fetchall():
            d = dict(row)
            try:
                d["factors"] = json.loads(d.get("factor_json") or "[]")
            except json.JSONDecodeError:
                d["factors"] = []
            out.append(d)
        return out


def set_meta(key: str, value: str) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO meta(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
            """,
            (key, value),
        )


def get_meta(key: str) -> str | None:
    with connect() as conn:
        cur = conn.execute("SELECT value FROM meta WHERE key=?", (key,))
        row = cur.fetchone()
        return row["value"] if row else None


def append_score_history(code: str, score: float, signal: str, as_of: str | None = None) -> None:
    day = (as_of or utc_now_iso())[:10]
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO score_history(code, as_of, score, signal)
            VALUES(?, ?, ?, ?)
            ON CONFLICT(code, as_of) DO UPDATE SET
              score=excluded.score,
              signal=excluded.signal
            """,
            (code, day, score, signal),
        )


def list_score_history(code: str, limit: int = 10) -> list[dict[str, Any]]:
    with connect() as conn:
        cur = conn.execute(
            """
            SELECT * FROM score_history WHERE code=?
            ORDER BY as_of ASC
            """,
            (code,),
        )
        rows = [dict(r) for r in cur.fetchall()]
    return rows[-limit:] if limit else rows


def save_alerts_cache(alerts: list[dict[str, Any]]) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO alerts_cache(id, payload_json, updated_at)
            VALUES(1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              payload_json=excluded.payload_json,
              updated_at=excluded.updated_at
            """,
            (json.dumps(alerts, ensure_ascii=False), utc_now_iso()),
        )


def load_alerts_cache() -> tuple[list[dict[str, Any]], str | None]:
    with connect() as conn:
        cur = conn.execute("SELECT payload_json, updated_at FROM alerts_cache WHERE id=1")
        row = cur.fetchone()
        if not row:
            return [], None
        try:
            return json.loads(row["payload_json"] or "[]"), row["updated_at"]
        except json.JSONDecodeError:
            return [], row["updated_at"]


def save_json_meta(key: str, payload: Any) -> None:
    set_meta(key, json.dumps(payload, ensure_ascii=False))


def load_json_meta(key: str) -> Any | None:
    raw = get_meta(key)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
