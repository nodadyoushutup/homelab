"""REST endpoints for editing the Proxmox provider credentials.

The on-disk ``.config/terraform/providers/proxmox.tfvars`` is the source of truth and every
edit is persisted immediately (auto-save): a PUT replaces the in-memory working
copy, writes it to disk, and broadcasts the result live over Socket.IO.
``/reload`` re-reads the file to pick up out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.proxmox_config import CredentialsValidationError
from homelab_config.proxmox_store import ProxmoxStore

logger = logging.getLogger(__name__)

bp = Blueprint("proxmox_api", __name__, url_prefix="/api/proxmox")

EVENT_CREDENTIALS = "proxmox:credentials"
EVENT_STATUS = "proxmox:status"


def _store() -> ProxmoxStore:
    return current_app.config["PROXMOX_STORE"]


def broadcast(store: ProxmoxStore) -> None:
    """Emit the current working credentials and status to all clients."""
    socketio.emit(EVENT_CREDENTIALS, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: ProxmoxStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/credentials")
def get_credentials():
    """Return the working credentials plus drift/status flags."""
    store = _store()
    return jsonify({"credentials": store.get(), "status": store.status()})


@bp.put("/credentials")
def update_credentials():
    """Replace the credentials and persist proxmox.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.update(data)
    except CredentialsValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    logger.info("Updated Proxmox credentials (endpoint=%s)", record["endpoint"])
    _persist(store)
    return jsonify(record)


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered proxmox.tfvars for the working copy."""
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
    logger.info("Reloaded Proxmox credentials from disk")
    broadcast(store)
    return jsonify({"credentials": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
