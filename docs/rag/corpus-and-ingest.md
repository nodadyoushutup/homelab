# Corpus layout and ingest

## Curated knowledge files

Put **intentional** reference material (PDFs, office docs, and other binaries you want indexed) under **`docs/knowledge/`**. That tree keeps a tracked layout (typically with `.gitkeep`); large binaries may be gitignored while still present on disk for local ingest.

Repo workflow docs, code under allowed prefixes, and other text sources can also be indexed when they match allowlists and pass exclude rules.

## Allowlists

Ingest eligibility is driven by **repo-relative path prefixes**:

- **`RAG_PATHS_ALLOWED`** — engine ingest allowlist (see `applications/rag-engine/src/ingest/pipeline.py`, `_allowed_prefixes`). Set in Swarm **`env`** / **`.config/docker/rag.env`**; no in-app default.
- **`RAG_HOOK_INCLUDE_PREFIXES`** — git hook filtering (see `scripts/rag/rag_embed_event.py`; align with engine allowlist).

When you change either, update **`.config/docker/rag.env`** and **`.config/docker/rag.env.example`** together per repository rules.

## Disallowed path segments

Even when a file is under **`RAG_PATHS_ALLOWED`**, ingest skips it if any **directory component** of the repo-relative path matches **`RAG_PATHS_DISALLOWED`** (comma-separated segment names, case-insensitive). Examples: `applications/foo/node_modules/bar.py` is skipped because `node_modules` appears in the path; `applications/foo/.venv/lib/x.py` is skipped for `.venv`.

Set the list in Swarm **`env`** / **`.config/docker/rag.env`**. When unset locally, the engine falls back to built-in defaults (virtualenvs, package caches, build output, `.terraform`, etc.) — see **`applications/rag-engine/src/ingest/path_rules.py`**.

## What is not auto-ingested

**`mcp-export`** and **`mcp-odoo`** write CSV sinks under **`data/exports/`** only. Those exports are **not** wired to auto-call embed; they are ordinary files unless you explicitly extend ingest to include them (usually you should not without a deliberate corpus decision).

## Excludes and path rules

Binary glob rules, sensitive paths, and other skips are centralized in engine path logic (`applications/rag-engine/src/ingest/path_rules.py`, mirrored in `scripts/rag/rag_path_excludes.py`). Set **`RAG_EXTENSIONS_IGNORE`** (comma-separated file suffixes) in Swarm **`env`** / **`.config/docker/rag.env`** for extension skips; there is no in-app default list. Set **`RAG_PATHS_DISALLOWED`** (comma-separated directory segment names such as `node_modules`, `.venv`, `__pycache__`) to skip paths even when they sit under **`RAG_PATHS_ALLOWED`**; when unset, the engine uses built-in defaults (same list in **`app.tfvars`**). If something never appears in the index, check allowlist **and** disallowed segments before debugging embeddings.

## Chunking strategies

Structured chunking (Python, XML/Odoo, Markdown, PDF hybrid, tabular, many other languages) is tracked in the ingest roadmap. That document is the checklist when adding or changing strategies:

- [rag-structured-file-ingest-roadmap.md](../workflows/rag-structured-file-ingest-roadmap.md)

Hook smoke / operator checks:

- [rag-hook-smoke-test.md](../workflows/rag-hook-smoke-test.md)

## Freshness

Index freshness depends on hooks, manual backfill, and any CI you run. If search feels stale after doc edits, re-run the project’s embed path for the affected files (see operator notes in [operators-and-clients.md](operators-and-clients.md) and the ingest roadmap).
