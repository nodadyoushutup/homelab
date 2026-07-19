"""REST endpoints for editing the NFS share catalog.

The on-disk ``.config/terraform/nfs.tfvars`` is the source of truth and every edit
is persisted immediately (auto-save): add/update/delete mutate the in-memory
working copy, write it to disk, and broadcast the result live over Socket.IO.
``/reload`` re-reads the file to pick up out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.nfs_config import ShareValidationError
from homelab_config.nfs_store import NfsStore, StoreError

logger = logging.getLogger(__name__)

bp = Blueprint("nfs_api", __name__, url_prefix="/api/nfs")

EVENT_SHARES = "nfs:shares"
EVENT_STATUS = "nfs:status"


def _store() -> NfsStore:
    return current_app.config["NFS_STORE"]


def broadcast(store: NfsStore) -> None:
    """Emit the current working shares and status to all clients."""
    socketio.emit(EVENT_SHARES, store.list_shares())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: NfsStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/shares")
def list_shares():
    """Return the working shares plus drift/status flags."""
    store = _store()
    return jsonify({"shares": store.list_shares(), "status": store.status()})


@bp.post("/shares")
def create_share():
    """Add a share and persist nfs.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        share = store.add(data)
    except ShareValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added NFS share %s (%s:%s)", share["name"], share["server"], share["export"])
    _persist(store)
    return jsonify(share), 201


@bp.put("/shares/<name>")
def update_share(name: str):
    """Update a share and persist nfs.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        share = store.update(name, data)
    except ShareValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated NFS share %s", share["name"])
    _persist(store)
    return jsonify(share)


@bp.delete("/shares/<name>")
def delete_share(name: str):
    """Delete a share and persist nfs.tfvars immediately (auto-save)."""
    store = _store()
    try:
        store.delete(name)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted NFS share %s", name)
    _persist(store)
    return jsonify({"deleted": name})


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered nfs.tfvars for the working copy."""
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
    logger.info("Reloaded NFS catalog from disk")
    broadcast(store)
    return jsonify({"shares": store.list_shares(), "status": store.status()})


__all__ = ["bp", "broadcast"]
