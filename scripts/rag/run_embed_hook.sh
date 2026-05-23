#!/usr/bin/env bash
# Run rag_embed_event.py for post-commit / post-merge / post-rewrite.
#
# By default the HTTP embed runs fully detached from the hook process (setsid
# when available for commit/merge; subshell + disown for rewrite with stdin) so
# ``git commit`` returns as soon as the hook script exits and is not tied to the
# embed job via process groups / TTY job control. Logs append to
# ``.git/rag-hook.log`` under the repo.
#
# Blocking (old behavior): RAG_HOOK_SYNC=1
# Disabled: RAG_GIT_HOOKS_DISABLED=1 (checked in caller hooks too)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EVENT="${1:?usage: run_embed_hook.sh commit|merge|rewrite}"

[[ -n "${RAG_GIT_HOOKS_DISABLED:-}" ]] && exit 0

LOG="$ROOT/.git/rag-hook.log"
PY="$ROOT/scripts/rag/rag_embed_event.py"

stdin_data=""
if [[ "$EVENT" == "rewrite" ]]; then
  stdin_data=$(cat)
fi

run_python() {
  if [[ "$EVENT" == "rewrite" ]]; then
    printf '%s' "$stdin_data" | python3 "$PY" rewrite
  else
    python3 "$PY" "$EVENT"
  fi
}

if [[ "${RAG_HOOK_SYNC:-}" == "1" ]]; then
  run_python
  exit $?
fi

run_async_logged() {
  set +e
  {
    echo "==== $(date -Iseconds) begin $EVENT (async) ===="
    run_python
    ec=$?
    if [[ "$ec" -eq 0 ]]; then
      echo "==== $(date -Iseconds) end $EVENT ok ===="
    else
      echo "==== $(date -Iseconds) end $EVENT FAILED exit=$ec ===="
    fi
  } >>"$LOG" 2>&1
}

# post-commit / post-merge: new session so the RAG work cannot participate in
# the hook's process group (helps ``git commit && git push`` return quickly).
# post-rewrite keeps stdin piping; setsid would lose the tty pipe.
if [[ "$EVENT" != "rewrite" ]] && command -v setsid >/dev/null 2>&1; then
  if setsid -f true 2>/dev/null; then
    setsid -f env ROOT="$ROOT" LOG="$LOG" PY="$PY" EVENT="$EVENT" bash -c '
set +e
cd "$ROOT" || exit 0
ev="$EVENT"
{
  echo "==== $(date -Iseconds) begin ${ev} (async) ===="
  python3 "$PY" "$ev"
  ec=$?
  if [[ "$ec" -eq 0 ]]; then
    echo "==== $(date -Iseconds) end ${ev} ok ===="
  else
    echo "==== $(date -Iseconds) end ${ev} FAILED exit=$ec ===="
  fi
} >>"$LOG" 2>&1
'
    exit 0
  fi
fi

(
  run_async_logged
) &
disown 2>/dev/null || true
exit 0
