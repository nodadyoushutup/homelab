"""REST endpoints for managing SSH key sets under ``.config/.ssh``.

Each set is a subdirectory (an independent key pair). Operations write straight
to disk (the files are the source of truth); every mutation re-broadcasts the
full snapshot over Socket.IO so other browser tabs stay in sync.
"""

from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request

from homelab_config.extensions import socketio
from homelab_config import ssh_store
from homelab_config.ssh_store import SSHError

logger = logging.getLogger(__name__)

bp = Blueprint("ssh_api", __name__, url_prefix="/api/ssh")

EVENT_SETS = "ssh:sets"


def broadcast() -> None:
    """Push the current snapshot (sets + shared + host) to all clients."""
    socketio.emit(EVENT_SETS, ssh_store.snapshot())


def _error(exc: SSHError):
    message = str(exc)
    if "not found" in message:
        return jsonify({"error": message}), 404
    if "already exists" in message:
        return jsonify({"error": message}), 409
    return jsonify({"error": message}), 400


@bp.get("/sets")
def list_sets():
    """Return all key sets, shared root files, and syncable host files."""
    return jsonify(ssh_store.snapshot())


@bp.post("/sets")
def create_set():
    """Create a new (empty) key set."""
    data = request.get_json(silent=True) or {}
    try:
        info = ssh_store.create_set(data.get("name", ""))
    except SSHError as exc:
        return _error(exc)
    broadcast()
    return jsonify(info), 201


@bp.delete("/sets/<set_name>")
def delete_set(set_name: str):
    """Delete a key set and all of its files."""
    try:
        ssh_store.delete_set(set_name)
    except SSHError as exc:
        return _error(exc)
    broadcast()
    return jsonify({"deleted": set_name})


@bp.post("/sets/<set_name>/sync")
def sync_from_host(set_name: str):
    """Copy the host ~/.ssh key pair into this set."""
    try:
        copied = ssh_store.sync_from_host(set_name)
    except SSHError as exc:
        return _error(exc)
    broadcast()
    return jsonify({"copied": copied})


@bp.post("/sets/<set_name>/upload")
def upload_key(set_name: str):
    """Upload a private or public key into a set (multipart form).

    Form fields: ``file`` (the uploaded key), ``kind`` (``private``/``public``),
    optional ``name`` overriding the target filename.
    """
    kind = (request.form.get("kind") or "").strip()
    upload = request.files.get("file")
    if upload is None or not upload.filename:
        return jsonify({"error": "no file was uploaded"}), 400
    name = (request.form.get("name") or "").strip() or upload.filename
    try:
        info = ssh_store.save_key(set_name, kind, name, upload.read())
    except SSHError as exc:
        return _error(exc)
    broadcast()
    return jsonify(info), 201


@bp.put("/sets/<set_name>/authorized_keys")
def save_authorized_keys(set_name: str):
    """Write the ``authorized_keys`` file for a set (JSON: ``content``)."""
    data = request.get_json(silent=True) or {}
    try:
        info = ssh_store.save_authorized_keys(set_name, data.get("content", ""))
    except SSHError as exc:
        return _error(exc)
    broadcast()
    return jsonify(info), 201


@bp.get("/sets/<set_name>/files/<name>")
def read_file(set_name: str, name: str):
    """Return the text of a non-sensitive file within a set."""
    try:
        return jsonify(
            {"name": name, "content": ssh_store.read_public(set_name, name)}
        )
    except SSHError as exc:
        return _error(exc)


@bp.delete("/sets/<set_name>/files/<name>")
def delete_file(set_name: str, name: str):
    """Delete a single file from a set."""
    try:
        ssh_store.delete_file(set_name, name)
    except SSHError as exc:
        return _error(exc)
    broadcast()
    return jsonify({"deleted": name})


__all__ = ["bp", "broadcast"]
