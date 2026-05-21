"""Per-invocation repository root for parallel agent lanes.

LangGraph clients pass ``homelab_code_repository_root`` in
``RunnableConfig["configurable"]``. Middleware copies it into a contextvar before
MCP-backed tools run so each thread can target its own Git worktree without
separate LangGraph deployments.
"""

from __future__ import annotations

import contextvars
from pathlib import Path
from typing import Any

from framework.configuration import default_repo_root

_code_repository_root_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "homelab_code_repository_root", default=None
)


def effective_code_repository_root(static_fallback: Path) -> Path:
    """Resolve repo root for path normalization; configurable overrides static agent default."""
    raw = _code_repository_root_var.get(None)
    if not raw or not str(raw).strip():
        return static_fallback.expanduser().resolve()

    path = Path(str(raw).strip()).expanduser()
    if path.is_absolute():
        return path.resolve()
    return (default_repo_root() / path).resolve()


def bind_from_configurable(configurable: dict[str, Any] | None) -> list[tuple[contextvars.Token[Any], contextvars.ContextVar[Any]]]:
    """Apply configurable keys; return tokens for reset (reverse order to reset)."""
    if not configurable:
        return []
    tokens: list[tuple[contextvars.Token[Any], contextvars.ContextVar[Any]]] = []

    root = configurable.get("homelab_code_repository_root") or configurable.get(
        "HOMELAB_CODE_REPOSITORY_ROOT"
    )
    if root is not None and str(root).strip():
        tokens.append((_code_repository_root_var.set(str(root).strip()), _code_repository_root_var))

    return tokens


def reset_tokens(tokens: list[tuple[contextvars.Token[Any], contextvars.ContextVar[Any]]]) -> None:
    for token, var in reversed(tokens):
        var.reset(token)
