"""Declarative reconcile for the Docker Swarm described in ``swarm.tfvars``.

Think of this as a tiny Terraform for the swarm: it reads the desired topology,
SSHes to each node to learn the *actual* state, diffs the two, and produces a
plan of the minimal actions needed to converge - init the manager, join workers,
fix roles/labels, and push SSH key sets. It never tears things down unless it has
to (e.g. the manager identity changed), and any teardown is flagged
``destructive`` so the UI can require an explicit confirmation.

Flow:
    state = gather_state(nodes, report)
    plan  = build_plan(nodes, state)          # pure diff, no side effects
    apply_plan(nodes, state, plan, report)    # runs the actions

The API layer re-gathers and re-plans at apply time (not trusting a stale plan),
and refuses destructive plans unless the caller confirmed.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Callable

from homelab_config import swarm_ssh
from homelab_config.paths import SSH_DIR
from homelab_config.swarm_ssh import SSHError

logger = logging.getLogger(__name__)

SWARM_PORT = 2377

# report(level, message): level in {info, step, cmd, ok, warn, error}
Reporter = Callable[[str, str], None]


def _noop(_level: str, _message: str) -> None:
    pass


# --- desired-state helpers ---------------------------------------------------


def _managers(nodes: list[dict]) -> list[dict]:
    return [n for n in nodes if n.get("role") == "manager"]


def _hostname_aliases(node: dict, state_entry: dict | None = None) -> set[str]:
    """Names a swarm roster Hostname might use for this node."""
    aliases = {node["name"], node["host"], node["host"].split(".", 1)[0]}
    if state_entry and state_entry.get("docker_name"):
        aliases.add(state_entry["docker_name"])
    return {a for a in aliases if a}


# --- gather ------------------------------------------------------------------

_INFO_FMT = (
    "{{.Swarm.LocalNodeState}};{{.Swarm.ControlAvailable}};"
    "{{.Swarm.NodeID}};{{if .Swarm.Cluster}}{{.Swarm.Cluster.ID}}{{end}};{{.Name}}"
)


def _gather_node(node: dict, report: Reporter) -> dict:
    """Learn one node's docker/swarm state over SSH."""
    entry = {
        "reachable": False,
        "docker": False,
        "state": "",  # active | inactive | pending | locked | ""
        "control": False,  # is this node a manager (control plane)?
        "node_id": "",
        "cluster_id": "",
        "docker_name": "",
        "error": "",
    }
    try:
        client = swarm_ssh.connect(node)
    except SSHError as exc:
        entry["error"] = str(exc)
        report("warn", f"{node['name']}: {exc}")
        return entry
    try:
        entry["reachable"] = True
        res = swarm_ssh.run(client, f"docker info --format '{_INFO_FMT}'")
        if not res.ok:
            entry["error"] = res.output() or "docker info failed"
            report("warn", f"{node['name']}: docker not available ({entry['error']})")
            return entry
        entry["docker"] = True
        parts = res.stdout.strip().split(";")
        parts += [""] * (5 - len(parts))
        entry["state"] = parts[0].strip()
        entry["control"] = parts[1].strip().lower() == "true"
        entry["node_id"] = parts[2].strip()
        entry["cluster_id"] = parts[3].strip()
        entry["docker_name"] = parts[4].strip()
        report(
            "info",
            f"{node['name']}: swarm={entry['state'] or 'inactive'}"
            f"{' (manager)' if entry['control'] else ''}",
        )
    finally:
        client.close()
    return entry


