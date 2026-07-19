"""REST endpoints for editing the MinIO instance catalog.

The on-disk ``.config/terraform/minio.tfvars`` is the source of truth and every
edit is persisted immediately (auto-save): a mutation updates the in-memory
working copy, writes it to disk, and broadcasts the result live over Socket.IO.
``/reload`` re-reads the file to pick up out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.minio_config import InstanceValidationError
from homelab_config.minio_store import MinioStore, StoreError

logger = logging.getLogger(__name__)

bp = Blueprint("minio_api", __name__, url_prefix="/api/minio")

EVENT_INSTANCES = "minio:instances"
EVENT_STATUS = "minio:status"


def _store() -> MinioStore:
    return current_app.config["MINIO_STORE"]


def broadcast(store: MinioStore) -> None:
    """Emit the current working instances and status to all clients."""
    socketio.emit(EVENT_INSTANCES, store.list_instances())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: MinioStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/instances")
def list_instances():
    """Return the working instances plus drift/status flags."""
    store = _store()
    return jsonify({"instances": store.list_instances(), "status": store.status()})


@bp.post("/instances")
def create_instance():
    """Add a MinIO instance and persist minio.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        inst = store.add(data)
    except InstanceValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    _persist(store)
    return jsonify(inst), 201


@bp.put("/instances/<name>")
def update_instance(name: str):
    """Update a MinIO instance and persist minio.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        inst = store.update(name, data)
    except InstanceValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    _persist(store)
    return jsonify(inst)


@bp.delete("/instances/<name>")
def delete_instance(name: str):
    """Delete a MinIO instance and persist minio.tfvars immediately (auto-save)."""
    store = _store()
    try:
        store.delete(name)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    _persist(store)
    return jsonify({"deleted": name})


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered minio.tfvars for the working copy."""
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
    broadcast(store)
    return jsonify({"instances": store.list_instances(), "status": store.status()})


__all__ = ["bp", "broadcast"]
