"""REST endpoints for editing the VictoriaMetrics Swarm app settings.

The on-disk ``.config/terraform/components/swarm/victoriametrics/app.tfvars`` is
the source of truth and every edit is persisted immediately (auto-save): the PUT
replaces the in-memory working copy, writes it to disk, and broadcasts the
result live over Socket.IO. ``/reload`` re-reads the file for out-of-band edits.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.victoriametrics_config import ConfigValidationError
from homelab_config.victoriametrics_store import VictoriaMetricsConfigStore

logger = logging.getLogger(__name__)

bp = Blueprint(
    "victoriametrics_config_api",
    __name__,
    url_prefix="/api/monitoring/victoriametrics",
)

EVENT_CONFIG = "victoriametrics_config:config"
EVENT_STATUS = "victoriametrics_config:status"


def _store() -> VictoriaMetricsConfigStore:
    return current_app.config["VICTORIAMETRICS_CONFIG_STORE"]


def broadcast(store: VictoriaMetricsConfigStore) -> None:
    """Emit the current working settings and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


@bp.get("/config")
def get_config():
    """Return the working settings plus drift/status flags."""
    store = _store()
    return jsonify({"config": store.get(), "status": store.status()})


@bp.put("/config")
def set_config():
    """Replace the settings and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.set(data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    logger.info("Updated VictoriaMetrics app settings")
    store.write()
    broadcast(store)
    return jsonify(record)


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered app.tfvars for the working copy."""
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
    logger.info("Reloaded VictoriaMetrics config from disk")
    broadcast(store)
    return jsonify({"config": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
