"""Small HCL string helpers shared by the tfvars-generating config modules.

python-hcl2 (v8+) returns quoted string literals verbatim - surrounding double
quotes preserved and inner escapes left intact (e.g. ``'"root@pam"'`` or
``'"p@ss\\"word"'``). :func:`coerce_str` reverses that so values roundtrip
unchanged, and :func:`hcl_escape` produces the matching escaped literal body.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def hcl_escape(value: object) -> str:
    """Escape ``\\`` and ``"`` for embedding inside an HCL double-quoted string."""
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def hcl_unescape(text: str) -> str:
    """Reverse the ``\\`` / ``"`` escaping applied by :func:`hcl_escape`."""
    out: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text) and text[i + 1] in ('"', "\\"):
            out.append(text[i + 1])
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def coerce_str(value: object) -> str:
    """Coerce a parsed tfvars value to a plain string.

    Strips a single surrounding quote pair (python-hcl2 preserves them) and
    undoes HCL escaping so values with ``"`` or ``\\`` roundtrip unchanged.
    """
    text = "" if value is None else str(value)
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        return hcl_unescape(text[1:-1])
    return text


def coerce_bool(value: object, *, default: bool) -> bool:
    """Coerce a parsed tfvars / JSON value to a bool, falling back to ``default``."""
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = str(value).strip().strip('"').lower()
    if text in ("true", "1", "yes", "on"):
        return True
    if text in ("false", "0", "no", "off"):
        return False
    return default


def atomic_write(path: Path, content: str) -> Path:
    """Write ``content`` to ``path`` atomically (temp file + ``os.replace``).

    A concurrent reader (e.g. the drift watcher) never observes a partially
    written file and reports a spurious out-of-band change.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise
    return path


__all__ = [
    "atomic_write",
    "coerce_bool",
    "coerce_str",
    "hcl_escape",
    "hcl_unescape",
]
