"""Resolve ``.config`` files by their ``# homelab-config: <id>`` tag.

Python port of ``scripts/terraform/resolve_config_by_id.sh``.  A config-id
mirrors the repo layout relative to ``CONFIG_DIR`` without the file suffix, e.g.
``terraform/components/swarm/grafana/app`` or ``terraform/minio.backend``.

Every live tfvars / backend / ``docker/*.env`` under ``.config`` begins with a
first line ``# homelab-config: <config-id>``; the resolver indexes those tags so
operators can relocate files freely.  When no tagged file exists, the canonical
layout path is returned so callers still get a deterministic (missing) path to
report.
"""

from __future__ import annotations

from pathlib import Path

from .logging_util import PipelineError

_TAG_PREFIX = "# homelab-config:"
_MATCH_SUFFIXES = (".tfvars", ".auto.tfvars", ".hcl", ".env")


class ConfigResolver:
    """Index and resolve ``.config`` files by config-id.

    The index is built lazily on first lookup and cached (matching the bash
    ``homelab_config_index_build`` memoization on ``CONFIG_DIR``).
    """

    def __init__(self, config_dir: Path | str):
        self.config_dir = Path(config_dir)
        self._index: dict[str, Path] | None = None

    def _build_index(self) -> dict[str, Path]:
        index: dict[str, Path] = {}
        if not self.config_dir.is_dir():
            return index

        for path in sorted(self.config_dir.rglob("*")):
            if not path.is_file():
                continue
            name = path.name
            if name.endswith(".example"):
                continue
            if not name.endswith(_MATCH_SUFFIXES):
                continue

            first_line = _read_first_line(path)
            if first_line is None or not first_line.startswith(_TAG_PREFIX):
                continue

            config_id = first_line[len(_TAG_PREFIX):].strip()
            if not config_id:
                continue

            resolved = path.resolve()
            existing = index.get(config_id)
            if existing is not None and existing != resolved:
                raise PipelineError(
                    "Duplicate homelab-config id "
                    f"'{config_id}':\n       {existing}\n       {resolved}"
                )
            index[config_id] = resolved

        return index

    @property
    def index(self) -> dict[str, Path]:
        if self._index is None:
            self._index = self._build_index()
        return self._index

    def canonical_path(self, config_id: str) -> Path:
        """Layout path a config-id maps to when no tagged file exists."""

        if config_id == "terraform/minio.backend":
            return self.config_dir / "terraform" / "minio.backend.hcl"
        if config_id.startswith("docker/"):
            return self.config_dir / f"{config_id}.env"
        return self.config_dir / f"{config_id}.tfvars"

    def find(self, config_id: str) -> Path | None:
        """Return the tagged file for ``config_id`` if one is indexed."""

        return self.index.get(config_id)

    def resolve(self, config_id: str) -> Path:
        """Tagged file if present, else the canonical layout path."""

        found = self.find(config_id)
        if found is not None:
            return found
        return self.canonical_path(config_id)


def config_id_from_terraform_dir(root: Path | str, terraform_dir: Path | str) -> str:
    """Config-id for a Terraform slice dir (its path relative to the repo root).

    Example: ``<root>/terraform/components/swarm/grafana/app`` ->
    ``terraform/components/swarm/grafana/app``.
    """

    root_path = Path(root).resolve()
    tf_path = Path(terraform_dir).resolve()
    try:
        return tf_path.relative_to(root_path).as_posix()
    except ValueError as exc:  # pragma: no cover - defensive
        raise PipelineError(
            f"Terraform dir {tf_path} is not under repo root {root_path}"
        ) from exc


def _read_first_line(path: Path) -> str | None:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            line = handle.readline()
    except OSError:
        return None
    return line.replace("\r", "").rstrip("\n")
