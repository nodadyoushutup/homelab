"""Bespoke Vault pipeline behavior (app bootstrap + config unseal/secret merge).

Ports the operational steps from ``vault/pipeline/app.sh`` and
``vault/pipeline/config.sh``:

* app: swarm-manager port preflight over SSH, then ``scripts/vault/bootstrap.sh``
  and a post-deploy health poll.
* config: resolve a reachable ``VAULT_ADDR``, auto-unseal via
  ``scripts/vault/unseal.sh``, then merge KV secret payloads into a generated
  ``*.auto.tfvars.json`` passed as an extra ``-var-file``.
"""

from __future__ import annotations

import atexit
import os
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

from .logging_util import PipelineError, info, warn
from .slice_pipeline import SliceContext

DEFAULT_VAULT_ADDR = "http://swarm-cp-0.local:8200"
_HEALTHY_CODES = {200, 429, 472, 473, 501, 503}
_VAULT_PUBLISHED_PORT = "8200"


# --------------------------------------------------------------------------
# shared helpers
# --------------------------------------------------------------------------
def _detect_swarm_manager_host() -> str:
    host = os.environ.get("VAULT_SWARM_MANAGER_HOST")
    if host:
        return host
    host = os.environ.get("DOCKER_SWARM_CP", "ssh://swarm-cp-0.internal")
    host = host.removeprefix("ssh://")
    host = host.split("/", 1)[0]
    return host


def _vault_health_code(vault_addr: str, timeout: float = 3.0) -> int | None:
    url = f"{vault_addr.rstrip('/')}/v1/sys/health"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.getcode()
    except urllib.error.HTTPError as exc:
        return exc.code
    except (urllib.error.URLError, OSError, ValueError):
        return None


def _source_env_file(env_file: Path) -> dict[str, str]:
    """Read simple ``KEY=VALUE`` lines (mirrors ``set -a; source``)."""

    values: dict[str, str] = {}
    if not env_file.is_file():
        return values
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        val = val.strip().strip('"').strip("'")
        values[key] = val
    return values


