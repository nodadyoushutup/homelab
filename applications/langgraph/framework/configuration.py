from __future__ import annotations

import os
import re
from pathlib import Path

from dotenv import dotenv_values


LANGGRAPH_ROOT = Path(__file__).resolve().parents[1]

DOCKER_ENV_LOAD_ORDER: tuple[str, ...] = (
    "site.env",
    "shared.env",
    "postgres.env",
    "rag.env",
    "mcp.env",
    "langgraph.env",
    "agents.env",
    "argocd.env",
    "minio.env",
    "qbittorrent.env",
)


def default_repo_root() -> Path:
    """Infer homelab repo root from ``applications/langgraph`` layout."""
    override = os.environ.get("HOMELAB_REPO_ROOT")
    if override:
        return Path(override).expanduser().resolve()
    return LANGGRAPH_ROOT.parent.parent.resolve()


def config_env_dir() -> Path:
    """Directory of split homelab dotenv files (``.config/docker``)."""
    override = os.environ.get("HOMELAB_CONFIG_ENV_DIR")
    if override:
        return Path(override).expanduser().resolve()
    legacy = os.environ.get("HOMELAB_CONFIG_ENV") or os.environ.get("HOMELAB_SECRETS_ENV")
    if legacy:
        path = Path(legacy).expanduser().resolve()
        if path.is_dir():
            return path
        if path.name == ".env" and path.parent.name == "docker":
            return path.parent
    return (default_repo_root() / ".config" / "docker").resolve()


def config_env_files() -> list[Path]:
    """Split dotenv paths in merge order (later files override earlier keys)."""
    env_dir = config_env_dir()
    return [env_dir / name for name in DOCKER_ENV_LOAD_ORDER]


def config_env_path() -> Path:
    """Primary dotenv path for error messages (``langgraph.env``)."""
    return config_env_dir() / "langgraph.env"


def secrets_env_path() -> Path:
    """Deprecated alias for :func:`config_env_path`."""
    return config_env_path()


def load_env_file(path: Path) -> dict[str, str]:
    """Load a .env file into a normal dictionary without mutating os.environ."""
    if not path.exists():
        return {}
    values = dotenv_values(path)
    return {key: value for key, value in values.items() if value is not None}


def load_merged_env_files(paths: list[Path]) -> dict[str, str]:
    merged: dict[str, str] = {}
    for path in paths:
        merged.update(load_env_file(path))
    return merged


def assert_no_langgraph_local_env_files() -> None:
    """Fail fast if ignored app-local dotenv files reappear under LangGraph."""
    allowed_dir = config_env_dir()
    local_env_files = list(LANGGRAPH_ROOT.rglob(".env"))
    if local_env_files:
        formatted = ", ".join(str(path) for path in sorted(local_env_files))
        raise RuntimeError(
            "LangGraph configuration must come from "
            f"{allowed_dir}/*.env; remove app-local .env file(s): {formatted}"
        )


def merged_settings(app_dir: Path, *extra_env_files: Path) -> dict[str, str]:
    """Merge homelab split dotenv files, then the process environment.

    ``app_dir`` and ``extra_env_files`` are retained for call-site compatibility but
    ignored so LangGraph uses the canonical ``.config/docker/*.env`` set only.
    """
    _ = (app_dir, extra_env_files)
    assert_no_langgraph_local_env_files()
    monolith = config_env_dir() / ".env"
    if monolith.exists():
        raise RuntimeError(
            f"Remove monolithic {monolith} and use split files under {config_env_dir()} "
            "(see .config/docker/README.md)."
        )
    secrets = load_merged_env_files(config_env_files())
    for key, value in secrets.items():
        os.environ.setdefault(key, value)

    merged: dict[str, str] = {}
    merged.update(secrets)
    merged.update({key: value for key, value in os.environ.items() if value is not None})
    return merged


def resolve_skill_roots(*paths: Path) -> list[str]:
    return [str(path) for path in paths if path.exists()]


def load_system_prompt(path: Path, variables: dict[str, str] | None = None) -> str:
    """Load a Markdown-backed system prompt and interpolate {{ variable }} tokens."""
    if not path.exists():
        raise FileNotFoundError(f"System prompt file does not exist: {path}")

    raw_prompt = path.read_text().strip()
    if not raw_prompt:
        raise ValueError(f"System prompt file is empty: {path}")

    values = variables or {}

    def _replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in values:
            raise KeyError(f"Missing system prompt variable '{key}' for {path}")
        return values[key]

    return re.sub(r"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}", _replace, raw_prompt)


def load_markdown_directory(path: Path, variables: dict[str, str] | None = None) -> list[str]:
    """Load all Markdown files in a directory in deterministic filename order."""
    if not path.exists():
        return []
    if not path.is_dir():
        raise NotADirectoryError(f"Markdown prompt path is not a directory: {path}")

    return [
        load_system_prompt(markdown_path, variables)
        for markdown_path in sorted(path.glob("*.md"))
    ]


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def resolve_repo_root(configured_path: str | None = None) -> Path:
    """Resolve the repository root used for repo-scoped filesystem access."""
    root = default_repo_root()
    if not configured_path:
        return root

    path = Path(configured_path).expanduser()
    if path.is_absolute():
        return path.resolve()
    return (root / path).resolve()
