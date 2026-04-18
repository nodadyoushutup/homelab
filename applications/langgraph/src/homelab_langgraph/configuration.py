from __future__ import annotations

import os
from pathlib import Path

from dotenv import dotenv_values


LANGGRAPH_ROOT = Path(__file__).resolve().parents[2]


def load_env_file(path: Path) -> dict[str, str]:
    """Load a .env file into a normal dictionary without mutating os.environ."""
    if not path.exists():
        return {}
    values = dotenv_values(path)
    return {key: value for key, value in values.items() if value is not None}


def merged_settings(app_dir: Path, *extra_env_files: Path) -> dict[str, str]:
    """Merge local env files with the process environment."""
    merged: dict[str, str] = {}
    merged.update(load_env_file(app_dir / ".env"))
    for env_file in extra_env_files:
        merged.update(load_env_file(env_file))
    merged.update({key: value for key, value in os.environ.items() if value is not None})
    return merged


def resolve_skill_roots(*paths: Path) -> list[str]:
    return [str(path) for path in paths if path.exists()]


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]
