"""REST endpoints for editing the Nginx Proxy Manager desired-state config.

The on-disk ``.config/terraform/components/swarm/nginx_proxy_manager/config.tfvars``
is the source of truth and every edit is persisted immediately (auto-save):
default/collection mutations update the in-memory working copy, write it to disk,
and broadcast the result live over Socket.IO. ``/reload`` re-reads the file to
pick up out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.npm_config import COLLECTIONS, ConfigValidationError
from homelab_config.npm_store import NpmConfigStore, StoreError

logger = logging.getLogger(__name__)

bp = Blueprint("npm_api", __name__, url_prefix="/api/network/npm")

EVENT_CONFIG = "npm_config:config"
EVENT_STATUS = "npm_config:status"


def _store() -> NpmConfigStore:
    return current_app.config["NPM_CONFIG_STORE"]


def broadcast(store: NpmConfigStore) -> None:
    """Emit the current working config and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: NpmConfigStore) -> None:
    store.write()
    broadcast(store)


def _valid_collection(collection: str) -> bool:
    return collection in COLLECTIONS


@bp.get("/config")
def get_config():
    """Return the working config plus drift/status flags."""
    store = _store()
    return jsonify({"config": store.get(), "status": store.status()})


@bp.put("/default")
def set_default():
    """Replace the default cert/DNS-challenge settings (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.set_default(data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    logger.info("Updated NPM default settings")
    _persist(store)
    return jsonify(record)


@bp.post("/<collection>")
def create_entry(collection: str):
    """Add an entry to a collection and persist immediately (auto-save)."""
    if not _valid_collection(collection):
        return jsonify({"error": f"unknown collection '{collection}'"}), 404
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        entry = store.add(collection, data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added NPM %s entry", collection)
    _persist(store)
    return jsonify(entry), 201


@bp.put("/<collection>/<key>")
def update_entry(collection: str, key: str):
    """Update a collection entry and persist immediately (auto-save)."""
    if not _valid_collection(collection):
        return jsonify({"error": f"unknown collection '{collection}'"}), 404
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        entry = store.update(collection, key, data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated NPM %s entry %s", collection, key)
    _persist(store)
    return jsonify(entry)


@bp.delete("/<collection>/<key>")
def delete_entry(collection: str, key: str):
    """Delete a collection entry and persist immediately (auto-save)."""
    if not _valid_collection(collection):
        return jsonify({"error": f"unknown collection '{collection}'"}), 404
    store = _store()
    try:
        store.delete(collection, key)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted NPM %s entry %s", collection, key)
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
    logger.info("Reloaded NPM config from disk")
    broadcast(store)
    return jsonify({"config": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
