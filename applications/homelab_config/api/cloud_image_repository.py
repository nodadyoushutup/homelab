"""REST endpoints for editing the Cloud Image Repository Swarm app config.

The on-disk
``.config/terraform/components/swarm/cloud-image-repository/app.tfvars`` is the
source of truth and every edit is persisted immediately (auto-save): a PUT
replaces the in-memory working copy, writes it to disk, and broadcasts the
result live over Socket.IO. ``/reload`` re-reads the file to pick up out-of-band
changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.cloud_image_repository_config import (
    CloudImageRepositoryValidationError,
)
from homelab_config.cloud_image_repository_store import CloudImageRepositoryStore
from homelab_config.extensions import socketio

logger = logging.getLogger(__name__)

bp = Blueprint(
    "cloud_image_repository_api",
    __name__,
    url_prefix="/api/cloud-image-repository",
)

EVENT_CONFIG = "cloud_image_repository:config"
EVENT_STATUS = "cloud_image_repository:status"


def _store() -> CloudImageRepositoryStore:
    return current_app.config["CLOUD_IMAGE_REPOSITORY_STORE"]


def broadcast(store: CloudImageRepositoryStore) -> None:
    """Emit the current working config and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: CloudImageRepositoryStore) -> None:
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
    except CloudImageRepositoryValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    logger.info(
        "Updated Cloud Image Repository config (docker_machine=%s, nfs_share=%s)",
        record.get("docker_machine"),
        record.get("nfs_share"),
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
    logger.info("Reloaded Cloud Image Repository config from disk")
    broadcast(store)
    return jsonify({"config": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
