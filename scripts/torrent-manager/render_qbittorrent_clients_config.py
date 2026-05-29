#!/usr/bin/env python3
"""Render torrent-manager qBittorrent client entries from K8s overlay ingress patches."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
OVERLAYS = ROOT / "kubernetes" / "qbittorrent" / "overlays"
HOST_RE = re.compile(r"^\s*-\s*host:\s*(\S+)\s*$")


def discover_clients(*, ingress_base_url: str) -> list[dict[str, str]]:
    clients: list[dict[str, str]] = []
    for ingress_path in sorted(OVERLAYS.glob("*/ingress-patch.yaml")):
        overlay_id = ingress_path.parent.name
        host: str | None = None
        for line in ingress_path.read_text(encoding="utf-8").splitlines():
            match = HOST_RE.match(line)
            if match:
                host = match.group(1)
                break
        if not host:
            raise RuntimeError(f"no ingress host found in {ingress_path}")
        clients.append(
            {
                "id": overlay_id,
                "base_url": ingress_base_url,
                "host_header": host,
            }
        )
    return clients


def build_config(
    *,
    password: str,
    username: str = "admin",
    secret_key: str = "dev-only-change-me",
    ingress_base_url: str = "http://192.168.1.241",
) -> dict:
    return {
        "app": {
            "secret_key": secret_key,
            "database_url": "sqlite:////data/torrent-manager.db",
            "debug": False,
            "sqlalchemy_echo": False,
        },
        "qbittorrent": {
            "defaults": {
                "username": username,
                "password": password,
                "insecure_tls": False,
                "timeout_sec": 20,
            },
            "clients": discover_clients(ingress_base_url=ingress_base_url),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / ".config" / "torrent-manager" / "config.yaml",
        help="Destination YAML path",
    )
    parser.add_argument("--password", required=True)
    parser.add_argument("--username", default="admin")
    parser.add_argument("--secret-key", default="dev-only-change-me")
    parser.add_argument(
        "--ingress-base-url",
        default="http://192.168.1.241",
        help="Shared ingress LB URL; per-client Host header selects the qBittorrent instance",
    )
    args = parser.parse_args()

    payload = build_config(
        password=args.password,
        username=args.username,
        secret_key=args.secret_key,
        ingress_base_url=args.ingress_base_url,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "# homelab-config: torrent-manager\n"
        + yaml.safe_dump(payload, sort_keys=False, default_flow_style=False),
        encoding="utf-8",
    )
    print(f"wrote {len(payload['qbittorrent']['clients'])} clients to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
