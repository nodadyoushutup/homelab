"""REST endpoints for editing the Proxmox cluster config (images + machines).

The on-disk ``.config/terraform/components/cluster/proxmox/app.tfvars`` is the
source of truth and every edit is persisted immediately (auto-save): add/update/
delete mutate the in-memory working copy, write it to disk, and broadcast the
result live over Socket.IO. ``/reload`` re-reads the file to pick up out-of-band
changes.

This section manages images/machines only; the Proxmox provider *credentials*
are a separate section (``/api/proxmox``).
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.proxmox_cluster_config import (
    ImageValidationError,
    MachineValidationError,
)
from homelab_config.proxmox_cluster_store import ProxmoxClusterStore, StoreError

logger = logging.getLogger(__name__)

bp = Blueprint("proxmox_cluster_api", __name__, url_prefix="/api/proxmox-vms")

EVENT_IMAGES = "proxmox_vms:images"
EVENT_MACHINES = "proxmox_vms:machines"
EVENT_STATUS = "proxmox_vms:status"


def _store() -> ProxmoxClusterStore:
    return current_app.config["PROXMOX_CLUSTER_STORE"]


def broadcast(store: ProxmoxClusterStore) -> None:
    """Emit the current working images/machines and status to all clients."""
    socketio.emit(EVENT_IMAGES, store.list_images())
    socketio.emit(EVENT_MACHINES, store.list_machines())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: ProxmoxClusterStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


def _snapshot_response(store: ProxmoxClusterStore):
    snap = store.snapshot()
    return jsonify(
        {
            "images": snap["images"],
            "machines": snap["machines"],
            "status": store.status(),
        }
    )


@bp.get("")
def get_all():
    """Return the working images/machines plus drift/status flags."""
    return _snapshot_response(_store())


# --- images ---------------------------------------------------------------


@bp.post("/images")
def create_image():
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        image = store.add_image(data)
    except ImageValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Proxmox image %s", image["key"])
    _persist(store)
    return jsonify(image), 201


@bp.put("/images/<key>")
def update_image(key: str):
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        image = store.update_image(key, data)
    except ImageValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Proxmox image %s", image["key"])
    _persist(store)
    return jsonify(image)


@bp.delete("/images/<key>")
def delete_image(key: str):
    store = _store()
    try:
        store.delete_image(key)
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Deleted Proxmox image %s", key)
    _persist(store)
    return jsonify({"deleted": key})


# --- machines -------------------------------------------------------------


@bp.post("/machines")
def create_machine():
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        machine = store.add_machine(data)
    except MachineValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Proxmox machine %s", machine["name"])
    _persist(store)
    return jsonify(machine), 201


@bp.put("/machines/<name>")
def update_machine(name: str):
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        machine = store.update_machine(name, data)
    except MachineValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Proxmox machine %s", machine["name"])
    _persist(store)
    return jsonify(machine)


@bp.delete("/machines/<name>")
def delete_machine(name: str):
    store = _store()
    try:
        store.delete_machine(name)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted Proxmox machine %s", name)
    _persist(store)
    return jsonify({"deleted": name})


# --- misc -----------------------------------------------------------------


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
    logger.info("Reloaded Proxmox cluster config from disk")
    broadcast(store)
    return _snapshot_response(store)


__all__ = ["bp", "broadcast", "EVENT_STATUS"]
