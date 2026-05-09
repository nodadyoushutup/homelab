"""Top-level–oriented chunking for languages without PyPI tree-sitter bindings (regex / line anchors)."""
from __future__ import annotations

import re
from typing import Any

from rag_worker.structured_chunks import _split_oversized

_DART_START = re.compile(
    r"(?m)^(?:@[^\n]+\n(?:\s*@[^\n]+\n)*)?"
    r"(?:(?:abstract|sealed|base|interface|final)\s+)*(?:class|enum|mixin|extension|typedef)\b",
)
_DART_FN = re.compile(
    r"(?m)^(?:@\w+(?:\([^)]*\))?\s*)*(?:async\s+)?(?:void|[\w.<>?,\[\]]+)\s+(\w+)\s*\([^)]*\)\s*(?:async\s*)?(?:=>|\{)",
)

_CLOJURE_START = re.compile(
    r"(?m)^[\s]*\((?:defn|defmacro|defn-|defmulti|defprotocol|defrecord|deftype|ns)\b",
)

_FSHARP_START = re.compile(
    r"(?m)(?:^(?:\s*\[\<[^\]]+\>\]\s*)*(?:module|type|let\s+rec|let\s+inline|let\s+mutable|let\s+val|let)\s+)"
    r"|(?:^\s*member\s+(?:inline\s+)?)",
)

_VB_START = re.compile(
    r"(?m)(?:^\s*(?:Public|Private|Friend|Protected)?\s*(?:MustInherit|NotInheritable|Partial)?\s*"
    r"(?:Class|Module|Interface|Structure|Enum)\s+\w+)"
    r"|(?:^\s*(?:Public|Private|Friend|Protected)?\s*(?:Overrides|Overloads|Async)?\s*(?:Sub|Function)\s+\w+)",
)


def _chunks_from_starts(
    rel_path: str,
    source: str,
    *,
    language_label: str,
    chunk_kind: str,
    pattern: re.Pattern[str],
    max_chars: int,
    overlap: int,
) -> list[Any]:
    if not source.strip():
        return []
    matches = list(pattern.finditer(source))
    if not matches:
        hdr_kw: dict[str, Any] = {}
        return _split_oversized(
            rel_path,
            language_label,
            f"{chunk_kind}_file",
            "file",
            source.strip() + "\n",
            1,
            max_chars=max_chars,
            overlap=overlap,
            header_kwargs=hdr_kw,
        )
    starts = [m.start() for m in matches]
    if starts[0] > 0:
        starts.insert(0, 0)
    out: list[Any] = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(source)
        body = source[start:end].strip()
        if not body:
            continue
        line = source.count("\n", 0, start) + 1
        sym = body.splitlines()[0].strip()[:160] if body else f"unit{i}"
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                language_label,
                chunk_kind,
                sym,
                body + "\n",
                line,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_dart(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[Any]:
    if not source.strip():
        return []
    starts = sorted(set(m.start() for m in _DART_START.finditer(source)) | set(m.start() for m in _DART_FN.finditer(source)))
    if not starts:
        hdr_kw: dict[str, Any] = {}
        return _split_oversized(
            rel_path,
            "dart",
            "dart_file",
            "file",
            source.strip() + "\n",
            1,
            max_chars=max_chars,
            overlap=overlap,
            header_kwargs=hdr_kw,
        )
    if starts[0] > 0:
        starts.insert(0, 0)
    out: list[Any] = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(source)
        body = source[start:end].strip()
        if not body:
            continue
        line = source.count("\n", 0, start) + 1
        sym = body.splitlines()[0].strip()[:160] if body else f"unit{i}"
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                "dart",
                "dart_unit",
                sym,
                body + "\n",
                line,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_clojure(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[Any]:
    return _chunks_from_starts(
        rel_path,
        source,
        language_label="clojure",
        chunk_kind="clojure_form",
        pattern=_CLOJURE_START,
        max_chars=max_chars,
        overlap=overlap,
    )


def chunks_fsharp(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[Any]:
    return _chunks_from_starts(
        rel_path,
        source,
        language_label="fsharp",
        chunk_kind="fsharp_decl",
        pattern=_FSHARP_START,
        max_chars=max_chars,
        overlap=overlap,
    )


def chunks_vbnet(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[Any]:
    return _chunks_from_starts(
        rel_path,
        source,
        language_label="vbnet",
        chunk_kind="vb_decl",
        pattern=_VB_START,
        max_chars=max_chars,
        overlap=overlap,
    )