def _fetch_roster(node: dict, report: Reporter) -> dict:
    """Return the manager's node roster keyed by node ID."""
    roster: dict[str, dict] = {}
    client = swarm_ssh.connect(node)
    try:
        ls = swarm_ssh.run(
            client,
            "docker node ls --format "
            "'{{.ID}};{{.Hostname}};{{.ManagerStatus}};{{.Status}};{{.Availability}}'",
        )
        if not ls.ok:
            report("warn", f"could not read node roster: {ls.output()}")
            return roster
        for line in ls.stdout.splitlines():
            cols = line.strip().split(";")
            if len(cols) < 5 or not cols[0]:
                continue
            roster[cols[0]] = {
                "id": cols[0],
                "hostname": cols[1],
                "manager_status": cols[2],
                "status": cols[3],
                "availability": cols[4],
                "labels": {},
                "role": "manager" if cols[2] else "worker",
            }
        ids = list(roster)
        if ids:
            insp = swarm_ssh.run(
                client,
                "docker node inspect "
                + " ".join(ids)
                + " --format '{{.ID}};{{json .Spec.Labels}};{{.Spec.Role}}'",
            )
            if insp.ok:
                for line in insp.stdout.splitlines():
                    cols = line.strip().split(";", 2)
                    if len(cols) < 3 or cols[0] not in roster:
                        continue
                    try:
                        labels = json.loads(cols[1]) or {}
                    except (json.JSONDecodeError, TypeError):
                        labels = {}
                    roster[cols[0]]["labels"] = {
                        str(k): str(v) for k, v in labels.items()
                    }
                    roster[cols[0]]["role"] = cols[2].strip() or roster[cols[0]]["role"]
    finally:
        client.close()
    return roster


def gather_state(nodes: list[dict], report: Reporter = _noop) -> dict:
    """SSH to every node and return actual docker/swarm state.

    Returns a dict with per-node state, the current manager's roster (if any),
    and the name of the node currently acting as control plane.
    """
    report("step", "Gathering actual swarm state from nodes")
    per_node: dict[str, dict] = {}
    for node in nodes:
        per_node[node["name"]] = _gather_node(node, report)

    # Which node currently holds the control plane? Prefer the desired manager.
    desired_mgr = _managers(nodes)
    desired_mgr_name = desired_mgr[0]["name"] if desired_mgr else None
    control_name = None
    if desired_mgr_name and per_node.get(desired_mgr_name, {}).get("control"):
        control_name = desired_mgr_name
    else:
        for node in nodes:
            if per_node[node["name"]].get("control"):
                control_name = node["name"]
                break

    roster: dict[str, dict] = {}
    if control_name:
        control_node = next(n for n in nodes if n["name"] == control_name)
        try:
            roster = _fetch_roster(control_node, report)
        except SSHError as exc:
            report("warn", f"could not read roster from {control_name}: {exc}")

    return {
        "nodes": per_node,
        "roster": roster,
        "control_name": control_name,
    }


# --- plan --------------------------------------------------------------------


def _action(kind: str, title: str, *, destructive: bool = False, **op) -> dict:
    return {"kind": kind, "title": title, "destructive": destructive, "op": op}


def _match_roster(node: dict, state_entry: dict, roster: dict) -> dict | None:
    """Find the roster entry for a config node (by node ID, then hostname)."""
    if state_entry.get("node_id") and state_entry["node_id"] in roster:
        return roster[state_entry["node_id"]]
    aliases = _hostname_aliases(node, state_entry)
    for entry in roster.values():
        if entry["hostname"] in aliases:
            return entry
    return None


def _label_changes(desired: dict, actual: dict) -> tuple[dict, list[str]]:
    """Return (labels to add/update, label keys to remove)."""
    add = {k: v for k, v in desired.items() if actual.get(k) != v}
    remove = [k for k in actual if k not in desired]
    return add, remove


