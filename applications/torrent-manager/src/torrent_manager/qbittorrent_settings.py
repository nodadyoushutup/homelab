"""qBittorrent client connection settings parsed from YAML."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any
from urllib import parse

_CLIENT_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


def normalize_base_url(value: str) -> str:
    """Normalize a qBittorrent Web UI base URL."""
    cleaned = value.strip()
    if not cleaned:
        raise ValueError("base_url cannot be empty")
    if "://" not in cleaned:
        cleaned = f"http://{cleaned}"
    return cleaned.rstrip("/")


@dataclass(frozen=True, slots=True)
class QBitTorrentClientConfig:
    """Connection settings for one qBittorrent Web API client."""

    client_id: str
    base_url: str
    username: str
    password: str
    host_header: str | None = None
    insecure_tls: bool = False
    timeout_sec: int = 20


def _validate_client_id(client_id: str) -> str:
    normalized = client_id.strip()
    if not normalized:
        raise ValueError("client id cannot be empty")
    if not _CLIENT_ID_PATTERN.fullmatch(normalized):
        raise ValueError(
            f"invalid client id {client_id!r}; use letters, numbers, and underscores only"
        )
    return normalized


def _client_from_mapping(raw: dict[str, Any], *, defaults: dict[str, Any]) -> QBitTorrentClientConfig:
    client_id = _validate_client_id(str(raw.get("id") or raw.get("client_id") or ""))
    base_url = normalize_base_url(str(raw.get("base_url") or ""))

    username = str(raw.get("username") or defaults["username"]).strip()
    password = str(raw.get("password") or defaults["password"]).strip()
    if not password:
        raise ValueError(f"password is required for qBittorrent client {client_id!r}")

    insecure_tls = raw.get("insecure_tls")
    if insecure_tls is None:
        insecure_tls = defaults["insecure_tls"]
    else:
        insecure_tls = bool(insecure_tls)

    timeout_raw = raw.get("timeout_sec")
    timeout_sec = int(timeout_raw) if timeout_raw is not None else int(defaults["timeout_sec"])

    host_header_raw = raw.get("host_header")
    host_header = str(host_header_raw).strip() if host_header_raw else None

    return QBitTorrentClientConfig(
        client_id=client_id,
        base_url=base_url,
        username=username,
        password=password,
        host_header=host_header,
        insecure_tls=insecure_tls,
        timeout_sec=timeout_sec,
    )


def parse_qbittorrent_clients(raw: dict[str, Any] | None) -> tuple[QBitTorrentClientConfig, ...]:
    """Parse the ``qbittorrent`` section from the YAML config."""
    section = raw or {}
    defaults_raw = section.get("defaults") or {}
    defaults = {
        "username": str(defaults_raw.get("username") or "admin").strip(),
        "password": str(defaults_raw.get("password") or "").strip(),
        "insecure_tls": bool(defaults_raw.get("insecure_tls", False)),
        "timeout_sec": int(defaults_raw.get("timeout_sec", 20)),
    }

    clients_raw = section.get("clients") or []
    if not isinstance(clients_raw, list):
        raise ValueError("qbittorrent.clients must be a YAML list")

    clients: list[QBitTorrentClientConfig] = []
    seen: set[str] = set()
    for index, item in enumerate(clients_raw):
        if not isinstance(item, dict):
            raise ValueError(f"qbittorrent.clients[{index}] must be a mapping")
        config = _client_from_mapping(item, defaults=defaults)
        if config.client_id in seen:
            raise ValueError(f"duplicate qBittorrent client id: {config.client_id!r}")
        seen.add(config.client_id)
        clients.append(config)
    return tuple(clients)


def client_display_host(base_url: str) -> str:
    """Return a short host label suitable for UI tables."""
    parsed = parse.urlsplit(base_url)
    return parsed.netloc or parsed.path
