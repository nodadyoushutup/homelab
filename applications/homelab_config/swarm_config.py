"""Render and persist ``.config/docker/swarm.yaml`` from swarm node records."""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import yaml

from homelab_config.models import ROLE_MANAGER, SwarmNode
from homelab_config.paths import SWARM_YAML

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: docker/swarm"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Docker Swarm topology managed by the homelab-config web app\n"
    "# (applications/homelab_config) and consumed by the bootstrap app.\n"
    "# Generated file: edit nodes in the UI rather than by hand.\n"
    "#\n"
    "# Exactly one node must have role: manager (the control plane).\n"
    "# Passwords are never stored here; key-based SSH auth is used first with an\n"
    "# interactive password fallback at connect time.\n"
)


def _node_payload(node: SwarmNode) -> dict:
    """Return the swarm.yaml mapping for a single node."""
    return {
        "name": node.name,
        "host": node.host,
        "user": node.ssh_user,
        "role": node.role,
        "ssh_port": node.ssh_port,
        "labels": node.labels,
    }


def _ordered(nodes: Iterable[SwarmNode]) -> list[SwarmNode]:
    """Return nodes with managers first, then workers, alphabetical by name."""
    return sorted(
        nodes,
        key=lambda node: (0 if node.role == ROLE_MANAGER else 1, node.name),
    )


def render_nodes(nodes: Iterable[SwarmNode]) -> str:
    """Render the swarm topology YAML document (including the config-id header).

    Args:
        nodes: Swarm node records.

    Returns:
        The full YAML document as a string.
    """
    payload = {"nodes": [_node_payload(node) for node in _ordered(nodes)]}
    body = yaml.safe_dump(payload, sort_keys=False, default_flow_style=False)
    return f"{_HEADER}{body}"


def write_swarm_yaml(
    nodes: Iterable[SwarmNode], path: Path = SWARM_YAML
) -> Path:
    """Write the swarm topology to ``path`` and return it.

    Args:
        nodes: Swarm node records.
        path: Destination file; defaults to ``.config/docker/swarm.yaml``.

    Returns:
        The path that was written.
    """
    content = render_nodes(nodes)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    logger.info("Wrote swarm topology to %s", path)
    return path


__all__ = ["render_nodes", "write_swarm_yaml"]
