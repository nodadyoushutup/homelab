"""REST endpoints for the CICD Jenkins section (controller + 2 agent slices).

Each slice's app.tfvars is the source of truth and edits auto-save: a PUT
replaces the in-memory working copy for that slice, writes it to disk, and
broadcasts the result live over Socket.IO. Events are namespaced per slice as
``jenkins:<slice>:config`` / ``jenkins:<slice>:status``.
"""

from __future__ import annotations

import logging

from flask import Blueprint, current_app, jsonify, request

from homelab_config.extensions import socketio
from homelab_config.jenkins_config import SLICES, SLICES_BY_KEY, JenkinsValidationError
from homelab_config.jenkins_store import JenkinsStore

logger = logging.getLogger(__name__)

# NOTE: the generic Jenkins *provider* credentials blueprint already owns
# ``/api/jenkins`` and the name ``jenkins_api`` - this deploy section must use a
# distinct name + prefix.
bp = Blueprint("jenkins_deploy_api", __name__, url_prefix="/api/cicd/jenkins")


def config_event(key: str) -> str:
    return f"jenkins:{key}:config"


def status_event(key: str) -> str:
    return f"jenkins:{key}:status"


def _store() -> JenkinsStore:
    return current_app.config["JENKINS_STORE"]


def broadcast(store: JenkinsStore, key: str) -> None:
    """Emit the working config + status for one slice."""
    socketio.emit(config_event(key), store.get(key))
    socketio.emit(status_event(key), store.status(key))


def _valid(key: str) -> bool:
    return key in SLICES_BY_KEY


@bp.get("/slices")
def list_slices():
    """Return slice metadata so the UI can build its tabs."""
    return jsonify(
        {
            "slices": [
                {"key": s.key, "title": s.title, "kind": s.kind}
                for s in SLICES
            ]
        }
    )


@bp.get("/<key>/config")
def get_config(key: str):
    if not _valid(key):
        return jsonify({"error": f"unknown slice {key!r}"}), 404
    store = _store()
    return jsonify({"config": store.get(key), "status": store.status(key)})


@bp.put("/<key>/config")
def update_config(key: str):
    if not _valid(key):
        return jsonify({"error": f"unknown slice {key!r}"}), 404
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        record = store.update(key, data)
    except JenkinsValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    store.write(key)
    logger.info("Updated Jenkins %s config", key)
    broadcast(store, key)
    return jsonify(record)


@bp.get("/<key>/tfvars")
def preview_tfvars(key: str):
    if not _valid(key):
        return jsonify({"error": f"unknown slice {key!r}"}), 404
    return jsonify({"tfvars": _store().render(key)})


@bp.get("/<key>/status")
def status(key: str):
    if not _valid(key):
        return jsonify({"error": f"unknown slice {key!r}"}), 404
    return jsonify(_store().status(key))


@bp.post("/<key>/reload")
def reload_config(key: str):
    if not _valid(key):
        return jsonify({"error": f"unknown slice {key!r}"}), 404
    store = _store()
    store.reload(key)
    logger.info("Reloaded Jenkins %s config from disk", key)
    broadcast(store, key)
    return jsonify({"config": store.get(key), "status": store.status(key)})


__all__ = ["bp", "broadcast", "config_event", "status_event"]
