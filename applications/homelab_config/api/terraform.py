"""REST endpoints for the Terraform state backend settings.

The on-disk ``.config/terraform/state.tfvars`` is the source of truth and every
edit is persisted immediately (auto-save): a PUT replaces the in-memory working
copy, writes it to disk, re-renders the derived S3 backend file when configured,
and broadcasts the result live over Socket.IO. ``/reload`` re-reads the file to
pick up out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.terraform_config import SettingsValidationError
from homelab_config.terraform_store import TerraformStore

logger = logging.getLogger(__name__)

bp = Blueprint("terraform_api", __name__, url_prefix="/api/terraform")

EVENT_SETTINGS = "terraform:settings"
EVENT_STATUS = "terraform:status"


def _store() -> TerraformStore:
    return current_app.config["TERRAFORM_STORE"]


def _payload(store: TerraformStore) -> dict:
    """The settings snapshot broadcast to clients (settings + MinIO options)."""
    return {"settings": store.get(), "minios": store.available_minios()}


def broadcast(store: TerraformStore) -> None:
    """Emit the current working settings and status to all clients."""
    socketio.emit(EVENT_SETTINGS, _payload(store))
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: TerraformStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/settings")
def get_settings():
    """Return the working settings, selectable MinIOs, and drift/status flags."""
    store = _store()
    return jsonify(
        {
            "settings": store.get(),
            "minios": store.available_minios(),
            "status": store.status(),
        }
    )


@bp.put("/settings")
def update_settings():
    """Replace settings and persist state.tfvars + backend immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.update(data)
    except SettingsValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    logger.info(
        "Updated Terraform state settings (backend=%s minio=%s)",
        record["backend"],
        record["minio"],
    )
    _persist(store)
    return jsonify(record)


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered state.tfvars for the working copy."""
    return jsonify({"tfvars": _store().render_state()})


@bp.get("/backend")
def preview_backend():
    """Return the rendered minio.backend.hcl for the working copy."""
    return jsonify({"backend": _store().render_backend()})


@bp.get("/status")
def status():
    """Return drift/status flags."""
    return jsonify(_store().status())


@bp.post("/reload")
def reload_config():
    """Reload the working copy from disk to pick up out-of-band changes."""
    store = _store()
    store.reload()
    logger.info("Reloaded Terraform state settings from disk")
    broadcast(store)
    return jsonify(
        {
            "settings": store.get(),
            "minios": store.available_minios(),
            "status": store.status(),
        }
    )


__all__ = ["bp", "broadcast"]
