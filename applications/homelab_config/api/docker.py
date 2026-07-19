"""REST endpoints for editing the Docker provider catalog.

Swarm-node providers are derived from the Swarm topology and shown read-only.
Non-swarm *extra hosts* are also derived into the catalog but edited on their own
page (see ``api.extra_hosts``). The editable state here is the *registry_auths*
(persisted to ``.config/terraform/providers/docker.tfvars``). Every edit is
persisted immediately (auto-save) and broadcast over Socket.IO. ``/reload``
re-reads disk.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.docker_providers_config import DockerConfigError
from homelab_config.docker_providers_store import DockerProvidersStore, StoreError
from homelab_config.extensions import socketio

logger = logging.getLogger(__name__)

bp = Blueprint("docker_api", __name__, url_prefix="/api/docker")

EVENT_PROVIDERS = "docker:providers"
EVENT_STATUS = "docker:status"


def _store() -> DockerProvidersStore:
    return current_app.config["DOCKER_STORE"]


def broadcast(store: DockerProvidersStore) -> None:
    """Emit the current catalog snapshot and status to all clients."""
    socketio.emit(EVENT_PROVIDERS, store.snapshot())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: DockerProvidersStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/providers")
def get_providers():
    """Return derived providers + editable extras/registry plus status."""
    store = _store()
    return jsonify({**store.snapshot(), "status": store.status()})


# -- registry auths -----------------------------------------------------------


@bp.post("/registry")
def create_registry():
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        auth = store.add_registry(data)
    except DockerConfigError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added registry auth %s", auth["address"])
    _persist(store)
    return jsonify(auth), 201


@bp.put("/registry/<path:address>")
def update_registry(address: str):
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        auth = store.update_registry(address, data)
    except DockerConfigError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated registry auth %s", auth["address"])
    _persist(store)
    return jsonify(auth)


@bp.delete("/registry/<path:address>")
def delete_registry(address: str):
    store = _store()
    try:
        store.delete_registry(address)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted registry auth %s", address)
    _persist(store)
    return jsonify({"deleted": address})


# -- file preview / reload ----------------------------------------------------


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered docker.tfvars for the working copy."""
    return jsonify({"tfvars": _store().render()})


@bp.get("/status")
def status():
    """Return drift/status flags."""
    return jsonify(_store().status())


@bp.post("/reload")
def reload_config():
    """Reload the editable working copies from disk (extra hosts + registry)."""
    store = _store()
    store.reload()
    logger.info("Reloaded Docker catalog from disk")
    broadcast(store)
    return jsonify({**store.snapshot(), "status": store.status()})


__all__ = ["bp", "broadcast"]
