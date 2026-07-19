"""REST endpoints for editing the Prometheus scrape configuration.

The on-disk ``.config/terraform/components/swarm/prometheus/prometheus.yaml`` is
the source of truth and every edit is persisted immediately (auto-save):
mutations update the in-memory working copy, write it to disk, and broadcast the
result live over Socket.IO. ``/reload`` re-reads the file for out-of-band edits.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.prometheus_config import ConfigValidationError
from homelab_config.prometheus_store import PrometheusConfigStore, StoreError

logger = logging.getLogger(__name__)

bp = Blueprint("prometheus_config_api", __name__, url_prefix="/api/monitoring/prometheus")

EVENT_CONFIG = "prometheus_config:config"
EVENT_STATUS = "prometheus_config:status"


def _store() -> PrometheusConfigStore:
    return current_app.config["PROMETHEUS_CONFIG_STORE"]


def broadcast(store: PrometheusConfigStore) -> None:
    """Emit the current working config and status to all clients."""
    socketio.emit(EVENT_CONFIG, store.get())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: PrometheusConfigStore) -> None:
    store.write()
    broadcast(store)


@bp.get("/config")
def get_config():
    """Return the working config plus drift/status flags."""
    store = _store()
    return jsonify({"config": store.get(), "status": store.status()})


@bp.put("/global")
def set_global():
    """Replace the global settings (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.set_global(data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    _persist(store)
    return jsonify(record)


@bp.put("/remote_write")
def set_remote_write():
    """Replace the remote_write endpoints (auto-save). Body: {urls: [...]}."""
    store = _store()
    data = request.get_json(silent=True) or {}
    entries = data.get("urls", data.get("remote_write", []))
    try:
        records = store.set_remote_write(entries)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    _persist(store)
    return jsonify(records)


@bp.post("/jobs")
def create_job():
    """Add a scrape job and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        job = store.add_job(data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Prometheus scrape job %s", job.get("job_name"))
    _persist(store)
    return jsonify(job), 201


@bp.put("/jobs/<key>")
def update_job(key: str):
    """Update a scrape job and persist immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        job = store.update_job(key, data)
    except ConfigValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Prometheus scrape job %s", key)
    _persist(store)
    return jsonify(job)


@bp.delete("/jobs/<key>")
def delete_job(key: str):
    """Delete a scrape job and persist immediately (auto-save)."""
    store = _store()
    try:
        store.delete_job(key)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted Prometheus scrape job %s", key)
    _persist(store)
    return jsonify({"deleted": key})


@bp.get("/yaml")
def preview_yaml():
    """Return the rendered prometheus.yaml for the working copy."""
    return jsonify({"yaml": _store().render()})


@bp.get("/status")
def status():
    """Return drift/status flags."""
    return jsonify(_store().status())


@bp.post("/reload")
def reload_config():
    """Reload the working copy from disk to pick up out-of-band changes."""
    store = _store()
    store.reload()
    logger.info("Reloaded Prometheus config from disk")
    broadcast(store)
    return jsonify({"config": store.get(), "status": store.status()})


__all__ = ["bp", "broadcast"]
