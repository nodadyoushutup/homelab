"""REST endpoints for editing the Cloudflare DNS desired state.

The on-disk ``.config/terraform/components/remote/cloudflare/config.tfvars`` is
the source of truth and every edit is persisted immediately (auto-save):
zone/record mutations update the in-memory working copy, write it to disk, and
broadcast the result live over Socket.IO. ``/reload`` re-reads the file to pick
up out-of-band changes.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.cloudflare_dns_config import RecordValidationError
from homelab_config.cloudflare_dns_store import CloudflareDnsStore, StoreError
from homelab_config.extensions import socketio

logger = logging.getLogger(__name__)

bp = Blueprint("cloudflare_dns_api", __name__, url_prefix="/api/remote/cloudflare")

EVENT_CONFIG = "cloudflare_dns:config"
EVENT_STATUS = "cloudflare_dns:status"


def _store() -> CloudflareDnsStore:
    return current_app.config["CLOUDFLARE_DNS_STORE"]


def broadcast(store: CloudflareDnsStore) -> None:
    """Emit the current working config and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: CloudflareDnsStore) -> None:
    store.write()
    broadcast(store)


@bp.get("/config")
def get_config():
    """Return the working zone/records plus drift/status flags."""
    store = _store()
    data = store.get()
    data["status"] = store.status()
    return jsonify(data)


@bp.put("/zone")
def set_zone():
    """Set the Cloudflare zone id and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    zone_id = store.set_zone_id(data.get("zone_id", ""))
    logger.info("Set Cloudflare zone id")
    _persist(store)
    return jsonify({"zone_id": zone_id})


@bp.post("/records")
def create_record():
    """Add a DNS record and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.add(data)
    except RecordValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Cloudflare record %s (%s)", record["key"], record["name"])
    _persist(store)
    return jsonify(record), 201


@bp.put("/records/<key>")
def update_record(key: str):
    """Update a DNS record and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.update(key, data)
    except RecordValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Cloudflare record %s", record["key"])
    _persist(store)
    return jsonify(record)


@bp.delete("/records/<key>")
def delete_record(key: str):
    """Delete a DNS record and persist immediately (auto-save)."""
    store = _store()
    try:
        store.delete(key)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted Cloudflare record %s", key)
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
    logger.info("Reloaded Cloudflare DNS config from disk")
    broadcast(store)
    data = store.get()
    data["status"] = store.status()
    return jsonify(data)


__all__ = ["bp", "broadcast"]
