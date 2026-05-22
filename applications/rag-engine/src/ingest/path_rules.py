"""Path allow/exclude rules for RAG indexing (virtualenvs, package trees, caches)."""
from __future__ import annotations

import os
from pathlib import Path

# Keep in sync with `.githooks/rag_path_excludes.py` defaults.
DEFAULT_RAG_EXCLUDE_PATH_SEGMENTS = (
    "node_modules,.venv,venv,virtualenv,pipenv,__pycache__,.pytest_cache,.mypy_cache,"
    ".ruff_cache,.tox,.nox,site-packages,.adk,dist,build,.next,.nuxt,target,vendor,"
    "htmlcov,.eggs,.npm,.yarn,.pnpm-store,__MACOSX,.cache,coverage,"
    "odoo-base,.tx,i18n,.terraform,output,keys"
)

# Minified/vendor/binary, raster image, video, and audio suffixes (comma-separated, leading dot).
# Sync `.githooks/rag_path_excludes.py`.
DEFAULT_RAG_EXCLUDE_FILE_SUFFIXES = (
    ".min.js,.map,.deb,.woff,.woff2,.ttf,.eot,.ico,.dll,.so,.dylib,"
    ".png,.jpg,.jpeg,.gif,.webp,.bmp,.tif,.tiff,.heic,.heif,.avif,.jxl,.jfif,.apng,"
    ".ppm,.pgm,.pbm,.dds,.exr,.hdr,.ktx,.ktx2,"
    ".mp4,.m4v,.mov,.avi,.mkv,.webm,.wmv,.flv,.f4v,.ogv,.mpeg,.mpg,.m2ts,.mts,.ts,.3gp,.3g2,.asf,"
    ".mp3,.wav,.flac,.aac,.m4a,.ogg,.oga,.opus,.wma,.aiff,.aif,.alac,.mid,.midi,.amr,"
    ".tfstate,.tfstate.backup,.tfplan"
)


def load_exclude_segments() -> frozenset[str]:
    """Excluded path segment names; override with RAG_EXCLUDE_PATH_SEGMENTS when needed."""
    raw = (os.getenv("RAG_EXCLUDE_PATH_SEGMENTS") or DEFAULT_RAG_EXCLUDE_PATH_SEGMENTS).strip()
    parts = [x.strip() for x in raw.split(",") if x.strip()]
    return frozenset(parts)


def path_has_excluded_segment(rel_norm: str, segments: frozenset[str] | None = None) -> bool:
    """True if any path component matches an excluded directory name (case-insensitive)."""
    segs = segments if segments is not None else load_exclude_segments()
    lowered = {s.lower() for s in segs}
    for part in Path(rel_norm).parts:
        if part.lower() in lowered:
            return True
        if part.endswith(".egg-info"):
            return True
    return False


def load_exclude_suffixes() -> tuple[str, ...]:
    """Excluded file suffixes; override with RAG_EXCLUDE_FILE_SUFFIXES when needed."""
    raw = (os.getenv("RAG_EXCLUDE_FILE_SUFFIXES") or DEFAULT_RAG_EXCLUDE_FILE_SUFFIXES).strip()
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
    for suf in suffixes if suffixes is not None else load_exclude_suffixes():
        if low.endswith(suf):
            return True
    return False
