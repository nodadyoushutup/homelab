"""REST endpoints for editing the Packer build defaults.

The on-disk ``.config/packer/build.pkrvars.hcl`` is the source of truth and
every edit is persisted immediately (auto-save): the PUT replaces the in-memory
working copy, writes it to disk, and broadcasts the result live over Socket.IO.
``/reload`` re-reads the file for out-of-band edits.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.packer_config import ConfigValidationError
from homelab_config.packer_store import PackerConfigStore

logger = logging.getLogger(__name__)

bp = Blueprint("packer_api", __name__, url_prefix="/api/packer")

EVENT_CONFIG = "packer:config"
EVENT_STATUS = "packer:status"


def _store() -> PackerConfigStore:
    return current_app.config["PACKER_STORE"]


def broadcast(store: PackerConfigStore) -> None:
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
    logger.info("Updated Packer build defaults")
    store.write()
    broadcast(store)
    return jsonify(record)


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered build.pkrvars.hcl for the working copy."""
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
    logger.info("Reloaded Packer config from disk")
    broadcast(store)
    return jsonify({"config": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
