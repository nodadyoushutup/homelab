#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
ROOT_PATH="$(realpath "$ROOT" 2>/dev/null || echo "$ROOT")"

echo "Scanning for .terraform directories under: $ROOT_PATH"

if [[ ! -d "$ROOT" ]]; then
  echo "Directory '$ROOT' does not exist." >&2
  exit 1
fi

mapfile -t TF_DIRS < <(find "$ROOT" -type d -name '.terraform' -prune -print)

if [[ ${#TF_DIRS[@]} -eq 0 ]]; then
  echo "No .terraform directories found under '$ROOT'."
  exit 0
fi

echo "Found ${#TF_DIRS[@]} .terraform director$( [[ ${#TF_DIRS[@]} -eq 1 ]] && echo "y" || echo "ies" ):"
for dir in "${TF_DIRS[@]}"; do
  size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
  [[ -z "$size" ]] && size="?"
  echo " - $dir (size: $size)"
done

for dir in "${TF_DIRS[@]}"; do
  echo "Removing $dir"
  rm -rfv "$dir"
done

echo "Removed ${#TF_DIRS[@]} .terraform director$( [[ ${#TF_DIRS[@]} -eq 1 ]] && echo "y" || echo "ies" )."
