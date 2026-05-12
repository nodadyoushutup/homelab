#!/usr/bin/env bash
# Point this repo at .githooks (post-commit / post-merge / post-rewrite → rag-engine).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
git config core.hooksPath .githooks
chmod +x .githooks/post-commit .githooks/post-merge .githooks/post-rewrite .githooks/run_embed_hook.sh .githooks/rag_embed_event.py 2>/dev/null || true
echo "core.hooksPath=.githooks"
echo "Set RAG_ENGINE_BASE_URL and RAG_ENGINE_API_KEY in .secrets/.env (see .secrets/.env.example)."
echo "Disable hooks: export RAG_GIT_HOOKS_DISABLED=1"
echo "Blocking embed (wait for rag-engine): export RAG_HOOK_SYNC=1"
echo "Async embed logs: .git/rag-hook.log (commit/merge use setsid when available)"
