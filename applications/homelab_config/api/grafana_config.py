"""REST endpoints for editing the Grafana data sources desired-state config.

The on-disk ``.config/terraform/components/swarm/grafana/config.tfvars`` is the
source of truth and every edit is persisted immediately (auto-save): mutations
update the in-memory working copy, write it to disk, and broadcast the result
live over Socket.IO. ``/reload`` re-reads the file to pick up out-of-band edits.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.grafana_config import ConfigValidationError
from homelab_config.grafana_store import GrafanaConfigStore, StoreError

logger = logging.getLogger(__name__)

bp = Blueprint("grafana_config_api", __name__, url_prefix="/api/monitoring/grafana")

EVENT_CONFIG = "grafana_config:config"
EVENT_STATUS = "grafana_config:status"


def _store() -> GrafanaConfigStore:
    return current_app.config["GRAFANA_CONFIG_STORE"]


def broadcast(store: GrafanaConfigStore) -> None:
    """Emit the current working datasources and status to all clients."""
    socketio.emit(EVENT_CONFIG, {"datasources": store.list()})
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: GrafanaConfigStore) -> None:
    store.write()
    broadcast(store)


@bp.get("/config")
def get_config():
    """Return the working datasources plus drift/status flags."""
    store = _store()
    return jsonify({"datasources": store.list(), "status": store.status()})


@bp.post("/datasources")
def create_datasource():
    """Add a datasource and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        entry = store.add(data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Grafana datasource %s", entry.get("uid"))
    _persist(store)
    return jsonify(entry), 201


@bp.put("/datasources/<key>")
def update_datasource(key: str):
    """Update a datasource and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        entry = store.update(key, data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Grafana datasource %s", key)
    _persist(store)
    return jsonify(entry)


@bp.delete("/datasources/<key>")
def delete_datasource(key: str):
    """Delete a datasource and persist immediately (auto-save)."""
    store = _store()
    try:
        store.delete(key)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted Grafana datasource %s", key)
    _persist(store)
    return jsonify({"deleted": key})


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered config.tfvars for the working copy."""
    return jsonify({"tfvars": _store().render()})


@bp.get("/status")
def status():
    """Return drift/status flags."""
    return jsonify(_store().status())


@bp.post("/reload")
def reload_config():
    """Reload the working copy from disk to pick up out-of-band changes."""
    store = _store()
    store.reload()
    logger.info("Reloaded Grafana config from disk")
    broadcast(store)
    return jsonify({"datasources": store.list(), "status": store.status()})


__all__ = ["bp", "broadcast"]
