# Corpus layout and ingest

## Curated knowledge files

Put **intentional** reference material (PDFs, office docs, and other binaries you want indexed) under **`docs/knowledge/`**. That tree keeps a tracked layout (typically with `.gitkeep`); large binaries may be gitignored while still present on disk for local ingest.

Repo workflow docs, code under allowed prefixes, and other text sources can also be indexed when they match allowlists and pass exclude rules.

## Allowlists

Ingest eligibility is driven by **repo-relative path prefixes**:

- **`RAG_ALLOWED_PATH_PREFIXES`** — engine ingest allowlist (see `applications/rag-engine/src/rag_engine/pipeline.py`, `_allowed_prefixes`; defaults include **`docs/`** among others).
- **`RAG_HOOK_INCLUDE_PREFIXES`** — git hook filtering should stay aligned (see `.githooks/rag_hook_common.py`).

When you change either, update **`.secrets/.env`** and **`.secrets/.env.example`** together per repository rules.

## What is not auto-ingested

**`mcp-export`** and **`mcp-odoo`** write CSV sinks under **`data/exports/`** only. Those exports are **not** wired to auto-call embed; they are ordinary files unless you explicitly extend ingest to include them (usually you should not without a deliberate corpus decision).

## Excludes and path rules

Binary glob rules, sensitive paths, and other skips are centralized in engine path logic (e.g. `path_rules.py`, `.githooks/rag_path_excludes.py`). If something never appears in the index, check allowlist **and** excludes before debugging embeddings.

## Chunking strategies

Structured chunking (Python, XML/Odoo, Markdown, PDF hybrid, tabular, many other languages) is tracked in the ingest roadmap. That document is the checklist when adding or changing strategies:

- [rag-structured-file-ingest-roadmap.md](../workflows/rag-structured-file-ingest-roadmap.md)

Hook smoke / operator checks:

- [rag-hook-smoke-test.md](../workflows/rag-hook-smoke-test.md)

## Freshness

Index freshness depends on hooks, manual backfill, and any CI you run. If search feels stale after doc edits, re-run the project’s embed path for the affected files (see operator notes in [operators-and-clients.md](operators-and-clients.md) and the ingest roadmap).
