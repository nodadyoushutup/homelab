"""REST endpoints for editing the Talos cluster config.

The on-disk ``.config/terraform/components/cluster/talos/app.tfvars`` is the
source of truth and every edit is persisted immediately (auto-save): a PUT
replaces the in-memory working copy, writes it to disk, and broadcasts the
result live over Socket.IO. ``/reload`` re-reads the file to pick up
out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.talos_config import TalosValidationError
from homelab_config.talos_store import TalosStore

logger = logging.getLogger(__name__)

bp = Blueprint("talos_api", __name__, url_prefix="/api/talos")

EVENT_CONFIG = "talos:config"
EVENT_STATUS = "talos:status"


def _store() -> TalosStore:
    return current_app.config["TALOS_STORE"]


def broadcast(store: TalosStore) -> None:
    """Emit the current working config and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: TalosStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/config")
def get_config():
    """Return the working config plus drift/status flags."""
    store = _store()
    return jsonify({"config": store.get(), "status": store.status()})


@bp.put("/config")
def update_config():
    """Replace the config and persist app.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.update(data)
    except TalosValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    logger.info(
        "Updated Talos config (cluster=%s)", record["cluster"].get("cluster_name")
    )
    _persist(store)
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
    logger.info("Reloaded Talos config from disk")
    broadcast(store)
    return jsonify({"config": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
