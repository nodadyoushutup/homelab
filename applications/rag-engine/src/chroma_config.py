"""Chroma HTTP endpoint from ``RAG_CHROMA_HOSTNAME`` (``host``, ``host:port``, or ``[ipv6]:port``)."""
from __future__ import annotations

import os

DEFAULT_RAG_CHROMA_HOSTNAME = "chromadb:8000"
DEFAULT_CHROMA_HTTP_PORT = 8000


def parse_chroma_hostname(raw: str | None = None) -> tuple[str, int]:
    value = (
        raw
        if raw is not None
        else (os.getenv("RAG_CHROMA_HOSTNAME") or DEFAULT_RAG_CHROMA_HOSTNAME)
    ).strip()
    if not value:
        value = DEFAULT_RAG_CHROMA_HOSTNAME

    if value.startswith("["):
        closing = value.find("]")
        if closing < 0:
            raise ValueError(f"invalid RAG_CHROMA_HOSTNAME (unclosed '['): {value!r}")
        host = value[1:closing].strip()
        suffix = value[closing + 1 :]
        if suffix == "":
            return host, DEFAULT_CHROMA_HTTP_PORT
        if not suffix.startswith(":"):
            raise ValueError(f"invalid RAG_CHROMA_HOSTNAME after ']': {value!r}")
        return host, int(suffix[1:])

    if ":" in value:
        host, _, port_part = value.rpartition(":")
        if port_part.isdigit():
            return host.strip(), int(port_part)

    return value, DEFAULT_CHROMA_HTTP_PORT


def chroma_hostname_display(raw: str | None = None) -> str:
    host, port = parse_chroma_hostname(raw)
    return f"{host}:{port}"


def chroma_http_client(raw: str | None = None):
    import chromadb

    host, port = parse_chroma_hostname(raw)
    return chromadb.HttpClient(host=host, port=port)
