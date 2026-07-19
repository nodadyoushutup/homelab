"""Non-swarm Docker host model and ``.config/docker/extra_hosts.yaml`` read/write.

An "extra host" is a machine that runs Docker but is **not** part of the Swarm
(e.g. an amd64 build host). It mirrors the swarm-node input shape so the Docker
provider catalog can derive a provider entry for it the same way, but it has no
``role`` and no ``labels`` - it is never init/joined into the swarm. The only
lifecycle action for an extra host is pushing/syncing SSH (key set +
authorized_keys), exactly like a swarm node's ``sync_ssh``.

Keys: ``name``, ``host``, ``ssh_user``, ``ssh_port``, ``ssh_key``,
``ssh_password``, ``sync_ssh``. ``ssh_key``/``ssh_password`` are only written when
set. The file lives under ``.config`` (git-ignored) - do not commit it.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import yaml

from homelab_config.hcl_util import atomic_write
from homelab_config.paths import EXTRA_HOSTS_YAML
from homelab_config.swarm_config import DEFAULT_SSH_PORT, DEFAULT_SSH_USER

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: docker/extra_hosts"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Non-swarm Docker hosts managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit hosts in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Same machine shape as swarm nodes (minus role/labels). The Docker provider\n"
    "# catalog (terraform/providers/docker) derives a provider entry for each of\n"
    "# these alongside the swarm nodes. These are NOT init/joined into the swarm;\n"
    "# their only lifecycle action is pushing/syncing SSH (key set + authorized_keys).\n"
    "# ssh_key (optional) names a key set under .config/.ssh/<ssh_key>.\n"
    "# ssh_password (optional) is only written when set, for password-based SSH.\n"
    "# sync_ssh (optional) marks the host to receive this key set + authorized_keys.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)


class ExtraHostValidationError(ValueError):
    """Raised when an extra-host payload fails validation."""


def normalize_extra_host(data: dict) -> dict:
    """Validate and normalize a raw extra-host payload into canonical shape.

    Raises:
        ExtraHostValidationError: When required fields are missing/invalid.
    """
    name = str(data.get("name") or "").strip()
    host = str(data.get("host") or "").strip()
    if not name and host:
        name = host.split(".", 1)[0]
    if not name:
        raise ExtraHostValidationError("name is required")
    if not all(ch.isalnum() or ch in "_-" for ch in name):
        raise ExtraHostValidationError(
            "name may only contain letters, digits, '-' and '_'"
        )
    if not host:
        raise ExtraHostValidationError("host is required")

    ssh_user = str(data.get("ssh_user") or data.get("user") or "").strip()
    ssh_user = ssh_user or DEFAULT_SSH_USER

    raw_port = data.get("ssh_port", DEFAULT_SSH_PORT)
    try:
        ssh_port = int(raw_port)
    except (TypeError, ValueError) as exc:
        raise ExtraHostValidationError("ssh_port must be an integer") from exc
    if not 1 <= ssh_port <= 65535:
        raise ExtraHostValidationError("ssh_port must be between 1 and 65535")

    ssh_key = str(data.get("ssh_key") or "").strip()
    raw_password = data.get("ssh_password")
    ssh_password = "" if raw_password is None else str(raw_password)
    sync_ssh = bool(data.get("sync_ssh"))

    return {
        "name": name,
        "host": host,
        "ssh_user": ssh_user,
        "ssh_port": ssh_port,
        "ssh_key": ssh_key,
        "ssh_password": ssh_password,
        "sync_ssh": sync_ssh,
    }


def order_extra_hosts(hosts: Iterable[dict]) -> list[dict]:
    """Return hosts sorted alphabetically by name."""
    return sorted(hosts, key=lambda h: h.get("name", ""))


def canonical(hosts: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(
        (
            h["name"],
            h["host"],
            h["ssh_user"],
            h["ssh_port"],
            h.get("ssh_key", ""),
            h.get("ssh_password", ""),
            h.get("sync_ssh", False),
        )
        for h in order_extra_hosts(hosts)
    )


def _host_document(host: dict) -> dict:
    """Build the ordered YAML mapping for one host (optional fields omitted)."""
    doc = {
        "name": host["name"],
        "host": host["host"],
        "user": host["ssh_user"],
        "ssh_port": host["ssh_port"],
    }
    if host.get("ssh_key"):
        doc["ssh_key"] = host["ssh_key"]
    if host.get("ssh_password"):
        doc["ssh_password"] = host["ssh_password"]
    if host.get("sync_ssh"):
        doc["sync_ssh"] = True
    return doc


def render_extra_hosts(hosts: Iterable[dict]) -> str:
    """Render the extra-hosts YAML document (including the config-id header)."""
    payload = {"hosts": [_host_document(h) for h in order_extra_hosts(hosts)]}
    body = yaml.safe_dump(payload, sort_keys=False, default_flow_style=False)
    return f"{_HEADER}{body}"


def read_extra_hosts(path: Path = EXTRA_HOSTS_YAML) -> list[dict] | None:
    """Parse extra_hosts.yaml into normalized host dicts.

    Returns a list (possibly empty when ``hosts: []``), or ``None`` when the file
    is missing, unparsable, or has no ``hosts`` key. Malformed entries are skipped.
    """
    if not path.is_file():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        logger.warning("Could not parse extra hosts %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw_hosts = data.get("hosts")
    if not isinstance(raw_hosts, list):
        return None

    hosts: list[dict] = []
    for entry in raw_hosts:
        if not isinstance(entry, dict):
            continue
        try:
            hosts.append(normalize_extra_host(entry))
        except ExtraHostValidationError as exc:
            logger.warning("Skipping invalid extra host in %s: %s", path, exc)
    return hosts


def write_extra_hosts(hosts: Iterable[dict], path: Path = EXTRA_HOSTS_YAML) -> Path:
    """Write the extra hosts to ``path`` atomically and return it."""
    atomic_write(path, render_extra_hosts(hosts))
    logger.info("Wrote extra Docker hosts to %s", path)
    return path


__all__ = [
    "ExtraHostValidationError",
    "canonical",
    "normalize_extra_host",
    "order_extra_hosts",
    "read_extra_hosts",
    "render_extra_hosts",
    "write_extra_hosts",
]
