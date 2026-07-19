"""REST endpoints for editing the non-swarm *extra hosts* catalog.

An extra host is a machine that runs Docker but is not part of the Swarm (e.g. an
amd64 build host). It is persisted to ``.config/docker/extra_hosts.yaml`` and the
Docker provider catalog derives a provider entry for it exactly like a swarm node
(see ``DockerProvidersStore``). This blueprint owns only the *editing* surface for
those hosts plus a per-host **apply** that pushes/syncs SSH (key set +
authorized_keys) to the machine - it never touches Docker or the swarm.

The underlying state lives in the shared ``DOCKER_STORE`` (extra hosts feed
``docker.tfvars``), so every edit persists via that store and re-broadcasts the
Docker catalog snapshot so the Docker page stays in sync.
"""

from __future__ import annotations

import logging
import threading

from flask import Blueprint, current_app, jsonify, request

from homelab_config import swarm_reconcile, swarm_ssh
from homelab_config.api.docker import broadcast
from homelab_config.docker_providers_store import DockerProvidersStore, StoreError
from homelab_config.extensions import socketio
from homelab_config.extra_hosts_config import ExtraHostValidationError
from homelab_config.swarm_ssh import SSHError

logger = logging.getLogger(__name__)

bp = Blueprint("extra_hosts_api", __name__, url_prefix="/api/extra-hosts")

EVENT_APPLY_LOG = "extra_hosts:apply:log"
EVENT_APPLY_DONE = "extra_hosts:apply:done"

# Serialize extra-host SSH applies: one at a time across all clients.
_apply_lock = threading.Lock()
_apply_running = False


def _store() -> DockerProvidersStore:
    return current_app.config["DOCKER_STORE"]


def _persist(store: DockerProvidersStore) -> None:
    """Write the working copy to disk and broadcast the Docker snapshot (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("")
def get_hosts():
    """Return the editable extra hosts plus status."""
    store = _store()
    snap = store.snapshot()
    return jsonify({"extra_hosts": snap["extra_hosts"], "status": store.status()})


@bp.post("")
def create_host():
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        host = store.add_host(data)
    except ExtraHostValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added Docker extra host %s (%s)", host["name"], host["host"])
    _persist(store)
    return jsonify(host), 201


@bp.put("/<name>")
def update_host(name: str):
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        host = store.update_host(name, data)
    except ExtraHostValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated Docker extra host %s", host["name"])
    _persist(store)
    return jsonify(host)


@bp.delete("/<name>")
def delete_host(name: str):
    store = _store()
    try:
        store.delete_host(name)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted Docker extra host %s", name)
    _persist(store)
    return jsonify({"deleted": name})


@bp.post("/reload")
def reload_config():
    """Reload the editable working copies from disk and re-broadcast."""
    store = _store()
    store.reload()
    logger.info("Reloaded Docker catalog from disk (extra hosts)")
    broadcast(store)
    snap = store.snapshot()
    return jsonify({"extra_hosts": snap["extra_hosts"], "status": store.status()})


# -- per-host SSH apply -------------------------------------------------------


def _make_reporter(host_name: str):
    """Return a reporter that streams apply output to all clients."""

    def report(level: str, message: str) -> None:
        socketio.emit(
            EVENT_APPLY_LOG, {"host": host_name, "level": level, "message": message}
        )
        socketio.sleep(0)

    return report


def _release_lock() -> None:
    global _apply_running
    with _apply_lock:
        _apply_running = False


def _apply_host_task(host: dict) -> None:
    """Background: push/sync the SSH key set + authorized_keys to one host.

    This is the non-swarm equivalent of ``swarm_reconcile``'s ``sync_ssh`` action:
    it connects (key first, password fallback) and pushes the key set files into
    the host's ``~/.ssh``. It never touches Docker/swarm.
    """
    report = _make_reporter(host["name"])
    ok = False
    try:
        report("step", f"{host['name']}: connecting ({host['ssh_user']}@{host['host']})")
        files = swarm_reconcile.ssh_sync_files(host)
        if not files:
            report(
                "warn",
                f"{host['name']}: nothing to sync - key set "
                f"'{host.get('ssh_key') or '(none)'}' is empty or missing",
            )
            ok = True
            return
        client = swarm_ssh.connect(host)
        try:
            remote_home_ssh = f"/home/{host['ssh_user']}/.ssh"
            report("step", f"{host['name']}: pushing SSH to {remote_home_ssh}")
            pushed = swarm_ssh.put_files(client, files, remote_home_ssh)
            report("ok", f"{host['name']}: pushed {', '.join(pushed)} to {remote_home_ssh}")
        finally:
            client.close()
        ok = True
    except SSHError as exc:
        report("error", f"{host['name']}: {exc}")
    except Exception as exc:  # noqa: BLE001 - surface any failure to the UI
        logger.exception("extra-host apply failed")
        report("error", f"{host['name']}: apply failed: {exc}")
    finally:
        socketio.emit(EVENT_APPLY_DONE, {"host": host["name"], "ok": ok})
        _release_lock()


@bp.post("/<name>/apply")
def apply_host(name: str):
    """Push/sync SSH to one extra host (no swarm actions); streams over Socket.IO."""
    global _apply_running
    store = _store()
    host = store.get_host(name)
    if host is None:
        return jsonify({"error": f"host '{name}' not found"}), 404
    with _apply_lock:
        if _apply_running:
            return jsonify({"error": "an apply is already running"}), 409
        _apply_running = True
    socketio.start_background_task(_apply_host_task, host)
    return jsonify({"started": True, "host": name}), 202


__all__ = ["bp"]
