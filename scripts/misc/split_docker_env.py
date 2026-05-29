#!/usr/bin/env python3
"""One-shot: split monolithic .config/docker/.env into split *.env files (hard cut)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCKER_DIR = ROOT / ".config" / "docker"
MONOLITH = DOCKER_DIR / ".env"

LOAD_ORDER = [
    "site.env",
    "shared.env",
    "postgres.env",
    "rag.env",
    "mcp.env",
    "langgraph.env",
    "agents.env",
    "argocd.env",
    "minio.env",
    "qbittorrent.env",
]

SITE_KEYS = {"CONFIG_DIR"}
ARGOCD_PREFIX = "ARGOCD_"
MINIO_PREFIX = "MINIO_"
POSTGRES_PREFIX = "POSTGRES_"
MCP_PREFIXES = ("HOMELAB_MCP_", "MCP_RAG_")
RAG_PREFIXES = ("RAG_",)
AGENTS_KEYS = {
    "CODE_AGENT_URL",
    "CODE_AGENT_GRAPH_ID",
    "CODE_AGENT_ASSISTANT_ID",
    "CODE_AGENT_API_KEY",
    "JIRA_AGENT_URL",
    "JIRA_AGENT_GRAPH_ID",
    "JIRA_AGENT_ASSISTANT_ID",
    "JIRA_AGENT_API_KEY",
}
LANGGRAPH_KEYS = {
    "SUPERVISOR_MODEL",
    "CODE_MODEL",
    "JIRA_MODEL",
    "TECH_LEAD_MODEL",
    "GITHUB_MODEL",
    "CREATE_ISSUE_DEFAULT_PROJECT",
    "LANGSMITH_TRACING",
    "HOMELAB_DISABLE_WORKFLOW_GATES",
    "HOMELAB_MCP_BOOTSTRAP_RETRIES",
    "HOMELAB_MCP_BOOTSTRAP_RETRY_DELAY_SEC",
    "CODE_REPOSITORY_ROOT",
    "TECH_LEAD_REPOSITORY_ROOT",
    "HOMELAB_CONFIG_ENV",
    "HOMELAB_CONFIG_ENV_DIR",
}
SHARED_KEYS = {"OPENAI_API_KEY", "GOOGLE_API_KEY", "VOYAGE_API_KEY"}
QBITTORRENT_KEYS = {
    "QBITTORRENT_BASE_URL",
    "QBITTORRENT_USERNAME",
    "QBITTORRENT_PASSWORD",
    "QBITTORRENT_HOSTS",
    "QBITTORRENT_WAIT_FOR_LOGIN",
    "EXPORTER_HOST",
    "EXPORTER_PORT",
    "ENABLE_HIGH_CARDINALITY",
    "INSECURE_SKIP_VERIFY",
    "HOST",
    "PORT",
    "BACKEND",
    "SCRAPE_INTERVAL",
    "RUST_LOG",
    "STARTUP_DELAY_SECONDS",
    "LOG_LEVEL",
}


def _target_file(key: str) -> str:
    if key in SITE_KEYS:
        return "site.env"
    if key.startswith(ARGOCD_PREFIX):
        return "argocd.env"
    if key.startswith(MINIO_PREFIX):
        return "minio.env"
    if key.startswith(POSTGRES_PREFIX):
        return "postgres.env"
    if key in SHARED_KEYS:
        return "shared.env"
    if any(key.startswith(p) for p in MCP_PREFIXES):
        return "mcp.env"
    if any(key.startswith(p) for p in RAG_PREFIXES):
        return "rag.env"
    if key in AGENTS_KEYS:
        return "agents.env"
    if key in LANGGRAPH_KEYS:
        return "langgraph.env"
    if key in QBITTORRENT_KEYS or key.startswith("QBITTORRENT_"):
        return "qbittorrent.env"
    return "langgraph.env"


def _parse_env(path: Path) -> list[tuple[str | None, str]]:
    """Return list of (comment_block|None, line) preserving comments before assignments."""
    entries: list[tuple[str | None, str]] = []
    comment_buf: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            if comment_buf:
                comment_buf.append("")
            continue
        if stripped.startswith("#"):
            comment_buf.append(line)
            continue
        if "=" not in stripped:
            continue
        key = stripped.split("=", 1)[0].strip()
        comment = "\n".join(comment_buf).rstrip() if comment_buf else None
        comment_buf = []
        entries.append((comment, f"{key}={stripped.split('=', 1)[1]}"))
    if comment_buf:
        entries.append(("\n".join(comment_buf).rstrip(), ""))
    return entries


def main() -> int:
    if not MONOLITH.is_file():
        print(f"No monolithic file at {MONOLITH}; nothing to split.", file=sys.stderr)
        return 0

    buckets: dict[str, list[str]] = {name: [] for name in LOAD_ORDER}
    for comment, assignment in _parse_env(MONOLITH):
        if not assignment:
            continue
        key = assignment.split("=", 1)[0]
        dest = _target_file(key)
        if comment:
            buckets[dest].append(comment)
            buckets[dest].append("")
        buckets[dest].append(assignment)

    for name in LOAD_ORDER:
        out = DOCKER_DIR / name
        lines = buckets[name]
        if not lines:
            if out.exists():
                continue
            continue
        body = "\n".join(lines).strip() + "\n"
        out.write_text(body)
        print(f"Wrote {out}")

    MONOLITH.unlink()
    print(f"Removed {MONOLITH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
