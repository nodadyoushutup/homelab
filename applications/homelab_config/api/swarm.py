"""REST endpoints for managing Docker Swarm nodes.

The frontend talks to the backend over REST (this blueprint) and receives live
updates over Socket.IO: every mutation persists ``.config/docker/swarm.yaml``
and broadcasts the refreshed node list plus the rendered YAML.
"""

from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request

from homelab_config.extensions import db, socketio
from homelab_config.models import (
    DEFAULT_SSH_PORT,
    DEFAULT_SSH_USER,
    VALID_ROLES,
    SwarmNode,
)
from homelab_config.swarm_config import render_nodes, write_swarm_yaml

logger = logging.getLogger(__name__)

bp = Blueprint("swarm_api", __name__, url_prefix="/api/swarm")

EVENT_NODES = "swarm:nodes"
EVENT_CONFIG_WRITTEN = "config:written"


def _all_nodes() -> list[SwarmNode]:
    """Return all swarm nodes with managers first, then alphabetical by name."""
    return (
        SwarmNode.query.order_by(SwarmNode.role.asc(), SwarmNode.name.asc()).all()
    )


def _sync() -> list[SwarmNode]:
    """Persist swarm.yaml and broadcast the refreshed state to all clients.

    Returns:
        The current list of swarm nodes.
    """
    nodes = _all_nodes()
    path = write_swarm_yaml(nodes)
    payload = [node.to_dict() for node in nodes]
    socketio.emit(EVENT_NODES, payload)
    socketio.emit(
        EVENT_CONFIG_WRITTEN,
        {"path": str(path), "yaml": render_nodes(nodes)},
    )
    return nodes


def _read_node_fields(data: dict, *, existing: SwarmNode | None = None) -> tuple:
    """Validate and normalize a node payload.

    Args:
        data: Raw JSON request body.
        existing: Node being updated, if any (used to default unspecified
            fields on updates).

    Returns:
        A ``(fields, error, status)`` tuple. ``fields`` is ``None`` when
        validation fails; otherwise ``error``/``status`` are ``None``.
    """
    name = str(data.get("name", existing.name if existing else "") or "").strip()
    host = str(data.get("host", existing.host if existing else "") or "").strip()
    role = str(
        data.get("role", existing.role if existing else "") or ""
    ).strip().lower()
    ssh_user = str(
        data.get("ssh_user", existing.ssh_user if existing else DEFAULT_SSH_USER)
        or DEFAULT_SSH_USER
    ).strip()
    raw_port = data.get(
        "ssh_port", existing.ssh_port if existing else DEFAULT_SSH_PORT
    )
    raw_labels = data.get("labels", existing.labels if existing else {})

    if not name:
        return None, "name is required", 400
    if not host:
        return None, "host is required", 400
    if role not in VALID_ROLES:
        return None, f"role must be one of {', '.join(VALID_ROLES)}", 400
    try:
        ssh_port = int(raw_port)
    except (TypeError, ValueError):
        return None, "ssh_port must be an integer", 400
    if not 1 <= ssh_port <= 65535:
        return None, "ssh_port must be between 1 and 65535", 400
    labels = raw_labels if isinstance(raw_labels, dict) else {}

    fields = {
        "name": name,
        "host": host,
        "role": role,
        "ssh_user": ssh_user,
        "ssh_port": ssh_port,
        "labels": labels,
    }
    return fields, None, None


@bp.get("/nodes")
def list_nodes():
    """Return every swarm node."""
    return jsonify([node.to_dict() for node in _all_nodes()])


@bp.post("/nodes")
def create_node():
    """Create a new swarm node."""
    data = request.get_json(silent=True) or {}
    fields, error, status = _read_node_fields(data)
    if fields is None:
        return jsonify({"error": error}), status

    if SwarmNode.query.filter_by(name=fields["name"]).first():
        return jsonify({"error": f"node '{fields['name']}' already exists"}), 409

    node = SwarmNode(
        name=fields["name"],
        host=fields["host"],
        role=fields["role"],
        ssh_user=fields["ssh_user"],
        ssh_port=fields["ssh_port"],
    )
    node.labels = fields["labels"]
    db.session.add(node)
    db.session.commit()
    logger.info("Created swarm node %s (%s)", node.name, node.role)
    _sync()
    return jsonify(node.to_dict()), 201


@bp.put("/nodes/<int:node_id>")
def update_node(node_id: int):
    """Update an existing swarm node."""
    node = db.session.get(SwarmNode, node_id)
    if node is None:
        return jsonify({"error": "node not found"}), 404

    data = request.get_json(silent=True) or {}
    fields, error, status = _read_node_fields(data, existing=node)
    if fields is None:
        return jsonify({"error": error}), status

    clash = SwarmNode.query.filter(
        SwarmNode.name == fields["name"], SwarmNode.id != node_id
    ).first()
    if clash is not None:
        return jsonify({"error": f"node '{fields['name']}' already exists"}), 409

    node.name = fields["name"]
    node.host = fields["host"]
    node.role = fields["role"]
    node.ssh_user = fields["ssh_user"]
    node.ssh_port = fields["ssh_port"]
    node.labels = fields["labels"]
    db.session.commit()
    logger.info("Updated swarm node %s (%s)", node.name, node.role)
    _sync()
    return jsonify(node.to_dict())


@bp.delete("/nodes/<int:node_id>")
def delete_node(node_id: int):
    """Delete a swarm node."""
    node = db.session.get(SwarmNode, node_id)
    if node is None:
        return jsonify({"error": "node not found"}), 404

    name = node.name
    db.session.delete(node)
    db.session.commit()
    logger.info("Deleted swarm node %s", name)
    _sync()
    return jsonify({"deleted": node_id})


@bp.get("/yaml")
def preview_yaml():
    """Return the rendered swarm.yaml for the current node set."""
    return jsonify({"yaml": render_nodes(_all_nodes())})


@bp.post("/apply")
def apply_config():
    """Re-write swarm.yaml from the current node set and broadcast it."""
    nodes = _sync()
    return jsonify({"written": True, "count": len(nodes)})


__all__ = ["bp"]
