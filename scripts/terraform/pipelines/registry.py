"""Discover and launch pipeline entrypoints by id.

Gives the homelab-config web app (or any caller) a stable way to enumerate the
Python pipeline entrypoints and run them programmatically, without duplicating
each slice's spec:

    from scripts.terraform.pipelines import registry
    registry.discover()                       # {id: entrypoint Path}
    registry.run("swarm/grafana/app", [])     # execute it

Ids:
    * Terraform slices: ``<domain>/<component>/<slice>`` (e.g. ``swarm/grafana/app``)
    * Docker build:     ``docker/build_push``
    * Packer build:     ``packer``
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

from .paths import repo_root

_BUILD_ENTRYPOINTS = {
    "docker/build_push": "scripts/docker/build_push.py",
    "packer": "packer/pipeline/packer.py",
}


def discover(root: Path | None = None) -> dict[str, Path]:
    """Map every pipeline id to its entrypoint file path."""

    base = root if root is not None else repo_root()
    found: dict[str, Path] = {}

    components = base / "terraform" / "components"
    if components.is_dir():
        for entry in sorted(components.glob("*/*/pipeline/*.py")):
            rel = entry.relative_to(components)
            # <domain>/<component>/pipeline/<slice>.py
            domain, component, _pipeline, filename = rel.parts
            slice_name = filename[:-3]
            found[f"{domain}/{component}/{slice_name}"] = entry

    for pid, rel_path in _BUILD_ENTRYPOINTS.items():
        path = base / rel_path
        if path.is_file():
            found[pid] = path

    return found


def entrypoint_path(pipeline_id: str, root: Path | None = None) -> Path:
    entries = discover(root)
    try:
        return entries[pipeline_id]
    except KeyError as exc:
        raise KeyError(f"Unknown pipeline id: {pipeline_id!r}") from exc


def _load_module(path: Path) -> ModuleType:
    mod_name = "homelab_pipeline_entry_" + path.as_posix().replace("/", "_").replace(".", "_")
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:  # pragma: no cover - defensive
        raise ImportError(f"Cannot load pipeline entrypoint: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load(pipeline_id: str, root: Path | None = None):
    """Return the entrypoint's ``build_pipeline()`` result, or its module.

    Terraform slice entrypoints expose ``build_pipeline() -> SlicePipeline``;
    build entrypoints expose ``main(argv)`` only, so their module is returned.
    """

    module = _load_module(entrypoint_path(pipeline_id, root))
    if hasattr(module, "build_pipeline"):
        return module.build_pipeline()
    return module


def run(pipeline_id: str, argv: list[str] | None = None, root: Path | None = None) -> int:
    """Execute a pipeline by id. Returns 0, or raises ``SystemExit`` for build ids."""

    obj = load(pipeline_id, root)
    if hasattr(obj, "run"):
        return obj.run(argv or [])
    # Build pipelines only expose main(); it calls sys.exit().
    obj.main(argv or [])
    return 0
