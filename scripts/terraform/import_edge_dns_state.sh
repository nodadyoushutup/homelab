#!/usr/bin/env bash
# Import existing Cloudflare DNS records and NPM proxy hosts/certs into Terraform state
# when live infra predates state (drift). Run from repo root after tfvars match reality.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_root_env.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
BACKEND_FILE="${BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"
CF_TFVARS="${TFVARS_HOME_DIR}/terraform/components/remote/cloudflare/config.tfvars"
NPM_TFVARS="${TFVARS_HOME_DIR}/terraform/components/swarm/nginx_proxy_manager/config.tfvars"
CF_DIR="${ROOT_DIR}/terraform/components/remote/cloudflare/config"
NPM_DIR="${ROOT_DIR}/terraform/components/swarm/nginx_proxy_manager/config"
DRY_RUN="${DRY_RUN:-0}"
ONLY="${ONLY:-}"

echo "[STEP] terraform init (cloudflare)"
(cd "${CF_DIR}" && terraform init -backend-config="${BACKEND_FILE}" -reconfigure >/dev/null)

echo "[STEP] terraform init (npm)"
(cd "${NPM_DIR}" && terraform init -backend-config="${BACKEND_FILE}" -reconfigure >/dev/null)

export CF_TFVARS CF_DIR NPM_TFVARS NPM_DIR DRY_RUN ONLY
# Match swarm_pipeline order: shared dns/nfs first, stack tfvars last (wins on provider_config).
NPM_EXTRA_VARFILES="${TFVARS_HOME_DIR}/terraform/components/swarm/dns.tfvars,${TFVARS_HOME_DIR}/terraform/components/swarm/nfs.tfvars"
export NPM_EXTRA_VARFILES
python3 - <<'PY'
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

cf_tfvars = os.environ["CF_TFVARS"]
cf_dir = os.environ["CF_DIR"]
npm_tfvars = os.environ["NPM_TFVARS"]
npm_dir = os.environ["NPM_DIR"]
dry_run = os.environ.get("DRY_RUN", "0") == "1"
only = os.environ.get("ONLY", "")
only_re = re.compile(only) if only else None

npm_extra = [p for p in os.environ.get("NPM_EXTRA_VARFILES", "").split(",") if p]


def parse_hcl_records(text: str) -> list[tuple[str, str]]:
    body = text.split("records = [", 1)[1].split("]", 1)[0]
    out = []
    for block in re.findall(r"\{[^}]+\}", body, re.DOTALL):
        k = re.search(r'key\s*=\s*"([^"]+)"', block)
        n = re.search(r'name\s*=\s*"([^"]+)"', block)
        if k and n:
            out.append((k.group(1), n.group(1)))
    return out


def parse_npm_list_items(text: str, list_name: str) -> list[dict]:
    """Parse certificates or proxy_hosts name + domain_names from tfvars."""
    markers = {
        "certificates": ("certificates = [", "proxy_hosts = ["),
        "proxy_hosts": ("proxy_hosts = [", "redirections = ["),
    }
    if list_name not in markers:
        return []
    start_marker, end_marker = markers[list_name]
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    section = text[start:end]
    items = []
    if list_name == "proxy_hosts":
        for name in re.findall(r'^\s*name\s*=\s*"([^"]+)"', section, re.MULTILINE):
            block_m = re.search(
                rf'name\s*=\s*"{re.escape(name)}"[^}}]*domain_names\s*=\s*\[([^\]]+)\]',
                section,
                re.DOTALL,
            )
            if block_m:
                domains = re.findall(r'"([^"]+)"', block_m.group(1))
                items.append({"name": name, "domain_names": domains})
        return items
    for m in re.finditer(
        r'name\s*=\s*"([^"]+)"\s*,\s*domain_names\s*=\s*\[([^\]]+)\]', section
    ):
        domains = re.findall(r'"([^"]+)"', m.group(2))
        items.append({"name": m.group(1), "domain_names": domains})
    return items


def state_keys(workdir: str, resource_prefix: str) -> set[str]:
    out = subprocess.check_output(
        ["terraform", "state", "list"], cwd=workdir, text=True
    )
    keys = set()
    for line in out.splitlines():
        if not line.startswith(resource_prefix):
            continue
        m = re.search(r'\["([^"]+)"\]', line)
        if m:
            keys.add(m.group(1))
    return keys


def terraform_import(workdir: str, args: list[str]) -> None:
    if dry_run:
        print(f"[dry-run] (cd {workdir} && terraform import {' '.join(args)})")
        return
    subprocess.run(
        ["terraform", "import", *args],
        cwd=workdir,
        check=True,
        capture_output=True,
        text=True,
    )


