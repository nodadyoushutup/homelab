"""REST endpoints for editing the Docker Swarm topology.

The on-disk ``.config/docker/swarm.tfvars`` is the source of truth and every edit
is persisted immediately (auto-save): add/update/delete mutate the in-memory
working copy, write it to disk, and broadcast the result live over Socket.IO.
``/reload`` re-reads the file to pick up out-of-band changes.
"""

from __future__ import annotations

import logging
import threading

from flask import Blueprint, current_app, jsonify, request

from homelab_config import swarm_reconcile
from homelab_config.extensions import socketio
from homelab_config.store import StoreError, SwarmStore
from homelab_config.swarm_config import NodeValidationError

logger = logging.getLogger(__name__)

bp = Blueprint("swarm_api", __name__, url_prefix="/api/swarm")

EVENT_NODES = "swarm:nodes"
EVENT_STATUS = "swarm:status"
EVENT_APPLY_LOG = "swarm:apply:log"
EVENT_APPLY_PLAN = "swarm:apply:plan"
EVENT_APPLY_DONE = "swarm:apply:done"

# Serialize reconcile runs: only one plan/apply at a time across all clients.
_apply_lock = threading.Lock()
_apply_running = False


def _store() -> SwarmStore:
    return current_app.config["SWARM_STORE"]


def broadcast(store: SwarmStore) -> None:
    """Emit the current working nodes and status to all clients."""
    socketio.emit(EVENT_NODES, store.list_nodes())
    socketio.emit(EVENT_STATUS, store.status())


def _persist(store: SwarmStore) -> None:
    """Write the working copy to disk and broadcast (auto-save)."""
    store.write()
    broadcast(store)


@bp.get("/nodes")
def list_nodes():
    """Return the working nodes plus drift/status flags."""
    store = _store()
    return jsonify({"nodes": store.list_nodes(), "status": store.status()})


@bp.post("/nodes")
def create_node():
    """Add a node and persist swarm.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        node = store.add(data)
    except NodeValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 409
    logger.info("Added swarm node %s (%s)", node["name"], node["role"])
    _persist(store)
    return jsonify(node), 201


@bp.put("/nodes/<name>")
def update_node(name: str):
    """Update a node and persist swarm.tfvars immediately (auto-save)."""
    store = _store()
    data = request.get_json(silent=True) or {}
    try:
        node = store.update(name, data)
    except NodeValidationError as exc:
        return jsonify({"error": str(exc)}), 400
    except StoreError as exc:
        status = 404 if "not found" in str(exc) else 409
        return jsonify({"error": str(exc)}), status
    logger.info("Updated swarm node %s (%s)", node["name"], node["role"])
    _persist(store)
    return jsonify(node)


@bp.delete("/nodes/<name>")
def delete_node(name: str):
    """Delete a node and persist swarm.tfvars immediately (auto-save)."""
    store = _store()
    try:
        store.delete(name)
    except StoreError as exc:
        return jsonify({"error": str(exc)}), 404
    logger.info("Deleted swarm node %s", name)
    _persist(store)
    return jsonify({"deleted": name})


@bp.get("/tfvars")
def preview_tfvars():
    """Return the rendered swarm.tfvars for the working copy."""
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
    logger.info("Reloaded swarm topology from disk")
    broadcast(store)
    return jsonify({"nodes": store.list_nodes(), "status": store.status()})


# --- reconcile (plan / apply) ------------------------------------------------


def _make_reporter(phase: str):
    """Return a reporter that streams reconcile output to all clients."""

    def report(level: str, message: str) -> None:
        socketio.emit(
            EVENT_APPLY_LOG, {"phase": phase, "level": level, "message": message}
        )
        socketio.sleep(0)

    return report


def _release_lock() -> None:
    global _apply_running
    with _apply_lock:
        _apply_running = False


def _plan_task(nodes: list[dict]) -> None:
    """Background: gather state + build a plan and stream it (no changes)."""
    report = _make_reporter("plan")
    try:
        state = swarm_reconcile.gather_state(nodes, report)
        plan = swarm_reconcile.build_plan(nodes, state)
        socketio.emit(EVENT_APPLY_PLAN, {"phase": "plan", **plan})
        ok = not plan["errors"]
        report(
            "ok" if ok else "error",
            "Plan ready."
            if plan["actions"]
            else ("Nothing to do - swarm matches the config." if ok else "Plan blocked."),
        )
        socketio.emit(EVENT_APPLY_DONE, {"phase": "plan", "ok": ok})
    except Exception as exc:  # noqa: BLE001 - surface any failure to the UI
        logger.exception("swarm plan failed")
        report("error", f"Plan failed: {exc}")
        socketio.emit(EVENT_APPLY_DONE, {"phase": "plan", "ok": False, "error": str(exc)})
    finally:
        _release_lock()


def _apply_task(nodes: list[dict], confirm_destructive: bool) -> None:
    """Background: re-plan then apply, streaming progress. Re-checks destructive."""
    report = _make_reporter("apply")
    try:
        state = swarm_reconcile.gather_state(nodes, report)
        plan = swarm_reconcile.build_plan(nodes, state)
        socketio.emit(EVENT_APPLY_PLAN, {"phase": "apply", **plan})
        if plan["errors"]:
            for err in plan["errors"]:
                report("error", err)
            socketio.emit(EVENT_APPLY_DONE, {"phase": "apply", "ok": False})
            return
        if not plan["actions"]:
            report("ok", "Nothing to do - swarm matches the config.")
            socketio.emit(EVENT_APPLY_DONE, {"phase": "apply", "ok": True})
            return
        if plan["destructive"] and not confirm_destructive:
            report("warn", "Plan contains destructive actions - confirmation required.")
            socketio.emit(
                EVENT_APPLY_DONE,
                {"phase": "apply", "ok": False, "needs_confirm": True},
            )
            return
        result = swarm_reconcile.apply_plan(nodes, state, plan, report)
        socketio.emit(EVENT_APPLY_DONE, {"phase": "apply", **result})
    except Exception as exc:  # noqa: BLE001 - surface any failure to the UI
        logger.exception("swarm apply failed")
        report("error", f"Apply failed: {exc}")
        socketio.emit(EVENT_APPLY_DONE, {"phase": "apply", "ok": False, "error": str(exc)})
    finally:
        _release_lock()


def _start_reconcile(task, *args) -> tuple:
    """Acquire the single-run guard and start a background reconcile task."""
    global _apply_running
    with _apply_lock:
        if _apply_running:
            return jsonify({"error": "a reconcile is already running"}), 409
        _apply_running = True
    socketio.start_background_task(task, *args)
    return jsonify({"started": True}), 202


@bp.post("/plan")
def plan():
    """Compute (but do not apply) the reconcile plan; streams over Socket.IO."""
    nodes = _store().list_nodes()
    return _start_reconcile(_plan_task, nodes)


@bp.post("/apply")
def apply():
    """Reconcile the live swarm to match swarm.tfvars; streams over Socket.IO."""
    data = request.get_json(silent=True) or {}
    confirm = bool(data.get("confirm_destructive"))
    nodes = _store().list_nodes()
    return _start_reconcile(_apply_task, nodes, confirm)


__all__ = ["bp", "broadcast"]
