"""Spec-driven REST endpoints for editing shared provider credentials.

:func:`make_blueprint` builds one Flask blueprint per :class:`ProviderSpec`
mounted at ``/api/<key>``, mirroring ``api/proxmox.py``: the on-disk
``providers/<app>.tfvars`` is the source of truth and every PUT auto-saves and
broadcasts the result over Socket.IO. Stores are looked up from
``current_app.config["PROVIDER_STORES"][key]`` so the drift watcher and blueprint
share the same instances.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.provider_config_generic import ProviderValidationError
from homelab_config.provider_specs import ProviderSpec
from homelab_config.provider_store_generic import GenericProviderStore

logger = logging.getLogger(__name__)


def _store(spec: ProviderSpec) -> GenericProviderStore:
    return current_app.config["PROVIDER_STORES"][spec.key]


def broadcast(spec: ProviderSpec, store: GenericProviderStore) -> None:
    """Emit the current working credentials and status to all clients."""
    socketio.emit(spec.credentials_event, store.get())
    socketio.emit(spec.status_event, store.status())


def make_blueprint(spec: ProviderSpec) -> Blueprint:
    """Build the REST blueprint for one provider spec."""
    bp = Blueprint(f"{spec.key}_api", __name__, url_prefix=f"/api/{spec.key}")

    def _persist(store: GenericProviderStore) -> None:
        store.write()
        broadcast(spec, store)

    @bp.get("/credentials")
    def get_credentials():  # noqa: ANN202 - Flask view
        store = _store(spec)
        return jsonify({"credentials": store.get(), "status": store.status()})

    @bp.put("/credentials")
    def update_credentials():  # noqa: ANN202 - Flask view
        store = _store(spec)
        data = request.get_json(silent=True) or {}
        try:
            record = store.update(data)
        except ProviderValidationError as exc:
            return jsonify({"error": str(exc)}), 400
        logger.info("Updated %s credentials", spec.key)
        _persist(store)
        return jsonify(record)

    @bp.get("/tfvars")
    def preview_tfvars():  # noqa: ANN202 - Flask view
        return jsonify({"tfvars": _store(spec).render()})

    @bp.get("/status")
    def status():  # noqa: ANN202 - Flask view
        return jsonify(_store(spec).status())

    @bp.post("/reload")
    def reload_config():  # noqa: ANN202 - Flask view
        store = _store(spec)
        store.reload()
        logger.info("Reloaded %s credentials from disk", spec.key)
        broadcast(spec, store)
        return jsonify({"credentials": store.get(), "status": store.status()})

    return bp


__all__ = ["broadcast", "make_blueprint"]