# --- Cloudflare ---
cf_text = Path(cf_tfvars).read_text()
zone_id = re.search(r'zone_id\s*=\s*"([^"]+)"', cf_text).group(1)
token = re.search(r'api_token\s*=\s*"([^"]+)"', cf_text).group(1)
records = parse_hcl_records(cf_text)
req = urllib.request.Request(
    f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?per_page=500&type=A",
    headers={"Authorization": f"Bearer {token}"},
)
with urllib.request.urlopen(req, timeout=60) as resp:
    cf_by_name = {r["name"]: r["id"] for r in json.loads(resp.read())["result"]}

cf_in_state = state_keys(cf_dir, "cloudflare_dns_record.records")
cf_imported = 0
for key, name in records:
    if only_re and not only_re.search(key):
        continue
    if key in cf_in_state:
        continue
    rid = cf_by_name.get(name)
    if not rid:
        print(f"[skip] cloudflare {key}: no DNS record for {name}")
        continue
    addr = f'cloudflare_dns_record.records["{key}"]'
    try:
        terraform_import(
            cf_dir,
            [f"-var-file={cf_tfvars}", addr, f"{zone_id}/{rid}"],
        )
        print(f"[ok] cloudflare {key}")
        cf_imported += 1
    except subprocess.CalledProcessError as e:
        print(f"[err] cloudflare {key}: {(e.stderr or '').strip()}")

print(f"[info] cloudflare imported {cf_imported}")

# --- NPM ---
npm_text = Path(npm_tfvars).read_text()
npm_var_args = [f"-var-file={p}" for p in npm_extra] + [f"-var-file={npm_tfvars}"]

u = re.search(r'username\s*=\s*"([^"]+)"', npm_text).group(1)
pw = re.search(r'password\s*=\s*"([^"]+)"', npm_text).group(1)
req = urllib.request.Request(
    "http://192.168.1.120:81/api/tokens",
    data=json.dumps({"identity": u, "secret": pw}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=30) as resp:
    npm_token = json.loads(resp.read())["token"]
headers = {"Authorization": f"Bearer {npm_token}"}


def npm_get(path: str) -> list:
    req = urllib.request.Request(f"http://192.168.1.120:81{path}", headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


certs = npm_get("/api/nginx/certificates")
hosts = npm_get("/api/nginx/proxy-hosts")

cert_by_domains = {
    frozenset(c.get("domain_names") or []): c for c in certs if c.get("domain_names")
}
host_by_domains = {
    frozenset(h.get("domain_names") or []): h for h in hosts if h.get("domain_names")
}

cert_in_state = state_keys(npm_dir, "nginxproxymanager_certificate_letsencrypt.this")
host_in_state = state_keys(npm_dir, "nginxproxymanager_proxy_host.this")

cert_imported = 0
for item in parse_npm_list_items(npm_text, "certificates"):
    key = item["name"]
    if only_re and not only_re.search(key):
        continue
    if key in cert_in_state:
        continue
    domains = frozenset(item["domain_names"])
    live = cert_by_domains.get(domains)
    if not live:
        print(f"[skip] npm cert {key}: not in NPM ({', '.join(sorted(domains))})")
        continue
    addr = f'nginxproxymanager_certificate_letsencrypt.this["{key}"]'
    try:
        terraform_import(npm_dir, [*npm_var_args, addr, str(live["id"])])
        print(f"[ok] npm cert {key}")
        cert_imported += 1
    except subprocess.CalledProcessError as e:
        print(f"[err] npm cert {key}: {(e.stderr or '').strip()}")

host_imported = 0
for item in parse_npm_list_items(npm_text, "proxy_hosts"):
    key = item["name"]
    if only_re and not only_re.search(key):
        continue
    if key in host_in_state:
        continue
    domains = frozenset(item["domain_names"])
    live = host_by_domains.get(domains)
    if not live:
        print(f"[skip] npm host {key}: not in NPM ({', '.join(sorted(domains))})")
        continue
    addr = f'nginxproxymanager_proxy_host.this["{key}"]'
    try:
        terraform_import(npm_dir, [*npm_var_args, addr, str(live["id"])])
        print(f"[ok] npm host {key}")
        host_imported += 1
    except subprocess.CalledProcessError as e:
        print(f"[err] npm host {key}: {(e.stderr or '').strip()}")

print(f"[info] npm certs imported {cert_imported}, hosts imported {host_imported}")
PY