def build_plan(nodes: list[dict], state: dict) -> dict:
    """Diff desired vs actual and return an ordered list of actions.

    The returned dict has ``actions`` (ordered), ``destructive`` (bool),
    ``errors`` (blocking problems), and ``warnings``.
    """
    actions: list[dict] = []
    errors: list[str] = []
    warnings: list[str] = []

    per_node = state["nodes"]
    roster = state["roster"]

    managers = _managers(nodes)
    if len(managers) != 1:
        errors.append(
            f"exactly one node must have role 'manager' (found {len(managers)})"
        )
        return {"actions": [], "destructive": False, "errors": errors, "warnings": warnings}

    manager = managers[0]
    workers = [n for n in nodes if n["role"] == "worker"]
    mgr_state = per_node[manager["name"]]

    if not mgr_state["reachable"]:
        errors.append(f"manager {manager['name']} is unreachable: {mgr_state['error']}")
        return {"actions": [], "destructive": False, "errors": errors, "warnings": warnings}
    if not mgr_state["docker"]:
        errors.append(f"manager {manager['name']} has no working docker: {mgr_state['error']}")
        return {"actions": [], "destructive": False, "errors": errors, "warnings": warnings}

    # Is there an existing swarm anywhere, and is the desired manager its leader?
    any_swarm = any(e.get("state") == "active" for e in per_node.values())
    manager_is_control = mgr_state["control"]
    # Manager changed if a swarm exists but the desired manager isn't its control node.
    manager_changed = any_swarm and not manager_is_control

    rebuild = manager_changed
    fresh_init = not any_swarm and not manager_is_control

    if rebuild:
        warnings.append(
            "The manager is changing (or an existing swarm doesn't include the "
            "desired manager). This requires tearing the swarm down and rebuilding "
            "it - running services will be recreated."
        )
        # Leave the swarm on every node that's currently in one.
        for node in nodes:
            st = per_node[node["name"]]
            if st["reachable"] and st["docker"] and st["state"] == "active":
                actions.append(
                    _action(
                        "leave_node",
                        f"{node['name']}: leave current swarm",
                        destructive=True,
                        node=node["name"],
                    )
                )
        actions.append(
            _action("init_swarm", f"{manager['name']}: initialize swarm", manager=manager["name"])
        )
        for w in workers:
            if per_node[w["name"]]["reachable"] and per_node[w["name"]]["docker"]:
                actions.append(
                    _action(
                        "join_worker",
                        f"{w['name']}: join swarm as worker",
                        node=w["name"],
                        manager=manager["name"],
                    )
                )
    else:
        if fresh_init:
            actions.append(
                _action("init_swarm", f"{manager['name']}: initialize swarm", manager=manager["name"])
            )
        # Join workers that aren't already members of the manager's swarm.
        # Membership is decided by the manager's roster (docker node ls): a worker's
        # own `docker info` does NOT expose the cluster ID (only managers do), so a
        # cluster-ID comparison would wrongly flag every healthy worker as foreign.
        for w in workers:
            st = per_node[w["name"]]
            if not st["reachable"] or not st["docker"]:
                warnings.append(f"skipping unreachable worker {w['name']}: {st['error']}")
                continue
            if _match_roster(w, st, roster) is not None:
                continue  # already a member of our swarm
            if st["state"] == "active":
                # Active but not in our roster => it belongs to a different swarm.
                actions.append(
                    _action(
                        "leave_node",
                        f"{w['name']}: leave foreign swarm",
                        destructive=True,
                        node=w["name"],
                    )
                )
            actions.append(
                _action(
                    "join_worker",
                    f"{w['name']}: join swarm as worker",
                    node=w["name"],
                    manager=manager["name"],
                )
            )

    # Role + label reconcile against the roster (only meaningful for an existing
    # swarm we're keeping; on init/rebuild the roster is resolved at apply time).
    if not rebuild and not fresh_init:
        for node in nodes:
            st = per_node[node["name"]]
            if not st["reachable"] or not st["docker"]:
                continue
            match = _match_roster(node, st, roster)
            if match is None:
                continue  # not joined yet - handled by join above
            # Demote stray managers (we keep exactly one, the desired manager).
            if node["role"] == "worker" and match["role"] == "manager":
                actions.append(
                    _action(
                        "demote",
                        f"{node['name']}: demote to worker",
                        node=node["name"],
                        manager=manager["name"],
                    )
                )
            add, remove = _label_changes(node.get("labels", {}), match.get("labels", {}))
            if add or remove:
                bits = [f"+{k}={v}" for k, v in add.items()] + [f"-{k}" for k in remove]
                actions.append(
                    _action(
                        "apply_labels",
                        f"{node['name']}: labels {' '.join(bits)}",
                        node=node["name"],
                        manager=manager["name"],
                    )
                )

        # Remove roster nodes that aren't in the desired config.
        known_aliases: set[str] = set()
        for node in nodes:
            known_aliases |= _hostname_aliases(node, per_node[node["name"]])
        matched_ids = set()
        for node in nodes:
            m = _match_roster(node, per_node[node["name"]], roster)
            if m:
                matched_ids.add(m["id"])
        for entry in roster.values():
            if entry["id"] in matched_ids:
                continue
            if entry["hostname"] in known_aliases:
                continue
            actions.append(
                _action(
                    "remove_node",
                    f"{entry['hostname']} ({entry['id'][:12]}): remove from swarm",
                    destructive=True,
                    node_id=entry["id"],
                    hostname=entry["hostname"],
                    manager=manager["name"],
                )
            )
    else:
        # On init/rebuild, set labels for every node with labels once joined.
        for node in nodes:
            if node.get("labels") and per_node[node["name"]]["reachable"]:
                actions.append(
                    _action(
                        "apply_labels",
                        f"{node['name']}: set labels "
                        + " ".join(f"{k}={v}" for k, v in node["labels"].items()),
                        node=node["name"],
                        manager=manager["name"],
                    )
                )

    # SSH sync for nodes that opted in.
    for node in nodes:
        if not node.get("sync_ssh"):
            continue
        st = per_node[node["name"]]
        if not st["reachable"]:
            warnings.append(f"cannot sync SSH to unreachable {node['name']}")
            continue
        actions.append(
            _action(
                "sync_ssh",
                f"{node['name']}: sync SSH key set '{node.get('ssh_key') or '(none)'}' "
                "+ authorized_keys to ~/.ssh",
                node=node["name"],
            )
        )

    destructive = any(a["destructive"] for a in actions)
    return {
        "actions": actions,
        "destructive": destructive,
        "errors": errors,
        "warnings": warnings,
    }


