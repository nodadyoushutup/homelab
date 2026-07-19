"""Swarm node model helpers and ``.config/docker/swarm.tfvars`` read/write.

The file is the source of truth. A "node" is a plain dict with the keys:
``name``, ``host``, ``ssh_user``, ``role``, ``ssh_port``, ``ssh_key``,
``ssh_password``, ``sync_ssh``, ``labels``.

``ssh_key`` (optional) names the SSH key set under ``.config/.ssh/<ssh_key>``
used to reach the node (see the homelab-config SSH page). ``ssh_password``
(optional) allows password-based SSH when no key set is available. Both are only
written to the file when set. The file lives under ``.config`` (git-ignored).

The topology renders to an HCL ``swarm_nodes`` map (keyed by node name) so it
reads like every other tfvars under ``.config``. The map is consumed only by the
homelab-config app itself (to derive the Docker provider catalog and reconcile
the live swarm); it is not passed to Terraform directly.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_str, hcl_escape
from homelab_config.paths import SWARM_TFVARS

logger = logging.getLogger(__name__)

ROLE_MANAGER = "manager"
ROLE_WORKER = "worker"
VALID_ROLES = (ROLE_MANAGER, ROLE_WORKER)

DEFAULT_SSH_USER = "nodadyoushutup"
DEFAULT_SSH_PORT = 22

_CONFIG_TAG = "# homelab-config: docker/swarm"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Docker Swarm topology managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit nodes in the UI (or by hand) then write it back.\n"
    "#\n"
    "# swarm_nodes is a map keyed by node name. Exactly one node must have\n"
    "# role = \"manager\" (the control plane); the rest are workers.\n"
    "# ssh_key (optional) names a key set under .config/.ssh/<ssh_key>.\n"
    "# ssh_password (optional) is only written when set, for password-based SSH.\n"
    "# sync_ssh (optional) marks the node to receive this key set + its\n"
    "#   authorized_keys during bootstrap (key auth first, password fallback).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)


class NodeValidationError(ValueError):
    """Raised when a node payload fails validation."""


def normalize_node(data: dict) -> dict:
    """Validate and normalize a raw node payload into the canonical shape.

    Args:
        data: Raw node mapping (from the API or a parsed tfvars entry).

    Returns:
        A normalized node dict.

    Raises:
        NodeValidationError: When required fields are missing or invalid.
    """
    name = str(data.get("name") or "").strip()
    host = str(data.get("host") or "").strip()
    if not name and host:
        name = host.split(".", 1)[0]
    if not name:
        raise NodeValidationError("name is required")
    if not host:
        raise NodeValidationError("host is required")

    role = str(data.get("role") or ROLE_WORKER).strip().lower()
    if role not in VALID_ROLES:
        raise NodeValidationError(
            f"role must be one of {', '.join(VALID_ROLES)}"
        )

    ssh_user = str(data.get("ssh_user") or data.get("user") or "").strip()
    ssh_user = ssh_user or DEFAULT_SSH_USER

    raw_port = data.get("ssh_port", DEFAULT_SSH_PORT)
    try:
        ssh_port = int(raw_port)
    except (TypeError, ValueError) as exc:
        raise NodeValidationError("ssh_port must be an integer") from exc
    if not 1 <= ssh_port <= 65535:
        raise NodeValidationError("ssh_port must be between 1 and 65535")

    # ssh_key is optional: an empty value means "no key set" (e.g. password auth).
    ssh_key = str(data.get("ssh_key") or "").strip()

    raw_password = data.get("ssh_password")
    ssh_password = "" if raw_password is None else str(raw_password)

    sync_ssh = bool(data.get("sync_ssh"))

    raw_labels = data.get("labels") or {}
    labels: dict[str, str] = {}
    if isinstance(raw_labels, dict):
        for key, value in raw_labels.items():
            cleaned_key = str(key).strip()
            if cleaned_key:
                labels[cleaned_key] = str(value).strip()

    return {
        "name": name,
        "host": host,
        "ssh_user": ssh_user,
        "role": role,
        "ssh_port": ssh_port,
        "ssh_key": ssh_key,
        "ssh_password": ssh_password,
        "sync_ssh": sync_ssh,
        "labels": labels,
    }


def order_nodes(nodes: Iterable[dict]) -> list[dict]:
    """Return nodes with managers first, then workers, alphabetical by name."""
    return sorted(
        nodes,
        key=lambda node: (0 if node.get("role") == ROLE_MANAGER else 1, node.get("name", "")),
    )


def canonical(nodes: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(
        (
            node["name"],
            node["host"],
            node["ssh_user"],
            node["role"],
            node["ssh_port"],
            node.get("ssh_key", ""),
            node.get("ssh_password", ""),
            node.get("sync_ssh", False),
            tuple(sorted(node.get("labels", {}).items())),
        )
        for node in order_nodes(nodes)
    )


def _render_labels(labels: dict[str, str]) -> str:
    """Render the ``labels`` object (empty map on one line, else one key/line)."""
    if not labels:
        return "    labels = {}\n"
    lines = ["    labels = {\n"]
    for key in sorted(labels):
        lines.append(f'      "{hcl_escape(key)}" = "{hcl_escape(labels[key])}"\n')
    lines.append("    }\n")
    return "".join(lines)


def _render_node_block(node: dict) -> str:
    """Render one ``"<name>" = { ... }`` entry (optional fields omitted)."""
    lines = [
        f'  "{hcl_escape(node["name"])}" = {{\n',
        f'    host         = "{hcl_escape(node["host"])}"\n',
        f'    user         = "{hcl_escape(node["ssh_user"])}"\n',
        f'    role         = "{hcl_escape(node["role"])}"\n',
        f'    ssh_port     = {int(node["ssh_port"])}\n',
    ]
    if node.get("ssh_key"):
        lines.append(f'    ssh_key      = "{hcl_escape(node["ssh_key"])}"\n')
    if node.get("ssh_password"):
        lines.append(f'    ssh_password = "{hcl_escape(node["ssh_password"])}"\n')
    if node.get("sync_ssh"):
        lines.append("    sync_ssh     = true\n")
    lines.append(_render_labels(node.get("labels", {})))
    lines.append("  }\n")
    return "".join(lines)


def render_nodes(nodes: Iterable[dict]) -> str:
    """Render the swarm topology tfvars document (including the config-id header)."""
    body = "swarm_nodes = {\n"
    body += "".join(_render_node_block(node) for node in order_nodes(nodes))
    body += "}\n"
    return f"{_HEADER}{body}"


def read_swarm_tfvars(path: Path = SWARM_TFVARS) -> list[dict] | None:
    """Parse swarm.tfvars into normalized node dicts.

    Args:
        path: Source file; defaults to ``.config/docker/swarm.tfvars``.

    Returns:
        A list of normalized node dicts (possibly empty when the file declares
        ``swarm_nodes = {}``), or ``None`` when the file is missing, unparsable,
        or has no ``swarm_nodes`` key. Malformed individual entries are skipped
        with a warning.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse swarm topology %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw_nodes = data.get("swarm_nodes")
    if not isinstance(raw_nodes, dict):
        return None

    nodes: list[dict] = []
    for key, entry in raw_nodes.items():
        if not isinstance(entry, dict):
            continue
        raw_labels = entry.get("labels")
        labels: dict[str, str] = {}
        if isinstance(raw_labels, dict):
            for label_key, label_value in raw_labels.items():
                labels[coerce_str(label_key)] = coerce_str(label_value)
        payload = {
            "name": coerce_str(key),
            "host": coerce_str(entry.get("host")),
            "ssh_user": coerce_str(entry.get("user") or entry.get("ssh_user")),
            "role": coerce_str(entry.get("role")),
            "ssh_port": entry.get("ssh_port", DEFAULT_SSH_PORT),
            "ssh_key": coerce_str(entry.get("ssh_key")),
            "ssh_password": coerce_str(entry.get("ssh_password")),
            "sync_ssh": entry.get("sync_ssh", False),
            "labels": labels,
        }
        try:
            nodes.append(normalize_node(payload))
        except NodeValidationError as exc:
            logger.warning("Skipping invalid swarm node in %s: %s", path, exc)
            continue
    return nodes


def write_swarm_tfvars(nodes: Iterable[dict], path: Path = SWARM_TFVARS) -> Path:
    """Write the swarm topology to ``path`` atomically and return it.

    Writes to a temp file in the same directory then ``os.replace``s it into
    place, so a concurrent reader (e.g. the drift watcher) never observes a
    partially written file and reports a spurious out-of-band change.
    """
    atomic_write(path, render_nodes(nodes))
    logger.info("Wrote swarm topology to %s", path)
    return path


__all__ = [
    "DEFAULT_SSH_PORT",
    "DEFAULT_SSH_USER",
    "ROLE_MANAGER",
    "ROLE_WORKER",
    "VALID_ROLES",
    "NodeValidationError",
    "canonical",
    "normalize_node",
    "order_nodes",
    "read_swarm_tfvars",
    "render_nodes",
    "write_swarm_tfvars",
]
