"""Talos cluster config helpers and ``.config/terraform/components/cluster/talos/app.tfvars`` I/O.

The file is the source of truth and is the slice ``-var-file`` consumed by the
Talos Terraform component (``terraform/components/cluster/talos/app``). It holds:

- ``cluster``: the ``provider_config.talos`` object (cluster_name,
  cluster_endpoint, endpoint, bootstrap_node, and optional talos_version /
  kubernetes_version / kubeconfig_renewal).
- ``nodes``: the fixed set of cluster nodes (one control-plane + eleven
  workers), each with a Talos API endpoint (``node``) and a list of Talos
  machine config-patch file paths.
- ``client_endpoints``: Talos client endpoints for the generated talosconfig.
- ``talosconfig_output_path`` / ``kubeconfig_output_path``: optional local file
  outputs (empty disables the file).

The Terraform slice declares a *fixed* variable per node (``k8s_cp_0_node`` …
``k8s_wk_10_node`` plus the matching ``*_config_patch_paths``), so this module
renders exactly those variables. Node membership is fixed to match that
contract; only their values are editable here.
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_str, hcl_escape
from homelab_config.paths import TALOS_APP_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/cluster/talos/app"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Talos cluster machine-config / bootstrap inputs, managed by the\n"
    "# homelab-config web app (applications/homelab_config).\n"
    "# Generated file: edit the Talos section in the UI (or by hand) then write\n"
    "# it back. Consumed by the Talos Terraform slice as its -var-file.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

# Fixed node roster matching the Talos slice's per-node variables. Order is the
# render/display order. Each tuple is (node name, machine role).
NODE_SPECS: tuple[tuple[str, str], ...] = (
    ("k8s-cp-0", "controlplane"),
    ("k8s-wk-0", "worker"),
    ("k8s-wk-1", "worker"),
    ("k8s-wk-2", "worker"),
    ("k8s-wk-3", "worker"),
    ("k8s-wk-4", "worker"),
    ("k8s-wk-5", "worker"),
    ("k8s-wk-6", "worker"),
    ("k8s-wk-7", "worker"),
    ("k8s-wk-8", "worker"),
    ("k8s-wk-9", "worker"),
    ("k8s-wk-10", "worker"),
)
_NODE_NAMES = tuple(name for name, _ in NODE_SPECS)
_NODE_ROLES = dict(NODE_SPECS)

# Cluster (provider_config.talos) fields. The first four are required by the
# slice (plain string); the rest are optional(string) and are omitted from the
# rendered object when empty so the Terraform defaults (null) apply.
_CLUSTER_REQUIRED = ("cluster_name", "cluster_endpoint", "endpoint", "bootstrap_node")
_CLUSTER_OPTIONAL = ("talos_version", "kubernetes_version", "kubeconfig_renewal")
_CLUSTER_FIELDS = _CLUSTER_REQUIRED + _CLUSTER_OPTIONAL


class TalosValidationError(ValueError):
    """Raised when a Talos config payload fails validation."""


def _var_base(node_name: str) -> str:
    """Return the Terraform variable stem for a node (``k8s-cp-0`` -> ``k8s_cp_0``)."""
    return node_name.replace("-", "_")


def default_config() -> dict:
    """Return the default (empty) Talos config used for scaffolding."""
    return {
        "cluster": {field: "" for field in _CLUSTER_FIELDS},
        "nodes": [
            {"name": name, "role": role, "node": "", "config_patch_paths": []}
            for name, role in NODE_SPECS
        ],
        "client_endpoints": [],
        "talosconfig_output_path": "",
        "kubeconfig_output_path": "",
    }


def _clean_list(value: object) -> list[str]:
    """Coerce a value into a list of non-empty trimmed strings."""
    if value is None:
        return []
    if isinstance(value, str):
        items = [value]
    elif isinstance(value, (list, tuple)):
        items = list(value)
    else:
        items = [value]
    out: list[str] = []
    for item in items:
        # coerce_str strips the surrounding quotes python-hcl2 keeps on list
        # string elements; it is a no-op for plain JSON strings from the UI.
        text = coerce_str(item).strip()
        if text:
            out.append(text)
    return out


def normalize_config(data: dict) -> dict:
    """Validate and normalize a raw Talos config payload into canonical shape.

    The node roster is fixed (:data:`NODE_SPECS`); node values are matched by
    name from the payload and any unknown nodes are ignored.
    """
    if not isinstance(data, dict):
        raise TalosValidationError("config must be an object")

    raw_cluster = data.get("cluster") or {}
    if not isinstance(raw_cluster, dict):
        raise TalosValidationError("cluster must be an object")
    cluster: dict = {}
    for field in _CLUSTER_FIELDS:
        value = raw_cluster.get(field, "")
        if value is None:
            value = ""
        if not isinstance(value, (str, int, float)):
            raise TalosValidationError(f"cluster.{field} must be a string")
        cluster[field] = str(value).strip()

    raw_nodes = data.get("nodes") or []
    by_name: dict[str, dict] = {}
    if isinstance(raw_nodes, list):
        for entry in raw_nodes:
            if isinstance(entry, dict) and entry.get("name"):
                by_name[str(entry["name"]).strip()] = entry
    elif isinstance(raw_nodes, dict):
        by_name = {str(k): v for k, v in raw_nodes.items() if isinstance(v, dict)}

    nodes: list[dict] = []
    for name, role in NODE_SPECS:
        entry = by_name.get(name, {})
        node_ip = entry.get("node", "")
        if node_ip is None:
            node_ip = ""
        nodes.append(
            {
                "name": name,
                "role": role,
                "node": str(node_ip).strip(),
                "config_patch_paths": _clean_list(entry.get("config_patch_paths")),
            }
        )

    return {
        "cluster": cluster,
        "nodes": nodes,
        "client_endpoints": _clean_list(data.get("client_endpoints")),
        "talosconfig_output_path": str(
            data.get("talosconfig_output_path") or ""
        ).strip(),
        "kubeconfig_output_path": str(
            data.get("kubeconfig_output_path") or ""
        ).strip(),
    }


def canonical(config: dict) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    cluster = config.get("cluster", {})
    cluster_t = tuple((f, cluster.get(f, "")) for f in _CLUSTER_FIELDS)
    nodes_t = tuple(
        (n["name"], n.get("node", ""), tuple(n.get("config_patch_paths", [])))
        for n in config.get("nodes", [])
    )
    return (
        cluster_t,
        nodes_t,
        tuple(config.get("client_endpoints", [])),
        config.get("talosconfig_output_path", ""),
        config.get("kubeconfig_output_path", ""),
    )


def _render_hcl_list(items: list[str]) -> str:
    if not items:
        return "[]"
    inner = ", ".join(f'"{hcl_escape(i)}"' for i in items)
    return f"[{inner}]"


def _render_client_endpoints(items: list[str]) -> str:
    if not items:
        return "client_endpoints = []\n"
    body = "client_endpoints = [\n"
    body += "".join(f'  "{hcl_escape(i)}",\n' for i in items)
    body += "]\n"
    return body


def render_config(config: dict) -> str:
    """Render the Talos app.tfvars document (including the config-id header)."""
    c = normalize_config(config)
    cluster = c["cluster"]

    lines = [_HEADER, "provider_config = {\n", "  talos = {\n"]
    for field in _CLUSTER_REQUIRED:
        lines.append(f'    {field:<16} = "{hcl_escape(cluster[field])}"\n')
    for field in _CLUSTER_OPTIONAL:
        if cluster[field]:
            lines.append(f'    {field:<16} = "{hcl_escape(cluster[field])}"\n')
    lines.append("  }\n}\n\n")

    # Per-node Talos API endpoints.
    node_key_width = max(len(f"{_var_base(n)}_node") for n in _NODE_NAMES)
    for node in c["nodes"]:
        var = f"{_var_base(node['name'])}_node"
        lines.append(f'{var:<{node_key_width}} = "{hcl_escape(node["node"])}"\n')
    lines.append("\n")

    # Per-node Talos config-patch file paths.
    patch_key_width = max(
        len(f"{_var_base(n)}_config_patch_paths") for n in _NODE_NAMES
    )
    for node in c["nodes"]:
        var = f"{_var_base(node['name'])}_config_patch_paths"
        rendered = _render_hcl_list(node["config_patch_paths"])
        lines.append(f"{var:<{patch_key_width}} = {rendered}\n")
    lines.append("\n")

    lines.append(_render_client_endpoints(c["client_endpoints"]))
    lines.append("\n")
    lines.append(
        f'talosconfig_output_path = "{hcl_escape(c["talosconfig_output_path"])}"\n'
    )
    lines.append(
        f'kubeconfig_output_path  = "{hcl_escape(c["kubeconfig_output_path"])}"\n'
    )
    return "".join(lines)


def read_talos_tfvars(path: Path = TALOS_APP_TFVARS) -> dict | None:
    """Parse the Talos app.tfvars into a normalized config dict.

    Returns:
        A normalized config dict, or ``None`` when the file is missing or
        unparsable. Missing keys default to empty values.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Talos config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None

    provider_config = data.get("provider_config")
    raw_talos = {}
    if isinstance(provider_config, dict) and isinstance(
        provider_config.get("talos"), dict
    ):
        raw_talos = provider_config["talos"]
    cluster = {field: coerce_str(raw_talos.get(field)) for field in _CLUSTER_FIELDS}

    nodes: list[dict] = []
    for name, role in NODE_SPECS:
        base = _var_base(name)
        node_ip = coerce_str(data.get(f"{base}_node"))
        patches = _clean_list(data.get(f"{base}_config_patch_paths"))
        nodes.append(
            {"name": name, "role": role, "node": node_ip, "config_patch_paths": patches}
        )

    payload = {
        "cluster": cluster,
        "nodes": nodes,
        "client_endpoints": _clean_list(data.get("client_endpoints")),
        "talosconfig_output_path": coerce_str(data.get("talosconfig_output_path")),
        "kubeconfig_output_path": coerce_str(data.get("kubeconfig_output_path")),
    }
    try:
        return normalize_config(payload)
    except TalosValidationError as exc:
        logger.warning("Invalid Talos config in %s: %s", path, exc)
        return None


def write_talos_tfvars(config: dict, path: Path = TALOS_APP_TFVARS) -> Path:
    """Write the Talos config to ``path`` atomically and return it."""
    atomic_write(path, render_config(config))
    logger.info("Wrote Talos config to %s", path)
    return path


__all__ = [
    "NODE_SPECS",
    "TalosValidationError",
    "canonical",
    "default_config",
    "normalize_config",
    "read_talos_tfvars",
    "render_config",
    "write_talos_tfvars",
]
