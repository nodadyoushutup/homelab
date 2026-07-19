"""Jenkins swarm-app deploy config helpers and per-slice app.tfvars I/O.

The CICD Jenkins section edits three Swarm Terraform slices, each with its own
``app.tfvars`` (the slice ``-var-file``):

- ``controller`` -> ``terraform/components/swarm/jenkins-controller/app``
- ``agent-amd64`` -> ``terraform/components/swarm/jenkins-agent-amd64/app``
- ``agent-arm64`` -> ``terraform/components/swarm/jenkins-agent-arm64/app``

Only the operator-facing inputs are managed here (the shape the app.tfvars.example
files set); every other slice variable keeps its Terraform default. The
controller and agents share a common core (docker_machine, dns_nameservers,
NFS selection, casc_config_path, env) and add slice-specific fields
(controller: ports / shared volume / mounts / placement; agents: jenkins_url /
agent_label_filter).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import (
    JENKINS_AGENT_AMD64_APP_TFVARS,
    JENKINS_AGENT_ARM64_APP_TFVARS,
    JENKINS_CONTROLLER_APP_TFVARS,
)

logger = logging.getLogger(__name__)

CONTROLLER = "controller"
AGENT_AMD64 = "agent-amd64"
AGENT_ARM64 = "agent-arm64"


@dataclass(frozen=True)
class JenkinsSlice:
    """Static description of one Jenkins deploy slice."""

    key: str
    title: str
    kind: str  # "controller" or "agent"
    config_id: str
    path: Path

    @property
    def tfvars_display(self) -> str:
        return f".config/{self.config_id}.tfvars"


SLICES: tuple[JenkinsSlice, ...] = (
    JenkinsSlice(
        key=CONTROLLER,
        title="Controller",
        kind="controller",
        config_id="terraform/components/swarm/jenkins-controller/app",
        path=JENKINS_CONTROLLER_APP_TFVARS,
    ),
    JenkinsSlice(
        key=AGENT_AMD64,
        title="Agent (amd64)",
        kind="agent",
        config_id="terraform/components/swarm/jenkins-agent-amd64/app",
        path=JENKINS_AGENT_AMD64_APP_TFVARS,
    ),
    JenkinsSlice(
        key=AGENT_ARM64,
        title="Agent (arm64)",
        kind="agent",
        config_id="terraform/components/swarm/jenkins-agent-arm64/app",
        path=JENKINS_AGENT_ARM64_APP_TFVARS,
    ),
)
SLICES_BY_KEY = {s.key: s for s in SLICES}
SLICE_KEYS = tuple(s.key for s in SLICES)


class JenkinsValidationError(ValueError):
    """Raised when a Jenkins slice payload fails validation."""


def _slice(key: str) -> JenkinsSlice:
    slice_ = SLICES_BY_KEY.get(key)
    if slice_ is None:
        raise JenkinsValidationError(f"unknown Jenkins slice: {key!r}")
    return slice_


# --- normalization -----------------------------------------------------------


def _str(value: object) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _str_list(value: object) -> list[str]:
    if value is None:
        return []
    items = value if isinstance(value, (list, tuple)) else [value]
    out: list[str] = []
    for item in items:
        text = coerce_str(item).strip()
        if text:
            out.append(text)
    return out


def _env_pairs(value: object) -> list[dict]:
    """Normalize an env map into an ordered list of {key, value} (keeps blanks).

    Accepts either a dict (parsed tfvars / JSON object) or a list of
    ``{"key", "value"}`` rows (from the UI). Entries with a blank key are
    dropped; blank values are kept (env keys are meaningful placeholders).
    """
    pairs: list[dict] = []
    if isinstance(value, dict):
        items = list(value.items())
    elif isinstance(value, (list, tuple)):
        items = []
        for row in value:
            if isinstance(row, dict):
                items.append((row.get("key", ""), row.get("value", "")))
    else:
        items = []
    seen: set[str] = set()
    for raw_key, raw_val in items:
        key = coerce_str(raw_key).strip()
        if not key or key in seen:
            continue
        seen.add(key)
        pairs.append({"key": key, "value": coerce_str(raw_val)})
    return pairs


def _mounts(value: object) -> list[dict]:
    """Normalize the controller ``mounts`` list of objects."""
    if not isinstance(value, (list, tuple)):
        return []
    out: list[dict] = []
    for row in value:
        if not isinstance(row, dict):
            continue
        name = coerce_str(row.get("name")).strip()
        target = coerce_str(row.get("target")).strip()
        driver = coerce_str(row.get("driver")).strip()
        driver_opts = _env_pairs(row.get("driver_opts"))
        no_copy = coerce_bool(row.get("no_copy"), default=False)
        if not (name or target or driver or driver_opts):
            continue
        out.append(
            {
                "name": name,
                "target": target,
                "driver": driver,
                "driver_opts": driver_opts,
                "no_copy": no_copy,
            }
        )
    return out


def _placement(value: object) -> dict:
    """Normalize the controller ``placement`` object; empty -> disabled."""
    if not isinstance(value, dict):
        return {"constraints": [], "platforms": []}
    constraints = _str_list(value.get("constraints"))
    platforms_raw = value.get("platforms")
    platforms: list[dict] = []
    if isinstance(platforms_raw, (list, tuple)):
        for row in platforms_raw:
            if not isinstance(row, dict):
                continue
            os_ = coerce_str(row.get("os")).strip()
            arch = coerce_str(row.get("architecture")).strip()
            if os_ or arch:
                platforms.append({"os": os_, "architecture": arch})
    return {"constraints": constraints, "platforms": platforms}


def _placement_empty(placement: dict) -> bool:
    return not placement.get("constraints") and not placement.get("platforms")


def default_config(kind: str) -> dict:
    """Return the default (empty) config for a slice kind."""
    common = {
        "docker_machine": "",
        "dns_nameservers": [],
        "nfs_share": "code",
        "nfs_subpath": "",
        "nfs_mount_target": "",
        "casc_config_path": "",
        "env": [],
    }
    if kind == "controller":
        common.update(
            {
                "controller_published_port": "",
                "agent_published_port": "",
                "shared_tfvars_volume_name": "",
                "mounts": [],
                "placement": {"constraints": [], "platforms": []},
            }
        )
    else:
        common.update({"jenkins_url": "", "agent_label_filter": []})
    return common


def normalize_config(key: str, data: dict) -> dict:
    """Validate + normalize a raw payload for a slice into canonical shape."""
    slice_ = _slice(key)
    if not isinstance(data, dict):
        raise JenkinsValidationError("config must be an object")
    record = {
        "docker_machine": _str(data.get("docker_machine")),
        "dns_nameservers": _str_list(data.get("dns_nameservers")),
        "nfs_share": _str(data.get("nfs_share")),
        "nfs_subpath": _str(data.get("nfs_subpath")),
        "nfs_mount_target": _str(data.get("nfs_mount_target")),
        "casc_config_path": _str(data.get("casc_config_path")),
        "env": _env_pairs(data.get("env")),
    }
    if slice_.kind == "controller":
        record["controller_published_port"] = _port(data.get("controller_published_port"))
        record["agent_published_port"] = _port(data.get("agent_published_port"))
        record["shared_tfvars_volume_name"] = _str(data.get("shared_tfvars_volume_name"))
        record["mounts"] = _mounts(data.get("mounts"))
        record["placement"] = _placement(data.get("placement"))
    else:
        record["jenkins_url"] = _str(data.get("jenkins_url"))
        record["agent_label_filter"] = _str_list(data.get("agent_label_filter"))
    return record


def _port(value: object) -> str:
    """Coerce a port field to a canonical string ('' when unset/invalid)."""
    text = _str(value)
    if not text:
        return ""
    try:
        return str(int(float(text)))
    except (TypeError, ValueError):
        raise JenkinsValidationError(f"port must be a number, got {value!r}")


def canonical(key: str, record: dict) -> tuple:
    """Return an order-insensitive-where-appropriate hashable form for drift."""
    slice_ = _slice(key)
    base = (
        record.get("docker_machine", ""),
        tuple(record.get("dns_nameservers", [])),
        record.get("nfs_share", ""),
        record.get("nfs_subpath", ""),
        record.get("nfs_mount_target", ""),
        record.get("casc_config_path", ""),
        tuple((p["key"], p["value"]) for p in record.get("env", [])),
    )
    if slice_.kind == "controller":
        pl = record.get("placement", {})
        extra = (
            record.get("controller_published_port", ""),
            record.get("agent_published_port", ""),
            record.get("shared_tfvars_volume_name", ""),
            tuple(
                (
                    m["name"],
                    m["target"],
                    m["driver"],
                    tuple((o["key"], o["value"]) for o in m["driver_opts"]),
                    m["no_copy"],
                )
                for m in record.get("mounts", [])
            ),
            tuple(pl.get("constraints", [])),
            tuple((p["os"], p["architecture"]) for p in pl.get("platforms", [])),
        )
    else:
        extra = (
            record.get("jenkins_url", ""),
            tuple(record.get("agent_label_filter", [])),
        )
    return base + extra


# --- rendering ---------------------------------------------------------------


def _q(value: str) -> str:
    return f'"{hcl_escape(value)}"'


def _render_str(name: str, value: str, width: int = 0) -> str:
    return f"{name:<{width}} = {_q(value)}\n" if width else f"{name} = {_q(value)}\n"


def _render_multiline_list(name: str, items: list[str]) -> str:
    if not items:
        return f"{name} = []\n"
    body = f"{name} = [\n"
    body += "".join(f"  {_q(i)},\n" for i in items)
    body += "]\n"
    return body


def _render_inline_list(name: str, items: list[str]) -> str:
    if not items:
        return f"{name} = []\n"
    inner = ", ".join(_q(i) for i in items)
    return f"{name} = [{inner}]\n"


def _render_env(pairs: list[dict]) -> str:
    if not pairs:
        return "env = {}\n"
    width = max(len(p["key"]) for p in pairs)
    body = "env = {\n"
    body += "".join(f'  {p["key"]:<{width}} = {_q(p["value"])}\n' for p in pairs)
    body += "}\n"
    return body


def _render_driver_opts(pairs: list[dict]) -> str:
    if not pairs:
        return "{}"
    inner = ", ".join(f'{p["key"]} = {_q(p["value"])}' for p in pairs)
    return f"{{ {inner} }}"


def _render_mounts(mounts: list[dict]) -> str:
    if not mounts:
        return "mounts = []\n"
    body = "mounts = [\n"
    for m in mounts:
        body += "  {\n"
        body += f'    name        = {_q(m["name"])}\n'
        body += f'    target      = {_q(m["target"])}\n'
        body += f'    driver      = {_q(m["driver"])}\n'
        body += f'    driver_opts = {_render_driver_opts(m["driver_opts"])}\n'
        body += f'    no_copy     = {"true" if m["no_copy"] else "false"}\n'
        body += "  },\n"
    body += "]\n"
    return body


def _render_placement(placement: dict) -> str:
    body = "placement = {\n"
    constraints = placement.get("constraints", [])
    if constraints:
        inner = ", ".join(_q(c) for c in constraints)
        body += f"  constraints = [{inner}]\n"
    else:
        body += "  constraints = []\n"
    platforms = placement.get("platforms", [])
    if platforms:
        body += "  platforms = [\n"
        for p in platforms:
            body += "    {\n"
            body += f'      os           = {_q(p["os"])}\n'
            body += f'      architecture = {_q(p["architecture"])}\n'
            body += "    },\n"
        body += "  ]\n"
    else:
        body += "  platforms = []\n"
    body += "}\n"
    return body


def _header(slice_: JenkinsSlice) -> str:
    return (
        f"# homelab-config: {slice_.config_id}\n"
        f"# Jenkins {slice_.title} deploy inputs, managed by the homelab-config web\n"
        "# app (applications/homelab_config). Generated file: edit the Jenkins\n"
        "# section (CICD) in the UI, or by hand. Consumed by the slice as its\n"
        "# -var-file. Lives under .config (git-ignored) - do not commit it.\n"
    )


def render_config(key: str, config: dict) -> str:
    """Render a slice's app.tfvars document (with config-id header)."""
    slice_ = _slice(key)
    c = normalize_config(key, config)
    lines = [_header(slice_), "\n"]
    lines.append(_render_str("docker_machine", c["docker_machine"]))
    lines.append("\n")
    lines.append(_render_multiline_list("dns_nameservers", c["dns_nameservers"]))
    lines.append("\n")
    lines.append(_render_str("nfs_share", c["nfs_share"], width=16))
    lines.append(_render_str("nfs_subpath", c["nfs_subpath"], width=16))
    lines.append(_render_str("nfs_mount_target", c["nfs_mount_target"], width=16))

    if slice_.kind == "controller":
        if c["controller_published_port"]:
            lines.append(
                f'controller_published_port = {c["controller_published_port"]}\n'
            )
        if c["agent_published_port"]:
            lines.append(f'agent_published_port      = {c["agent_published_port"]}\n')
        lines.append("\n")
        lines.append(_render_str("casc_config_path", c["casc_config_path"]))
        lines.append(
            _render_str("shared_tfvars_volume_name", c["shared_tfvars_volume_name"])
        )
        lines.append("\n")
        lines.append(_render_mounts(c["mounts"]))
        lines.append("\n")
        lines.append(_render_env(c["env"]))
        if not _placement_empty(c["placement"]):
            lines.append("\n")
            lines.append(_render_placement(c["placement"]))
    else:
        lines.append(_render_str("jenkins_url", c["jenkins_url"]))
        lines.append(_render_inline_list("agent_label_filter", c["agent_label_filter"]))
        lines.append("\n")
        lines.append(_render_str("casc_config_path", c["casc_config_path"]))
        lines.append("\n")
        lines.append(_render_env(c["env"]))
    return "".join(lines)


