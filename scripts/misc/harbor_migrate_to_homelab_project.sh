#!/usr/bin/env bash
# Copy Harbor images from per-service projects into the shared `homelab` project.
# Repository names follow `homelab/<service>` (same as `harbor.../<project>/<project>` → `<project>`).
# Skips `library` and `homelab`. Copies per tag (works when `latest` is missing).
#
# Requires: skopeo, curl, python3
# Credentials: export HARBOR_URL, HARBOR_USER, HARBOR_PASS (and optional HARBOR_INSECURE=1),
# or pass --tfvars (default: ${TFVARS_HOME_DIR:-/mnt/eapp/config}/harbor/config.tfvars).
#
# Usage:
#   ./scripts/misc/harbor_migrate_to_homelab_project.sh --ensure-project
#   ./scripts/misc/harbor_migrate_to_homelab_project.sh

set -euo pipefail

TFVARS_DEFAULT="${TFVARS_HOME_DIR:-/mnt/eapp/config}/harbor/config.tfvars"
TFVARS_FILE="${TFVARS_FILE:-$TFVARS_DEFAULT}"
ENSURE_PROJECT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tfvars)
      TFVARS_FILE="$2"
      shift 2
      ;;
    --ensure-project)
      ENSURE_PROJECT=1
      shift
      ;;
    -h|--help)
      sed -n '1,22p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${HARBOR_URL:-}" || -z "${HARBOR_USER:-}" || -z "${HARBOR_PASS:-}" ]]; then
  if [[ ! -f "$TFVARS_FILE" ]]; then
    echo "Set HARBOR_URL, HARBOR_USER, HARBOR_PASS or provide --tfvars ($TFVARS_FILE missing)." >&2
    exit 1
  fi
  HARBOR_URL="$(grep -E '^\s*url\s*=' "$TFVARS_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  HARBOR_USER="$(grep -E '^\s*username\s*=' "$TFVARS_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  HARBOR_PASS="$(grep -E '^\s*password\s*=' "$TFVARS_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  if grep -qE '^\s*insecure\s*=\s*true' "$TFVARS_FILE"; then
    export HARBOR_INSECURE=1
  else
    export HARBOR_INSECURE="${HARBOR_INSECURE:-0}"
  fi
fi

export HARBOR_URL HARBOR_USER HARBOR_PASS

curl_args=(--silent --show-error --user "${HARBOR_USER}:${HARBOR_PASS}" --header "Accept: application/json")
if [[ "${HARBOR_INSECURE:-0}" == "1" ]]; then
  curl_args+=(--insecure)
fi

api_get() {
  local path="$1"
  curl "${curl_args[@]}" --fail "${HARBOR_URL%/}${path}"
}

if [[ "$ENSURE_PROJECT" == "1" ]]; then
  cnt="$(api_get "/api/v2.0/projects?name=homelab&exact=true" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
  if [[ "$cnt" == "0" ]]; then
    echo "Creating Harbor project homelab..."
    curl "${curl_args[@]}" --fail -X POST "${HARBOR_URL%/}/api/v2.0/projects" \
      -H "Content-Type: application/json" \
      -d '{"project_name":"homelab","metadata":{"public":"false"},"storage_limit":-1}'
    echo
  else
    echo "Harbor project homelab already exists."
  fi
fi

export HARBOR_INSECURE
python3 <<'PY'
import base64
import json
import os
import ssl
import subprocess
import sys
import urllib.parse
import urllib.request

harbor_url = os.environ["HARBOR_URL"].rstrip("/")
user = os.environ["HARBOR_USER"]
pw = os.environ["HARBOR_PASS"]
insecure = os.environ.get("HARBOR_INSECURE", "0") == "1"

auth = base64.b64encode(f"{user}:{pw}".encode()).decode()


def ctx():
    if not insecure:
        return None
    c = ssl.create_default_context()
    c.check_hostname = False
    c.verify_mode = ssl.CERT_NONE
    return c


def http_get(path: str):
    req = urllib.request.Request(harbor_url + path, headers={"Authorization": f"Basic {auth}"})
    with urllib.request.urlopen(req, timeout=300, context=ctx()) as r:
        return json.load(r)


projects = http_get("/api/v2.0/projects?page_size=100")
skip = {"library", "homelab"}


def dest_repo_name(project: str, repo_full: str) -> str:
    if "/" in repo_full:
        a, b = repo_full.split("/", 1)
        if a == project and b == project:
            return a
        return repo_full.split("/")[0]
    return repo_full


for proj in sorted(projects, key=lambda p: p["name"]):
    pname = proj["name"]
    if pname in skip:
        continue
    enc = urllib.parse.quote(pname, safe="")
    repos = http_get(f"/api/v2.0/projects/{enc}/repositories?page_size=100")
    for repo in repos:
        repo_name = repo["name"]
        dest = dest_repo_name(pname, repo_name)
        # Tags via skopeo (Harbor artifacts list is unreliable on some builds).
        reg = harbor_url.removeprefix("http://").removeprefix("https://")
        creds = f"{user}:{pw}"
        tls_verify = ["--tls-verify=false"] if insecure else []
        tls_copy = (
            ["--src-tls-verify=false", "--dest-tls-verify=false"] if insecure else []
        )
        out = subprocess.check_output(
            ["skopeo", "list-tags", *tls_verify, f"--creds={creds}", f"docker://{reg}/{repo_name}"],
            text=True,
        )
        data = json.loads(out)
        tags = set(data.get("Tags") or [])
        if not tags:
            print(f"[skip] {pname}/{repo_name}: skopeo list-tags empty", file=sys.stderr)
            continue
        for tag in sorted(tags):
            src = f"docker://{reg}/{repo_name}:{tag}"
            dst = f"docker://{reg}/homelab/{dest}:{tag}"
            print(f"[copy] {src} -> {dst}")
            try:
                subprocess.check_call(
                    [
                        "skopeo",
                        "copy",
                        "--all",
                        *tls_copy,
                        f"--src-creds={creds}",
                        f"--dest-creds={creds}",
                        src,
                        dst,
                    ]
                )
            except subprocess.CalledProcessError as e:
                print(f"[warn] copy failed (skip): {src} ({e.returncode})", file=sys.stderr)
PY

echo "[done] Finished tag copies into homelab/. Apply Harbor config Terraform after old projects are removable."
