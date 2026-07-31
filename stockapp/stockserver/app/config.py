from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT / "config"
DATA_DIR = ROOT / "data"


class EnvSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    host: str = "0.0.0.0"
    port: int = 8787
    admin_token: str = ""


@lru_cache
def load_yaml(name: str) -> dict[str, Any]:
    path = CONFIG_DIR / name
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"invalid yaml root in {name}")
    return data


def reload_configs() -> None:
    load_yaml.cache_clear()


def settings() -> dict[str, Any]:
    base = load_yaml("settings.yaml")
    env = EnvSettings()
    base["host"] = env.host or base.get("host", "0.0.0.0")
    base["port"] = env.port or base.get("port", 8787)
    base["admin_token"] = env.admin_token
    return base


def universe() -> dict[str, Any]:
    return load_yaml("etf_universe.yaml")


def events() -> dict[str, Any]:
    return load_yaml("events.yaml")


def timing_rules_cfg() -> dict[str, Any]:
    return load_yaml("timing_rules.yaml")


def stock_screen_cfg() -> dict[str, Any]:
    return load_yaml("stock_screen.yaml")


SETTINGS = settings()
