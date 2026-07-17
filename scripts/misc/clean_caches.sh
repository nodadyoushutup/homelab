#!/usr/bin/env bash
# Delete regenerable tooling cache files and directories under the repo.
#
# Targets (directories): __pycache__, .pytest_cache, .mypy_cache, .ruff_cache,
#   .tox, .nox, .cache, .vite, .eslintcache (dir form), *.egg-info
# Targets (files): *.pyc, *.pyo, *.pyd, .eslintcache, *.tsbuildinfo
#
# Does not descend into heavy trees that match root .gitignore (venvs,
# node_modules, build/output dirs, .terraform, coverage, Playwright reports,
# etc.). Those are skipped entirely — not cleaned. For .terraform removal see
# scripts/terraform/remove_dirs.sh.
#
# Usage:
#   scripts/misc/clean_caches.sh              # clean repo root
#   scripts/misc/clean_caches.sh -n           # dry-run (list only)
#   scripts/misc/clean_caches.sh /path/to/dir # clean a subdirectory

set -euo pipefail

DRY_RUN=0
ROOT=""

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROOT" ]]; then
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      ROOT="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT="${ROOT:-$REPO_ROOT}"

if [[ ! -d "$ROOT" ]]; then
  echo "Directory does not exist: $ROOT" >&2
  exit 1
fi

ROOT_PATH="$(cd "$ROOT" && pwd)"

log() {
  printf '[clean-caches] %s\n' "$*"
}

# Directory basenames to skip (aligned with root .gitignore install/build trees).
# Cache targets listed below are still deleted when found under source trees.
PRUNE_NAMES=(
  .git
  .direnv
  .terraform
  node_modules
  .pnpm-store
  .venv
  venv
  .virtualenv
  ENV
  env
  dist
  dist-ssr
  .next
  coverage
  test-results
  playwright-report
  blob-report
  data
  output
  site-packages
)

prune_expr=()
for name in "${PRUNE_NAMES[@]}"; do
  prune_expr+=( -name "$name" -o )
done
# Drop trailing -o
unset 'prune_expr[-1]'

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "scanning (dry-run) under: $ROOT_PATH"
else
  log "scanning and removing under: $ROOT_PATH"
fi

removed=0
# Stream matches as find discovers them so output appears while deleting.
while IFS= read -r -d '' path; do
  [[ -z "$path" ]] && continue
  size="$(du -sh "$path" 2>/dev/null | cut -f1 || echo '?')"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[clean-caches] would remove %s (%s)\n' "$path" "$size"
  else
    printf '[clean-caches] removing %s (%s)\n' "$path" "$size"
    # -v prints each path as it is deleted
    rm -rfv -- "$path"
  fi
  removed=$((removed + 1))
done < <(
  find "$ROOT_PATH" \
    \( "${prune_expr[@]}" \) -prune -o \
    \( \
      -type d \( \
        -name __pycache__ -o \
        -name .pytest_cache -o \
        -name .mypy_cache -o \
        -name .ruff_cache -o \
        -name .tox -o \
        -name .nox -o \
        -name .cache -o \
        -name .vite -o \
        -name .eslintcache -o \
        -name '*.egg-info' \
      \) -print0 -prune \
    \) -o \
    \( \
      -type f \( \
        -name '*.pyc' -o \
        -name '*.pyo' -o \
        -name '*.pyd' -o \
        -name .eslintcache -o \
        -name '*.tsbuildinfo' \
      \) -print0 \
    \) -o \
    -true
)

if [[ "$removed" -eq 0 ]]; then
  log "no cache paths found under: $ROOT_PATH"
elif [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run complete (${removed} path(s) listed)"
else
  log "removed ${removed} path(s)"
fi