# --- apply -------------------------------------------------------------------


class _Conns:
    """Lazy, cached SSH connections keyed by node name."""

    def __init__(self, nodes: list[dict]) -> None:
        self._by_name = {n["name"]: n for n in nodes}
        self._clients: dict[str, object] = {}

    def get(self, name: str):
        if name not in self._clients:
            self._clients[name] = swarm_ssh.connect(self._by_name[name])
        return self._clients[name]

    def node(self, name: str) -> dict:
        return self._by_name[name]

    def close(self) -> None:
        for client in self._clients.values():
            try:
                client.close()
            except Exception:  # noqa: BLE001 - best effort cleanup
                pass
        self._clients.clear()


def _run(report: Reporter, client, command: str, *, timeout: int = 180):
    report("cmd", f"$ {command}")
    res = swarm_ssh.run(client, command, timeout=timeout)
    if res.stdout.strip():
        report("info", res.stdout.strip())
    if not res.ok and res.stderr.strip():
        report("error", res.stderr.strip())
    return res


def _resolve_node_id(report: Reporter, mgr_client, node: dict, state_entry: dict) -> str | None:
    ls = swarm_ssh.run(mgr_client, "docker node ls --format '{{.ID}};{{.Hostname}}'")
    if not ls.ok:
        return None
    aliases = _hostname_aliases(node, state_entry)
    for line in ls.stdout.splitlines():
        cols = line.strip().split(";")
        if len(cols) >= 2 and cols[1] in aliases:
            return cols[0]
    return None


def ssh_sync_files(node: dict) -> list[tuple[Path, str, int]]:
    """Build the (local, remote_name, mode) list to push for sync_ssh.

    Reused by the Docker extra-host apply (non-swarm SSH push): it enumerates the
    node's key set under ``.config/.ssh/<ssh_key>`` and returns each file with the
    right remote name + mode (private keys/authorized_keys 0600, public 0644).
    """
    files: list[tuple[Path, str, int]] = []
    key_set = node.get("ssh_key") or ""
    if key_set:
        set_dir = SSH_DIR / key_set
        if set_dir.is_dir():
            for entry in sorted(set_dir.iterdir()):
                if not entry.is_file():
                    continue
                is_private = not entry.name.endswith((".pub", "-cert.pub")) and (
                    entry.name == "authorized_keys"
                    or "PRIVATE KEY"
                    in entry.read_text(encoding="utf-8", errors="replace")[:64]
                )
                mode = 0o600 if is_private else 0o644
                files.append((entry, entry.name, mode))
    return files


