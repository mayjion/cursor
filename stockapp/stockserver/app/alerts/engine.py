"""预警：涨幅、拥挤、评分连降、events.yaml 手工事件。"""
from __future__ import annotations

from typing import Any

from app.config import events as load_events
from app.db import store
from app.factors.engine import flow_burst, momentum


def _level(kind: str) -> str:
    return {"risk": "risk", "watch": "watch", "info": "info"}.get(kind, "info")


def evaluate_alerts(
    cards: list[dict[str, Any]],
    *,
    change_threshold: float = 5.0,
    flow_burst_threshold: float = 2.0,
    score_drop_days: int = 3,
) -> list[dict[str, Any]]:
    alerts: list[dict[str, Any]] = []

    for c in cards:
        code = str(c["code"])
        name = c.get("name") or code
        chg = c.get("change_pct")
        if chg is not None and abs(float(chg)) >= change_threshold:
            direction = "大涨" if float(chg) > 0 else "大跌"
            alerts.append(
                {
                    "type": "risk" if float(chg) < 0 else "watch",
                    "code": code,
                    "name": name,
                    "title": f"{name} 单日{direction} {float(chg):+.2f}%",
                    "detail": f"涨跌幅阈值 {change_threshold}%",
                    "source": "rule:change_pct",
                }
            )

        shares = store.list_shares(code, limit=500)
        burst = flow_burst(shares)
        bars = store.list_bars(code, limit=40)
        mom5 = momentum(bars, 5)
        if (
            burst is not None
            and burst >= flow_burst_threshold
            and mom5 is not None
            and mom5 > 0.08
        ):
            alerts.append(
                {
                    "type": "watch",
                    "code": code,
                    "name": name,
                    "title": f"{name} 净申购突发叠加短线大涨（拥挤关注）",
                    "detail": f"flow_burst={burst:.2f}x，5日动量 {mom5*100:.1f}%",
                    "source": "rule:crowding",
                }
            )

        hist = store.list_score_history(code, limit=score_drop_days + 1)
        if len(hist) >= score_drop_days + 1:
            # hist 新→旧 或 旧→新？list_score_history 按时间升序
            recent = hist[-(score_drop_days + 1) :]
            drops = all(
                recent[i]["score"] > recent[i + 1]["score"] for i in range(len(recent) - 1)
            )
            if drops:
                alerts.append(
                    {
                        "type": "watch",
                        "code": code,
                        "name": name,
                        "title": f"{name} 评分连续 {score_drop_days} 日下行",
                        "detail": " → ".join(f"{h['score']:.1f}" for h in recent),
                        "source": "rule:score_drop",
                    }
                )

        if (c.get("signal") == "red") and (c.get("score") is not None) and float(c["score"]) < 25:
            alerts.append(
                {
                    "type": "info",
                    "code": code,
                    "name": name,
                    "title": f"{name} 综合评分极弱（{c['score']}）",
                    "detail": "红灯且评分 < 25",
                    "source": "rule:weak_score",
                }
            )

    for ev in load_events().get("events") or []:
        alerts.append(
            {
                "type": _level(str(ev.get("type") or "info")),
                "code": ev.get("code"),
                "name": ev.get("name") or ev.get("title"),
                "title": ev.get("title") or "手工事件",
                "detail": ev.get("detail") or "",
                "source": "events.yaml",
                "date": ev.get("date"),
            }
        )

    order = {"risk": 0, "watch": 1, "info": 2}
    alerts.sort(key=lambda a: order.get(str(a.get("type")), 9))
    return alerts
