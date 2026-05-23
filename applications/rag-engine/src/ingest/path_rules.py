"""Path allow/exclude rules for RAG indexing (virtualenvs, package trees, caches)."""
from __future__ import annotations

import os
from pathlib import Path

DEFAULT_RAG_PATHS_DISALLOWED = (
    "node_modules,.venv,venv,virtualenv,pipenv,__pycache__,.pytest_cache,.mypy_cache,"
    ".ruff_cache,.tox,.nox,site-packages,.adk,dist,build,.next,.nuxt,target,vendor,"
    "htmlcov,.eggs,.npm,.yarn,.pnpm-store,__MACOSX,.cache,coverage,"
    "odoo-base,.tx,i18n,.terraform,output,keys,"
    ".langgraph_api,.runtime,.config,.vite,.git,.direnv,.cursor,.vscode,.codex,.secrets,"
    ".github,.idea,.claude,.continue,.specstory,.fleet,.zed,"
    "playwright-report,test-results,blob-report"
)


def load_disallowed_segments() -> frozenset[str]:
    """Path segment names skipped even under ``RAG_PATHS_ALLOWED`` (``RAG_PATHS_DISALLOWED``)."""
    raw = (os.getenv("RAG_PATHS_DISALLOWED") or DEFAULT_RAG_PATHS_DISALLOWED).strip()
    parts = [x.strip() for x in raw.split(",") if x.strip()]
    return frozenset(parts)


def path_has_disallowed_segment(rel_norm: str, segments: frozenset[str] | None = None) -> bool:
    """True if any path component matches a disallowed directory name (case-insensitive)."""
    segs = segments if segments is not None else load_disallowed_segments()
    lowered = {s.lower() for s in segs}
    for part in Path(rel_norm).parts:
        if part.lower() in lowered:
            return True
        if part.endswith(".egg-info"):
            return True
    return False


def load_ignored_extensions() -> tuple[str, ...]:
    """File suffixes to skip; set ``RAG_EXTENSIONS_IGNORE`` (comma-separated, optional leading dot)."""
    raw = (os.getenv("RAG_EXTENSIONS_IGNORE") or "").strip()
    out: list[str] = []
    for p in raw.split(","):
        p = p.strip().lower()
        if not p:
            continue
        if not p.startswith("."):
            p = f".{p}"
        out.append(p)
    return tuple(out)


def file_has_excluded_suffix(rel_norm: str, suffixes: tuple[str, ...] | None = None) -> bool:
    low = rel_norm.lower()
    for suf in suffixes if suffixes is not None else load_ignored_extensions():
        if low.endswith(suf):
            return True
    return False
