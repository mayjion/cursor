"""局域网发现：UDP 广播，供 App 同网自动搜索。"""
from __future__ import annotations

import asyncio
import json
import logging
import socket
from typing import Any

from app.config import SETTINGS

logger = logging.getLogger("stockserver.discovery")

SERVICE_NAME = "stockserver"
DEFAULT_DISCOVERY_PORT = 48787

_task: asyncio.Task[None] | None = None
_stop = asyncio.Event()


def discovery_port() -> int:
    return int(SETTINGS.get("discovery_port", DEFAULT_DISCOVERY_PORT))


def http_port() -> int:
    return int(SETTINGS.get("port", 8787))


def local_ipv4_addresses() -> list[str]:
    ips: list[str] = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = info[4][0]
            if ip and not ip.startswith("127.") and ip not in ips:
                ips.append(ip)
    except OSError:
        pass
    # 额外：连一个 UDP 探测拿到出网网卡 IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127.") and ip not in ips:
            ips.insert(0, ip)
    except OSError:
        pass
    return ips


def health_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "service": SERVICE_NAME,
        "name": "星沉观察",
        "data_policy": "public_only",
        "http_port": http_port(),
        "discovery_port": discovery_port(),
        "lan_ips": local_ipv4_addresses(),
        "version": "0.3.0",
    }


def _beacon_bytes() -> bytes:
    payload = {
        "service": SERVICE_NAME,
        "name": "星沉观察",
        "http_port": http_port(),
        "discovery_port": discovery_port(),
        "lan_ips": local_ipv4_addresses(),
    }
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _send_beacon_once() -> None:
    port = discovery_port()
    data = _beacon_bytes()
    targets = [("255.255.255.255", port)]
    for ip in local_ipv4_addresses():
        parts = ip.split(".")
        if len(parts) == 4:
            targets.append((f"{parts[0]}.{parts[1]}.{parts[2]}.255", port))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.settimeout(1.0)
        for addr in targets:
            try:
                sock.sendto(data, addr)
            except OSError:
                continue
    finally:
        sock.close()


async def _broadcast_loop() -> None:
    logger.info("LAN discovery beacon on UDP %s (http %s)", discovery_port(), http_port())
    while not _stop.is_set():
        try:
            await asyncio.to_thread(_send_beacon_once)
        except Exception:  # noqa: BLE001
            logger.exception("discovery beacon send failed")
        try:
            await asyncio.wait_for(_stop.wait(), timeout=3.0)
        except asyncio.TimeoutError:
            pass


def start_discovery_beacon() -> None:
    global _task
    if _task is not None and not _task.done():
        return
    _stop.clear()
    _task = asyncio.create_task(_broadcast_loop(), name="stockserver-discovery")


async def stop_discovery_beacon() -> None:
    global _task
    _stop.set()
    if _task is not None:
        try:
            await asyncio.wait_for(_task, timeout=2.0)
        except (asyncio.TimeoutError, asyncio.CancelledError):
            _task.cancel()
        _task = None
