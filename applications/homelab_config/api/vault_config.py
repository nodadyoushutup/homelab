"""REST endpoints for editing the Vault KV desired state.

The on-disk ``.config/terraform/components/swarm/vault/config.tfvars`` is the
source of truth and every edit is persisted immediately (auto-save): mount/secret
mutations update the in-memory working copy, write it to disk, and broadcast the
result live over Socket.IO. ``/reload`` re-reads the file to pick up out-of-band
changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.vault_config import SecretValidationError
from homelab_config.vault_store import StoreError, VaultConfigStore

logger = logging.getLogger(__name__)

bp = Blueprint("vault_config_api", __name__, url_prefix="/api/storage/vault")

EVENT_CONFIG = "vault_config:config"
EVENT_STATUS = "vault_config:status"


def _store() -> VaultConfigStore:
    return current_app.config["VAULT_CONFIG_STORE"]


def broadcast(store: VaultConfigStore) -> None:
    """Emit the current working config and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: VaultConfigStore) -> None:
    store.write()
    broadcast(store)


@bp.get("/config")
def get_config():
    """Return the working mount path/secrets plus drift/status flags."""
    store = _store()
    data = store.get()
    data["status"] = store.status()
    return jsonify(data)


@bp.put("/mount")
def set_mount():
    """Set the KV mount path and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    mount_path = store.set_mount_path(data.get("mount_path", ""))
    logger.info("Set Vault mount path")
    _persist(store)
    return jsonify({"mount_path": mount_path})


@bp.post("/secrets")
def create_secret():
    """Add a KV secret and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        secret = store.add(data)
    except SecretValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Vault secret %s", secret["key"])
    _persist(store)
    return jsonify(secret), 201


@bp.put("/secrets/<path:key>")
def update_secret(key: str):
    """Update a KV secret and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        secret = store.update(key, data)
    except SecretValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Vault secret %s", secret["key"])
    _persist(store)
    return jsonify(secret)


@bp.delete("/secrets/<path:key>")
def delete_secret(key: str):
    """Delete a KV secret and persist immediately (auto-save)."""
    store = _store()
    try:
        store.delete(key)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted Vault secret %s", key)
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
    logger.info("Reloaded Vault config from disk")
    broadcast(store)
    data = store.get()
    data["status"] = store.status()
    return jsonify(data)


__all__ = ["bp", "broadcast"]