def _apply_action(action: dict, conns: _Conns, state: dict, report: Reporter) -> None:
    kind = action["kind"]
    op = action["op"]
    report("step", action["title"])

    if kind == "leave_node":
        client = conns.get(op["node"])
        _run(report, client, "docker swarm leave --force")

    elif kind == "init_swarm":
        node = conns.node(op["manager"])
        client = conns.get(op["manager"])
        res = _run(
            report,
            client,
            f"docker swarm init --advertise-addr {node['host']}",
        )
        if not res.ok:
            raise SSHError(f"swarm init failed: {res.output()}")

    elif kind == "join_worker":
        mgr_client = conns.get(op["manager"])
        mgr_node = conns.node(op["manager"])
        token_res = swarm_ssh.run(mgr_client, "docker swarm join-token worker -q")
        if not token_res.ok or not token_res.stdout.strip():
            raise SSHError(f"could not read worker join token: {token_res.output()}")
        token = token_res.stdout.strip()
        client = conns.get(op["node"])
        res = _run(
            report,
            client,
            f"docker swarm join --token {token} {mgr_node['host']}:{SWARM_PORT}",
        )
        if not res.ok:
            raise SSHError(f"join failed: {res.output()}")

    elif kind == "demote":
        client = conns.get(op["manager"])
        node = conns.node(op["node"])
        nid = _resolve_node_id(report, client, node, state["nodes"][op["node"]])
        if nid:
            _run(report, client, f"docker node demote {nid}")

    elif kind == "remove_node":
        client = conns.get(op["manager"])
        _run(report, client, f"docker node rm --force {op['node_id']}")

    elif kind == "apply_labels":
        client = conns.get(op["manager"])
        node = conns.node(op["node"])
        nid = _resolve_node_id(report, client, node, state["nodes"][op["node"]])
        if not nid:
            report("warn", f"{op['node']}: not in roster yet, skipping labels")
            return
        inspect = swarm_ssh.run(
            client, f"docker node inspect {nid} --format '{{{{json .Spec.Labels}}}}'"
        )
        try:
            actual = json.loads(inspect.stdout.strip()) or {} if inspect.ok else {}
        except (json.JSONDecodeError, TypeError):
            actual = {}
        desired = node.get("labels", {})
        add, remove = _label_changes(desired, {str(k): str(v) for k, v in actual.items()})
        for key, value in add.items():
            _run(report, client, f"docker node update --label-add {key}={value} {nid}")
        for key in remove:
            _run(report, client, f"docker node update --label-rm {key} {nid}")

    elif kind == "sync_ssh":
        node = conns.node(op["node"])
        client = conns.get(op["node"])
        files = ssh_sync_files(node)
        if not files:
            report("warn", f"{op['node']}: nothing to sync (empty/missing key set)")
            return
        remote_home_ssh = f"/home/{node['ssh_user']}/.ssh"
        pushed = swarm_ssh.put_files(client, files, remote_home_ssh)
        report("ok", f"{op['node']}: pushed {', '.join(pushed)} to {remote_home_ssh}")

    else:  # pragma: no cover - guarded by build_plan
        report("warn", f"unknown action kind: {kind}")


def apply_plan(
    nodes: list[dict],
    state: dict,
    plan: dict,
    report: Reporter = _noop,
) -> dict:
    """Execute a plan's actions in order. Returns ``{ok, applied, failed}``."""
    conns = _Conns(nodes)
    applied = 0
    failed = 0
    try:
        for action in plan["actions"]:
            try:
                _apply_action(action, conns, state, report)
                report("ok", f"done: {action['title']}")
                applied += 1
            except SSHError as exc:
                failed += 1
                report("error", f"{action['title']}: {exc}")
                # Stop on the first failure of a structural action; labels/sync are
                # best-effort and could continue, but halting is safer/clearer.
                if action["kind"] in {"init_swarm", "join_worker", "leave_node"}:
                    report("error", "Halting: a structural step failed.")
                    break
    finally:
        conns.close()
    ok = failed == 0
    report("ok" if ok else "error", f"Apply finished: {applied} applied, {failed} failed")
    return {"ok": ok, "applied": applied, "failed": failed}


__all__ = ["apply_plan", "build_plan", "gather_state", "ssh_sync_files"]
