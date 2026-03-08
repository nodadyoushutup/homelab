#!/usr/bin/env bash
# SSH CA connectivity spot-check: full matrix between machines plus dev<->machines with readable output.

set -euo pipefail

SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}
check_keys=true
machines=()

usage() {
  cat <<'EOF'
Usage: ssh_ca_matrix_check.sh [options] [machine ...]

Options:
  -k, --check-keys      Verify host key uniqueness and cert IDs (default).
  -K, --no-check-keys   Skip host key/cert verification.
  -h, --help            Show this help.

Machines default to the swarm nodes when none are provided.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -k|--check-keys) check_keys=true ;;
    -K|--no-check-keys) check_keys=false ;;
    -h|--help) usage; exit 0 ;;
    *) machines+=("$1") ;;
  esac
  shift
done

if [ "${#machines[@]}" -eq 0 ]; then
  machines=(swarm-cp-0.internal swarm-wk-0.internal swarm-wk-1.internal swarm-wk-2.internal swarm-wk-3.internal)
fi

# Colors (fallback to plain if tput is unavailable or not a TTY).
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); RESET=$(tput sgr0)
  GREEN=$(tput setaf 2); RED=$(tput setaf 1); CYAN=$(tput setaf 6)
else
  BOLD=; RESET=; GREEN=; RED=; CYAN=
fi

ok="${GREEN}[OK]${RESET}"
fail="${RED}[FAIL]${RESET}"

print_section() {
  echo
  printf "%s==> %s%s\n" "$BOLD" "$1" "$RESET"
  printf "%s\n" "------------------------------------------------------------"
}

ok_count=0
fail_count=0

run_check() {
  local label="$1"; shift
  if eval "$@" >/dev/null 2>&1; then
    printf "%-45s %s\n" "$label" "$ok"
    ok_count=$((ok_count + 1))
  else
    printf "%-45s %s\n" "$label" "$fail"
    fail_count=$((fail_count + 1))
  fi
}

dev_host=$(hostname -f 2>/dev/null || hostname)
# Ensure the dev host uses the internal FQDN for consistency.
case "$dev_host" in
  *.internal) ;;
  *) dev_host="${dev_host}.internal" ;;
esac

echo "${BOLD}SSH CA connectivity check${RESET}"
echo "Machines: ${machines[*]}"
echo "Dev host: $dev_host"
echo "SSH_OPTS: $SSH_OPTS"
echo "Host key check: $([ "$check_keys" = true ] && echo enabled || echo skipped)"

print_section "Matrix (machine -> machine)"
for src in "${machines[@]}"; do
  for dst in "${machines[@]}"; do
    run_check "$src -> $dst" "ssh $SSH_OPTS \"$src\" \"ssh -o StrictHostKeyChecking=accept-new $dst hostname\""
  done
done

print_section "Dev -> machines"
for dst in "${machines[@]}"; do
  run_check "$dev_host -> $dst" "ssh $SSH_OPTS \"$dst\" hostname"
done

print_section "Machines -> dev"
for src in "${machines[@]}"; do
  run_check "$src -> $dev_host" "ssh $SSH_OPTS \"$src\" \"ssh -o StrictHostKeyChecking=accept-new $dev_host hostname\""
done

if [ "$check_keys" = true ]; then
  print_section "Host key uniqueness and cert sanity"
  declare -A fp_to_hosts
  # Temporarily disable -e so a single bad host does not abort the script.
  set +e
  for node in "${machines[@]}"; do
    pubkey=$(ssh $SSH_OPTS "$node" "cat /etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null)
    if [ -z "$pubkey" ]; then
      printf "%-45s %s (cannot read host key pub)\n" "$node host key" "$fail"
      fail_count=$((fail_count + 1))
      continue
    fi
    fp_line=$(ssh-keygen -lf /dev/stdin <<<"$pubkey" 2>/dev/null)
    if [ -z "$fp_line" ]; then
      printf "%-45s %s (cannot fingerprint host key)\n" "$node host key" "$fail"
      fail_count=$((fail_count + 1))
      continue
    fi
    fp=$(printf '%s\n' "$fp_line" | awk '{print $2}')
    printf "%-45s %s\n" "$node host key" "$ok"
    if [ -n "$fp" ]; then
      existing="${fp_to_hosts[$fp]:-}"
      fp_to_hosts["$fp"]="$existing $node"
    fi

    cert_info=$(ssh $SSH_OPTS "$node" "ssh-keygen -Lf /etc/ssh/ssh_host_ed25519_key-cert.pub" 2>/dev/null)
    if [ -z "$cert_info" ]; then
      printf "%-45s %s (missing or unreadable host cert)\n" "$node host cert" "$fail"
      fail_count=$((fail_count + 1))
      continue
    fi

    key_id=$(printf '%s\n' "$cert_info" | awk -F': ' '/Key ID/ {print $2; exit}')
    principals=$(printf '%s\n' "$cert_info" | awk '/Principals:/ {p=1; next} p && /^[[:space:]]/ {gsub(/^[[:space:]]+/, "", $0); print} p && !/^[[:space:]]/ {exit}')
    short_node=${node%%.internal}

    cert_ok=true
    msg_parts=()

    if [ -n "$key_id" ] && [[ "$key_id" != *"$short_node"* && "$key_id" != *"$node"* ]]; then
      cert_ok=false
      msg_parts+=("unexpected Key ID: $key_id")
    fi

    principal_match=false
    while IFS= read -r principal; do
      [ -z "$principal" ] && continue
      if [ "$principal" = "$node" ] || [ "$principal" = "$short_node" ]; then
        principal_match=true
      fi
    done <<<"$principals"
    if [ "$principal_match" = false ]; then
      cert_ok=false
      msg_parts+=("missing principal for $node/$short_node")
    fi

    if [ "$cert_ok" = true ]; then
      printf "%-45s %s\n" "$node host cert" "$ok"
    else
      printf "%-45s %s (%s)\n" "$node host cert" "$fail" "$(IFS='; '; echo "${msg_parts[*]}")"
      fail_count=$((fail_count + 1))
    fi
  done
  set -e

  dup_found=0
  for fp in "${!fp_to_hosts[@]}"; do
    # Trim leading space from the host list.
    hosts="${fp_to_hosts[$fp]# }"
    # Count hosts sharing the same fingerprint.
    count=$(printf '%s\n' "$hosts" | wc -w | tr -d ' ')
    if [ "$count" -gt 1 ]; then
      dup_found=1
      fail_count=$((fail_count + 1))
      printf "%-45s %s (shared by: %s)\n" "Duplicate host key $fp" "$fail" "$hosts"
    fi
  done
  if [ "$dup_found" -eq 0 ]; then
    echo "Host key fingerprints are unique across provided machines."
  fi
fi

echo
printf "%sSummary:%s %sok=%d%s, %sfail=%d%s\n" "$BOLD" "$RESET" "$GREEN" "$ok_count" "$RESET" "$RED" "$fail_count" "$RESET"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
