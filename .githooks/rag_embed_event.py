#!/usr/bin/env python3
"""Drive rag-engine ``POST /v1/embed-commit`` from git hook events.

Events:
  commit   — last commit only (``git show``), for normal commits / merge commits / cherry-pick / revert.
  merge    — ``ORIG_HEAD..HEAD`` (fast-forward and merge pulls).
  rewrite  — after amend/rebase; prefers ``ORIG_HEAD..HEAD``, else stdin ``old new`` pairs.

Git invokes ``.githooks/run_embed_hook.sh``, which starts this script in a detached
session (``setsid`` for commit/merge when available) so the hook exits without waiting
for HTTP; output is appended to ``.git/rag-hook.log``.

Disable: ``export RAG_GIT_HOOKS_DISABLED=1``
Blocking (wait for HTTP): ``export RAG_HOOK_SYNC=1``
Strict (fail the hook on HTTP errors): ``export RAG_HOOK_STRICT=1``
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Same directory imports (``core.hooksPath=.githooks``)
_HOOK_DIR = Path(__file__).resolve().parent
if str(_HOOK_DIR) not in sys.path:
    sys.path.insert(0, str(_HOOK_DIR))

import rag_path_excludes as rpe  # noqa: E402

# Default allowlist must match ``pipeline._allowed_prefixes`` when env unset.
_DEFAULT_ALLOWED = "docs/,applications/,kubernetes/,terraform/,scripts/,pipelines/,packer/,AGENTS.md"


def _log(msg: str) -> None:
    print(f"[rag-hook] {msg}", file=sys.stderr)


def _load_dotenv(repo_root: Path) -> None:
    path = repo_root / ".config" / ".env"
    if not path.is_file():
        path = repo_root / ".secrets" / ".env"
    if not path.is_file():
        return
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        _log(f"warning: could not read {path}: {exc}")
        return
    for line in raw.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            continue
        key, _, val = s.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, val)


def _allowed_prefixes() -> list[str]:
    raw = (
        os.getenv("RAG_HOOK_INCLUDE_PREFIXES")
        or os.getenv("RAG_ALLOWED_PATH_PREFIXES")
        or _DEFAULT_ALLOWED
    ).strip()
    out: list[str] = []
    for p in raw.split(","):
        p = p.strip().replace("\\", "/").lstrip("/")
        if p:
            out.append(p)
    return out


def _matches_allowed_prefix(rel_norm: str) -> bool:
    if not rel_norm or ".." in Path(rel_norm).parts:
        return False
    for p in _allowed_prefixes():
        if p.endswith("/"):
            base = p.rstrip("/")
            if rel_norm == base or rel_norm.startswith(base + "/"):
                return True
        elif rel_norm == p:
            return True
    return False


def _should_send(rel_norm: str) -> bool:
    rel_norm = rel_norm.strip().replace("\\", "/").lstrip("/")
    if not _matches_allowed_prefix(rel_norm):
        return False
    if rpe.path_has_excluded_segment(rel_norm):
        return False
    if rpe.file_has_excluded_suffix(rel_norm):
        return False
    return True


def _git_lines(repo: Path, *git_args: str) -> list[str]:
    r = subprocess.run(
        ["git", *git_args],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
        timeout=120,
    )
    if r.returncode != 0:
        _log(f"git {' '.join(git_args)} failed ({r.returncode}): {(r.stderr or '').strip()}")
        return []
    return [ln for ln in (r.stdout or "").splitlines() if ln.strip()]


def _git_ok(repo: Path, *git_args: str) -> bool:
    r = subprocess.run(
        ["git", *git_args],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )
    return r.returncode == 0


def _parse_name_status(lines: list[str]) -> tuple[list[str], list[str]]:
    """Return (paths_to_embed, removed_paths) from ``--name-status`` lines."""
    paths: list[str] = []
    removed: list[str] = []
    seen_p: set[str] = set()
    seen_r: set[str] = set()

    for line in lines:
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status = parts[0].strip()
        if not status:
            continue
        if status == "D":
            p = parts[1].strip().replace("\\", "/").lstrip("/")
            if p and p not in seen_r:
                seen_r.add(p)
                removed.append(p)
            continue
        if status[0] in ("R", "C") and len(parts) >= 3:
            old_p = parts[1].strip().replace("\\", "/").lstrip("/")
            new_p = parts[2].strip().replace("\\", "/").lstrip("/")
            if old_p and old_p not in seen_r:
                seen_r.add(old_p)
                removed.append(old_p)
            if new_p and new_p not in seen_p:
                seen_p.add(new_p)
                paths.append(new_p)
            continue
        if status[0] in ("M", "A", "T"):
            # Skip ``U`` (unmerged) until the conflict commit lands.
            p = parts[1].strip().replace("\\", "/").lstrip("/")
            if p and p not in seen_p:
                seen_p.add(p)
                paths.append(p)
            continue
        # Ignore other statuses (e.g. broken)
    return paths, removed


def _filter(paths: list[str], removed: list[str]) -> tuple[list[str], list[str]]:
    fp = sorted({p for p in paths if _should_send(p)})
    fr = sorted({p for p in removed if _should_send(p)})
    return fp, fr


def _post_embed(repo: Path, commit: str, paths: list[str], removed_paths: list[str]) -> int:
    base = (os.getenv("RAG_ENGINE_BASE_URL") or "").strip().rstrip("/")
    if not base:
        _log("RAG_ENGINE_BASE_URL is unset; skipping embed (set in .config/docker/rag.env)")
        return 0

    url = f"{base}/v1/embed-commit"
    body = json.dumps(
        {"commit": commit, "paths": paths, "removed_paths": removed_paths},
        separators=(",", ":"),
    ).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    key = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if key:
        req.add_header("x-api-key", key)

    timeout = 300.0
    try:
        raw_t = (os.getenv("RAG_HOOK_HTTP_TIMEOUT_SEC") or "").strip()
        if raw_t:
            timeout = float(raw_t)
    except ValueError:
        pass

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            _ = resp.read()
            if resp.status != 200:
                _log(f"unexpected HTTP {resp.status} from {url}")
                return 1 if os.getenv("RAG_HOOK_STRICT") == "1" else 0
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:500]
        except OSError:
            pass
        _log(f"HTTP {exc.code} from embed-commit: {detail or exc.reason}")
        return 1 if os.getenv("RAG_HOOK_STRICT") == "1" else 0
    except urllib.error.URLError as exc:
        _log(f"request failed: {exc.reason}")
        return 1 if os.getenv("RAG_HOOK_STRICT") == "1" else 0
    except OSError as exc:
        _log(f"request failed: {exc}")
        return 1 if os.getenv("RAG_HOOK_STRICT") == "1" else 0

    _log(f"embed-commit ok commit={commit[:12]} paths={len(paths)} removed={len(removed_paths)}")
    return 0


def _head_sha(repo: Path) -> str:
    lines = _git_lines(repo, "rev-parse", "HEAD")
    return lines[0].strip() if lines else ""


def _run_commit(repo: Path) -> int:
    sha = _head_sha(repo)
    if not sha:
        return 0
    lines = _git_lines(repo, "show", "--pretty=format:", "--name-status", "HEAD")
    paths, removed = _parse_name_status(lines)
    paths, removed = _filter(paths, removed)
    if not paths and not removed:
        return 0
    return _post_embed(repo, sha, paths, removed)


def _run_merge(repo: Path) -> int:
    if not _git_ok(repo, "rev-parse", "--verify", "ORIG_HEAD"):
        _log("no ORIG_HEAD; skipping merge hook (nothing to diff)")
        return 0
    sha = _head_sha(repo)
    if not sha:
        return 0
    lines = _git_lines(repo, "diff", "--name-status", "ORIG_HEAD", "HEAD")
    paths, removed = _parse_name_status(lines)
    paths, removed = _filter(paths, removed)
    if not paths and not removed:
        return 0
    return _post_embed(repo, sha, paths, removed)


def _run_rewrite(repo: Path, stdin_text: str) -> int:
    sha = _head_sha(repo)
    if not sha:
        return 0
    paths_acc: list[str] = []
    removed_acc: list[str] = []

    if _git_ok(repo, "rev-parse", "--verify", "ORIG_HEAD"):
        lines = _git_lines(repo, "diff", "--name-status", "ORIG_HEAD", "HEAD")
        p, r = _parse_name_status(lines)
        paths_acc.extend(p)
        removed_acc.extend(r)
    else:
        for line in stdin_text.splitlines():
            parts = line.split()
            if len(parts) < 2:
                continue
            old_s, new_s = parts[0], parts[1]
            if old_s == new_s:
                continue
            lines = _git_lines(repo, "diff", "--name-status", old_s, new_s)
            p, r = _parse_name_status(lines)
            paths_acc.extend(p)
            removed_acc.extend(r)

    paths, removed = _filter(paths_acc, removed_acc)
    if not paths and not removed:
        return 0
    return _post_embed(repo, sha, paths, removed)


def main(argv: list[str]) -> int:
    if os.getenv("RAG_GIT_HOOKS_DISABLED", "").strip() in ("1", "true", "yes"):
        return 0

    repo = Path(__file__).resolve().parent.parent
    _load_dotenv(repo)
    os.chdir(repo)

    if len(argv) < 2:
        _log("usage: rag_embed_event.py {commit|merge|rewrite}")
        return 0

    kind = argv[1].strip().lower()
    if kind == "commit":
        return _run_commit(repo)
    if kind == "merge":
        return _run_merge(repo)
    if kind == "rewrite":
        stdin_text = sys.stdin.read()
        return _run_rewrite(repo, stdin_text)

    _log(f"unknown event {kind!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
