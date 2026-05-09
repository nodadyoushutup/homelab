from __future__ import annotations

import os
import re
from pathlib import Path

from dotenv import dotenv_values


LANGGRAPH_ROOT = Path(__file__).resolve().parents[1]


def default_repo_root() -> Path:
    """Infer homelab repo root from ``applications/langgraph`` layout."""
    return LANGGRAPH_ROOT.parent.parent.resolve()


def secrets_env_path() -> Path:
    """Homelab-wide secrets file (not per-agent ``.env``)."""
    override = os.environ.get("HOMELAB_SECRETS_ENV")
    if override:
        return Path(override).expanduser().resolve()
    return (default_repo_root() / ".secrets" / ".env").resolve()


def load_env_file(path: Path) -> dict[str, str]:
    """Load a .env file into a normal dictionary without mutating os.environ."""
    if not path.exists():
        return {}
    values = dotenv_values(path)
    return {key: value for key, value in values.items() if value is not None}


def merged_settings(app_dir: Path, *extra_env_files: Path) -> dict[str, str]:
    """Merge homelab secrets, optional extra env files, then the process environment.

    ``app_dir`` is retained for call-site compatibility; configuration is loaded from
    ``secrets_env_path()`` (default ``<repo>/.secrets/.env``) instead of per-agent
    ``.env`` files.
    """
    _ = app_dir
    merged: dict[str, str] = {}
    merged.update(load_env_file(secrets_env_path()))
    for env_file in extra_env_files:
        merged.update(load_env_file(env_file))
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
