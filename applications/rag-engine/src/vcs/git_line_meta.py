"""Git last-touch metadata for RAG chunks (commit hash, author, committer timestamp).

Line-range queries use ``git log -L`` against the workspace repo. For chunk kinds whose
``start_line``/``end_line`` are not source file lines (PDF pages, tabular row indices,
office extracts), we fall back to the latest commit touching the file path.
"""
from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

GIT_LINE_META_VERSION = 1

_LANGUAGES_LINE_RANGE_SKIP = frozenset(
    {"pdf", "docx", "pptx", "odt", "csv", "xlsx"},
)


def _git_timeout_sec() -> int:
    try:
        return max(5, int(os.getenv("RAG_GIT_LOG_TIMEOUT_SEC", "30").strip()))
    except ValueError:
        return 30


def line_range_git_applicable(language: str) -> bool:
    """True when chunk line numbers refer to lines in the indexed text file on disk."""
    return (language or "").strip().lower() not in _LANGUAGES_LINE_RANGE_SKIP


def path_tracked_in_git(repo: Path, rel_path: str) -> bool:
    rel = rel_path.replace("\\", "/").lstrip("/")
    if not rel or ".." in Path(rel).parts:
        return False
    proc = subprocess.run(
        ["git", "-c", "safe.directory=*", "ls-files", "--error-unmatch", "--", rel],
        cwd=str(repo.resolve()),
        capture_output=True,
        text=True,
        timeout=_git_timeout_sec(),
    )
    return proc.returncode == 0


def _parse_format_output(stdout: str) -> dict[str, str] | None:
    raw = (stdout or "").strip()
    if not raw:
        return None
    parts = raw.split("\x00", 2)
    if len(parts) != 3:
        return None
    sha, author, ts = parts[0].strip(), parts[1].strip(), parts[2].strip()
    if not sha:
        return None
    return {
        "git_last_commit": sha,
        "git_last_author": author,
        "git_last_timestamp": ts,
    }


def last_commit_touching_file(repo: Path, rel_path: str) -> dict[str, str] | None:
    """Latest commit that touched ``rel_path`` (any line)."""
    rel = rel_path.replace("\\", "/").lstrip("/")
    proc = subprocess.run(
        [
            "git",
            "-c",
            "safe.directory=*",
            "log",
            "-1",
            "--format=%H%x00%an%x00%cI",
            "--no-patch",
            "--",
            rel,
        ],
        cwd=str(repo.resolve()),
        capture_output=True,
        text=True,
        timeout=_git_timeout_sec(),
    )
    if proc.returncode != 0:
        return None
    return _parse_format_output(proc.stdout)


def last_commit_touching_line_range(
    repo: Path, rel_path: str, start_line: int, end_line: int
) -> dict[str, str] | None:
    """Latest commit affecting any line in ``[start_line, end_line]`` (1-based, inclusive)."""
    rel = rel_path.replace("\\", "/").lstrip("/")
    if start_line < 1 or end_line < start_line:
        return None
    spec = f"{start_line},{end_line}:{rel}"
    proc = subprocess.run(
        [
            "git",
            "-c",
            "safe.directory=*",
            "log",
            "-L",
            spec,
            "-1",
            "--format=%H%x00%an%x00%cI",
            "--no-patch",
        ],
        cwd=str(repo.resolve()),
        capture_output=True,
        text=True,
        timeout=_git_timeout_sec(),
    )
    if proc.returncode != 0:
        if proc.stderr:
            log.debug("git log -L failed for %s %s: %s", rel, spec, proc.stderr.strip()[:500])
        return None
    return _parse_format_output(proc.stdout)


def enrich_chunk_git_metadata(
    repo: Path,
    rel_norm: str,
    structured: list[Any] | None,
    metas_extra: list[dict[str, Any]],
    *,
    eff_strategy: str,
) -> None:
    """Attach git last-touch keys to each ``metas_extra`` row when the repo is available."""
    if not metas_extra:
        return
    root = repo.resolve()
    try:
        tracked = path_tracked_in_git(root, rel_norm)
    except (OSError, subprocess.SubprocessError) as exc:
        log.debug("git track check skipped for %s: %s", rel_norm, exc)
        return
    if not tracked:
        return

    file_cache: dict[str, str] | None = None

    def _file_level() -> dict[str, str]:
        nonlocal file_cache
        if file_cache is None:
            file_cache = last_commit_touching_file(root, rel_norm) or {}
        return file_cache

    if structured is None or eff_strategy == "char":
        fl = _file_level()
        if not fl:
            return
        for ex in metas_extra:
            ex.update(fl)
        return

    for i, ch in enumerate(structured):
        if i >= len(metas_extra):
            break
        lang = getattr(ch, "language", "") or ""
        start = int(getattr(ch, "start_line", 0) or 0)
        end = int(getattr(ch, "end_line", 0) or 0)
        if line_range_git_applicable(lang):
            span = last_commit_touching_line_range(root, rel_norm, start, end)
            if span:
                metas_extra[i].update(span)
            else:
                metas_extra[i].update(_file_level())
        else:
            metas_extra[i].update(_file_level())
