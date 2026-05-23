#!/usr/bin/env bash
# Point this repo at .githooks (thin stubs → scripts/rag/run_embed_hook.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
git config core.hooksPath .githooks
chmod +x .githooks/post-commit .githooks/post-merge .githooks/post-rewrite 2>/dev/null || true
chmod +x scripts/rag/run_embed_hook.sh scripts/rag/rag_embed_event.py scripts/rag/backfill.sh 2>/dev/null || true
echo "core.hooksPath=.githooks"
echo "Hook implementation: scripts/rag/ (run_embed_hook.sh, rag_embed_event.py)"
echo "Set RAG_ENGINE_BASE_URL and RAG_ENGINE_API_KEY in .config/docker/rag.env (hooks) or .config/scripts/rag.env (backfill)."
echo "Disable hooks: export RAG_GIT_HOOKS_DISABLED=1"
echo "Blocking embed (wait for rag-engine): export RAG_HOOK_SYNC=1"
echo "Async embed logs: .git/rag-hook.log (commit/merge use setsid when available)"