# --------------------------------------------------------------------------
# app slice
# --------------------------------------------------------------------------
def app_preflight(ctx: SliceContext) -> None:
    """SSH port preflight before deploying the Vault service."""

    host = _detect_swarm_manager_host()
    if not host:
        raise PipelineError("Unable to determine swarm manager host for Vault port preflight.")
    if shutil.which("ssh") is None:
        raise PipelineError("ssh is required for Vault port preflight checks.")

    if subprocess.run(["ssh", host, "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        raise PipelineError(
            f"Unable to reach swarm manager host {host} over ssh for Vault preflight checks."
        )

    existing = subprocess.run(
        ["ssh", host, "docker service inspect vault >/dev/null 2>&1"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if existing.returncode == 0:
        info(f"Existing Vault service detected on {host}; skipping fresh-port check.")
        os.environ["VAULT_SWARM_MANAGER_HOST"] = host
        return

    port_check = subprocess.run(
        [
            "ssh",
            host,
            "ss -H -ltn 2>/dev/null | awk '{print $4}' | "
            f"grep -Eq '(^|:|\\]){_VAULT_PUBLISHED_PORT}$'",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if port_check.returncode == 0:
        raise PipelineError(
            f"Port {_VAULT_PUBLISHED_PORT} is already in use on {host}.\n"
            "      Free the port or remove the conflicting listener before rerunning Vault app pipeline."
        )

    info(f"Port preflight passed on {host}:{_VAULT_PUBLISHED_PORT}.")
    os.environ["VAULT_SWARM_MANAGER_HOST"] = host


def app_bootstrap_and_health(ctx: SliceContext) -> None:
    """Run the bootstrap script then poll the health endpoint."""

    bootstrap = ctx.root / "scripts" / "vault" / "bootstrap.sh"
    if not (bootstrap.is_file() and os.access(bootstrap, os.X_OK)):
        raise PipelineError(f"Missing executable bootstrap script: {bootstrap}")

    if subprocess.run([str(bootstrap)]).returncode != 0:
        raise PipelineError("Vault bootstrap failed")

    _post_deploy_health_check(ctx)


def _post_deploy_health_check(ctx: SliceContext) -> None:
    retries = 24
    sleep_seconds = 5
    env_file = ctx.config_dir / "terraform" / "components" / "swarm" / "vault" / ".env"

    vault_addr = os.environ.get("VAULT_ADDR", "")
    if not vault_addr and env_file.is_file():
        vault_addr = _source_env_file(env_file).get("VAULT_ADDR", "")
    if not vault_addr:
        warn(f"{env_file} missing or VAULT_ADDR unset; falling back to {DEFAULT_VAULT_ADDR}")
        vault_addr = DEFAULT_VAULT_ADDR

    info(f"Validating Vault health endpoint at {vault_addr}/v1/sys/health")
    for _ in range(retries):
        code = _vault_health_code(vault_addr)
        if code in _HEALTHY_CODES:
            info(f"Vault health check passed with HTTP {code}.")
            return
        time.sleep(sleep_seconds)

    raise PipelineError(
        f"Vault health check failed at {vault_addr}/v1/sys/health after {retries * sleep_seconds}s."
    )


# --------------------------------------------------------------------------
# config slice
# --------------------------------------------------------------------------
def config_unseal_and_merge(ctx: SliceContext) -> None:
    """Ensure Vault is reachable + unsealed, then merge secrets into a var-file."""

    vault_dir = ctx.tfvars_home / "terraform" / "components" / "swarm" / "vault"
    env_file = vault_dir / ".env"
    init_file = vault_dir / "init.json"
    unseal_script = ctx.root / "scripts" / "vault" / "unseal.sh"

    if not init_file.is_file():
        raise PipelineError(
            f"Missing {init_file}. Run terraform/components/swarm/vault/pipeline/app.py "
            "first to bootstrap Vault."
        )
    if not (unseal_script.is_file() and os.access(unseal_script, os.X_OK)):
        raise PipelineError(f"Missing executable unseal script: {unseal_script}")

    env_values = _source_env_file(env_file)
    for key, value in env_values.items():
        os.environ.setdefault(key, value)

    vault_addr = os.environ.get("VAULT_ADDR", "")
    if not vault_addr:
        warn(f"{env_file} missing or VAULT_ADDR unset; falling back to {DEFAULT_VAULT_ADDR}")
        vault_addr = DEFAULT_VAULT_ADDR
        os.environ["VAULT_ADDR"] = vault_addr
    if not os.environ.get("VAULT_TOKEN"):
        raise PipelineError(
            f"VAULT_TOKEN is not set. Ensure {env_file} exists with bootstrap values."
        )

    vault_addr = _resolve_reachable_vault_addr()
    os.environ["VAULT_ADDR"] = vault_addr
    _assert_vault_reachable(vault_addr)

    if subprocess.run([str(unseal_script)]).returncode != 0:
        raise PipelineError(
            "Auto-unseal failed in config pipeline. Run scripts/vault/unseal.sh manually and retry."
        )

    _assert_unsealed(vault_addr)

    merged = _merge_config_secrets(ctx)
    ctx.extra_var_files.append(merged)


def _resolve_reachable_vault_addr() -> str:
    candidates: list[str] = []

    def add(value: str | None) -> None:
        if value and value not in candidates:
            candidates.append(value)

    add(os.environ.get("VAULT_ADDR"))
    add(DEFAULT_VAULT_ADDR)
    manager = _detect_swarm_manager_host()
    if manager:
        add(f"http://{manager}:8200")
    add("http://127.0.0.1:8200")
    add("http://localhost:8200")

    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        for candidate in candidates:
            if _vault_health_code(candidate, timeout=3.0) in _HEALTHY_CODES:
                return candidate
        time.sleep(2)

    raise PipelineError(
        f"Vault is not reachable via any candidate address ({' '.join(candidates)})."
    )


def _assert_vault_reachable(vault_addr: str) -> None:
    code = _vault_health_code(vault_addr)
    if code in _HEALTHY_CODES:
        return
    raise PipelineError(
        f"Vault is not reachable at {vault_addr} (health status {code if code is not None else 'n/a'})."
    )


def _assert_unsealed(vault_addr: str) -> None:
    import json

    url = f"{vault_addr.rstrip('/')}/v1/sys/seal-status"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError, urllib.error.HTTPError):
        payload = {}
    if payload.get("sealed", True) is False:
        return
    raise PipelineError(
        "Vault remains sealed after auto-unseal attempt. Run scripts/vault/unseal.sh manually and retry."
    )


def _merge_config_secrets(ctx: SliceContext) -> Path:
    merge_script = ctx.root / "scripts" / "terraform" / "vault_merge_config_secrets.py"
    handle = tempfile.NamedTemporaryFile(
        prefix="vault-merged-secrets-", suffix=".auto.tfvars.json", delete=False
    )
    handle.close()
    out_path = Path(handle.name)
    atexit.register(lambda: out_path.unlink(missing_ok=True))

    if shutil.which("uv") is not None:
        cmd = ["uv", "run", "--with", "python-hcl2>=4,<5", "python3"]
    else:
        cmd = ["python3"]
    cmd += [
        str(merge_script),
        "--tfvars-home",
        str(ctx.tfvars_home),
        "--vault-config-tfvars",
        str(ctx.slice_tfvars),
        "--out",
        str(out_path),
    ]

    if subprocess.run(cmd).returncode != 0:
        raise PipelineError("Vault secret merge failed (see messages above).")
    return out_path
