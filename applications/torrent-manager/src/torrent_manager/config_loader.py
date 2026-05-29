"""Load torrent-manager settings from a YAML file."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from torrent_manager.qbittorrent_settings import QBitTorrentClientConfig, parse_qbittorrent_clients

_CONTAINER_DEFAULT = Path("/etc/torrent-manager/config.yaml")
_BUNDLED_DEFAULT = Path(__file__).resolve().parents[2] / "config" / "config.yaml"


@dataclass(frozen=True, slots=True)
class Config:
    """Application settings loaded from YAML."""

    secret_key: str
    database_url: str
    debug: bool
    qbittorrent_clients: tuple[QBitTorrentClientConfig, ...] = ()
    config_path: Path | None = None
    testing: bool = False
    sqlalchemy_echo: bool = False


def resolve_config_path(explicit: str | Path | None = None) -> Path:
    """Return the YAML config path to load.

    Resolution order:

    1. ``explicit`` argument
    2. ``TORRENT_MANAGER_CONFIG_PATH`` environment variable
    3. ``/etc/torrent-manager/config.yaml`` when present (container default)
    4. Bundled repo default at ``applications/torrent-manager/config/config.yaml``
    """
    if explicit is not None:
        path = Path(explicit)
        if not path.is_file():
            raise FileNotFoundError(f"config file not found: {path}")
        return path

    env_path = (os.getenv("TORRENT_MANAGER_CONFIG_PATH") or "").strip()
    if env_path:
        path = Path(env_path)
        if not path.is_file():
            raise FileNotFoundError(f"config file not found: {path}")
        return path

    if _CONTAINER_DEFAULT.is_file():
        return _CONTAINER_DEFAULT

    if _BUNDLED_DEFAULT.is_file():
        return _BUNDLED_DEFAULT

    raise FileNotFoundError(
        "no torrent-manager config file found; set TORRENT_MANAGER_CONFIG_PATH or "
        f"create {_CONTAINER_DEFAULT} or {_BUNDLED_DEFAULT}"
    )


def _require_mapping(raw: Any, label: str) -> dict[str, Any]:
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be a YAML mapping")
    return raw


def load_config(
    *,
    path: str | Path | None = None,
    testing: bool = False,
    overrides: dict[str, Any] | None = None,
) -> Config:
    """Load settings from YAML."""
    if testing:
        return Config(
            secret_key="test",
            database_url="sqlite:///:memory:",
            debug=False,
            qbittorrent_clients=(),
            testing=True,
        )

    config_path = resolve_config_path(path)
    payload = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if payload is None:
        payload = {}
    if not isinstance(payload, dict):
        raise ValueError("config root must be a YAML mapping")

    if overrides:
        payload = _deep_merge(payload, overrides)

    app_section = _require_mapping(payload.get("app"), "app")
    secret_key = str(app_section.get("secret_key") or "dev-only-change-me").strip()
    database_url = str(app_section.get("database_url") or "sqlite:////data/torrent-manager.db").strip()

    qbittorrent_section = payload.get("qbittorrent")
    if qbittorrent_section is not None and not isinstance(qbittorrent_section, dict):
        raise ValueError("qbittorrent must be a YAML mapping")

    return Config(
        secret_key=secret_key,
        database_url=database_url,
        debug=bool(app_section.get("debug", False)),
        sqlalchemy_echo=bool(app_section.get("sqlalchemy_echo", False)),
        qbittorrent_clients=parse_qbittorrent_clients(qbittorrent_section),
        config_path=config_path,
    )


def _deep_merge(base: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged
