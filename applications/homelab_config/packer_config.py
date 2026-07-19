"""Packer build-default helpers and read/write for
``.config/packer/build.pkrvars.hcl``.

The file is the source of truth for the Packer build defaults consumed by
``packer/packer.sh`` and ``packer/pipeline/packer.sh`` (CLI flags still
override). It is shaped like a Packer var-file (HCL ``key = value`` lines) but
also carries orchestration keys (``distro``, ``build_arch``, ``target``,
``publish``) that are NOT declared Packer variables, so the shell scripts parse
it for their own defaults rather than feeding it to ``packer -var-file``.
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import PACKER_BUILD_PKRVARS

logger = logging.getLogger(__name__)

_CONFIG_ID = "packer/build"
_HEADER = (
    f"# homelab-config: {_CONFIG_ID}\n"
    "# Packer build defaults, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit settings in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed as DEFAULTS by packer/packer.sh and packer/pipeline/packer.sh;\n"
    "# explicit CLI flags still override. Shaped like a Packer var-file but it\n"
    "# also carries orchestration keys (distro, build_arch, target, publish) that\n"
    "# are not Packer variables, so the scripts parse it for their own defaults\n"
    "# rather than feeding it to `packer -var-file`.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

# Allowed values for the enum-style fields. The first entry is the default.
DISTROS = ("ubuntu", "arch", "centos", "kali")
GUIS = ("headless", "gnome", "kde", "xfce")
BUILD_ARCHES = ("amd64", "arm64", "both")
ACCELERATORS = ("kvm", "tcg", "none")
TARGETS = ("cloud-image-repository",)


class ConfigValidationError(ValueError):
    """Raised when a Packer settings payload fails validation."""


def default_settings() -> dict:
    """Return the built-in Packer build defaults (mirroring packer/packer.sh)."""
    return {
        "distro": "ubuntu",
        "image_version": "",
        "gui": "headless",
        "install_node_exporter": False,
        "ubuntu_release": "24.04",
        "centos_stream": "10",
        "arch_snapshot": "",
        "kali_release": "2026.2",
        "target": "cloud-image-repository",
        "build_arch": "amd64",
        "amd64_accelerator": "kvm",
        "arm64_accelerator": "kvm",
        "publish": False,
    }


def _coerce_choice(value: object, choices: tuple[str, ...]) -> str:
    """Return a normalized choice, falling back to the first (default) choice."""
    text = coerce_str(value).strip()
    return text if text in choices else choices[0]


def normalize(data: dict) -> dict:
    """Validate and normalize the raw settings payload into canonical shape."""
    data = data or {}
    return {
        "distro": _coerce_choice(data.get("distro"), DISTROS),
        "image_version": coerce_str(data.get("image_version")).strip(),
        "gui": _coerce_choice(data.get("gui"), GUIS),
        "install_node_exporter": coerce_bool(
            data.get("install_node_exporter"), default=False
        ),
        "ubuntu_release": coerce_str(data.get("ubuntu_release")).strip() or "24.04",
        "centos_stream": coerce_str(data.get("centos_stream")).strip() or "10",
        "arch_snapshot": coerce_str(data.get("arch_snapshot")).strip(),
        "kali_release": coerce_str(data.get("kali_release")).strip() or "2026.2",
        "target": _coerce_choice(data.get("target"), TARGETS),
        "build_arch": _coerce_choice(data.get("build_arch"), BUILD_ARCHES),
        "amd64_accelerator": _coerce_choice(
            data.get("amd64_accelerator"), ACCELERATORS
        ),
        "arm64_accelerator": _coerce_choice(
            data.get("arm64_accelerator"), ACCELERATORS
        ),
        "publish": coerce_bool(data.get("publish"), default=False),
    }


def canonical(settings: dict) -> tuple:
    """Return a hashable form for equality/drift checks."""
    return (
        settings.get("distro", ""),
        settings.get("image_version", ""),
        settings.get("gui", ""),
        bool(settings.get("install_node_exporter", False)),
        settings.get("ubuntu_release", ""),
        settings.get("centos_stream", ""),
        settings.get("arch_snapshot", ""),
        settings.get("kali_release", ""),
        settings.get("target", ""),
        settings.get("build_arch", ""),
        settings.get("amd64_accelerator", ""),
        settings.get("arm64_accelerator", ""),
        bool(settings.get("publish", False)),
    )


# --- rendering -------------------------------------------------------------


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _b(value: object) -> str:
    return "true" if value else "false"


def render_settings(settings: dict) -> str:
    """Render the Packer build var-file document (with the config-id header)."""
    body = (
        f"distro                = {_q(settings.get('distro', ''))}\n"
        f"image_version         = {_q(settings.get('image_version', ''))}\n"
        f"gui                   = {_q(settings.get('gui', ''))}\n"
        f"install_node_exporter = {_b(settings.get('install_node_exporter', False))}\n"
        f"ubuntu_release        = {_q(settings.get('ubuntu_release', ''))}\n"
        f"centos_stream         = {_q(settings.get('centos_stream', ''))}\n"
        f"arch_snapshot         = {_q(settings.get('arch_snapshot', ''))}\n"
        f"kali_release          = {_q(settings.get('kali_release', ''))}\n"
        f"target                = {_q(settings.get('target', ''))}\n"
        f"build_arch            = {_q(settings.get('build_arch', ''))}\n"
        f"amd64_accelerator     = {_q(settings.get('amd64_accelerator', ''))}\n"
        f"arm64_accelerator     = {_q(settings.get('arm64_accelerator', ''))}\n"
        f"publish               = {_b(settings.get('publish', False))}\n"
    )
    return f"{_HEADER}\n{body}"


# --- reading ---------------------------------------------------------------


def read_packer_pkrvars(path: Path = PACKER_BUILD_PKRVARS) -> dict | None:
    """Parse the Packer build var-file into settings, or ``None``.

    Returns ``None`` only when the file is missing/unparsable.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Packer config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    return normalize(
        {
            "distro": data.get("distro"),
            "image_version": data.get("image_version"),
            "gui": data.get("gui"),
            "install_node_exporter": data.get("install_node_exporter"),
            "ubuntu_release": data.get("ubuntu_release"),
            "centos_stream": data.get("centos_stream"),
            "arch_snapshot": data.get("arch_snapshot"),
            "kali_release": data.get("kali_release"),
            "target": data.get("target"),
            "build_arch": data.get("build_arch"),
            "amd64_accelerator": data.get("amd64_accelerator"),
            "arm64_accelerator": data.get("arm64_accelerator"),
            "publish": data.get("publish"),
        }
    )


def write_packer_pkrvars(settings: dict, path: Path = PACKER_BUILD_PKRVARS) -> Path:
    """Write the Packer settings to ``path`` atomically and return it."""
    atomic_write(path, render_settings(settings))
    logger.info("Wrote Packer config to %s", path)
    return path


__all__ = [
    "ConfigValidationError",
    "canonical",
    "default_settings",
    "normalize",
    "read_packer_pkrvars",
    "render_settings",
    "write_packer_pkrvars",
]