# --- parsing -----------------------------------------------------------------


def read_tfvars(key: str, path: Path | None = None) -> dict | None:
    """Parse a slice's app.tfvars into a normalized config dict (or None)."""
    slice_ = _slice(key)
    target = path or slice_.path
    if not target.is_file():
        return None
    try:
        with target.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Jenkins %s config %s: %s", key, target, exc)
        return None
    if not isinstance(data, dict):
        return None

    payload = {
        "docker_machine": coerce_str(data.get("docker_machine")),
        "dns_nameservers": _str_list(data.get("dns_nameservers")),
        "nfs_share": coerce_str(data.get("nfs_share")) or "code",
        "nfs_subpath": coerce_str(data.get("nfs_subpath")),
        "nfs_mount_target": coerce_str(data.get("nfs_mount_target")),
        "casc_config_path": coerce_str(data.get("casc_config_path")),
        "env": _env_pairs(data.get("env")),
    }
    if slice_.kind == "controller":
        payload["controller_published_port"] = data.get("controller_published_port")
        payload["agent_published_port"] = data.get("agent_published_port")
        payload["shared_tfvars_volume_name"] = coerce_str(
            data.get("shared_tfvars_volume_name")
        )
        payload["mounts"] = _mounts(data.get("mounts"))
        payload["placement"] = _placement(data.get("placement"))
    else:
        payload["jenkins_url"] = coerce_str(data.get("jenkins_url"))
        payload["agent_label_filter"] = _str_list(data.get("agent_label_filter"))
    try:
        return normalize_config(key, payload)
    except JenkinsValidationError as exc:
        logger.warning("Invalid Jenkins %s config in %s: %s", key, target, exc)
        return None


def write_tfvars(key: str, config: dict, path: Path | None = None) -> Path:
    """Write a slice's config atomically and return the path."""
    slice_ = _slice(key)
    target = path or slice_.path
    atomic_write(target, render_config(key, config))
    logger.info("Wrote Jenkins %s config to %s", key, target)
    return target


__all__ = [
    "AGENT_AMD64",
    "AGENT_ARM64",
    "CONTROLLER",
    "JenkinsSlice",
    "JenkinsValidationError",
    "SLICES",
    "SLICES_BY_KEY",
    "SLICE_KEYS",
    "canonical",
    "default_config",
    "normalize_config",
    "read_tfvars",
    "render_config",
    "write_tfvars",
]
