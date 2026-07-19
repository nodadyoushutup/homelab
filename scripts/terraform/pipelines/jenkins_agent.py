"""Bespoke Jenkins agent pre-flight checks.

Ports ``run_pre_terraform_checks`` from
``jenkins-agent-{amd64,arm64}/pipeline/app.sh``: confirm the Jenkins controller
slice has been applied (its ``controller_service_id`` output is available) and
validate that the pinned agent image manifest advertises the expected CPU
architecture (authenticating to the registry with ``var.registry_auths`` when an
anonymous manifest inspect fails).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from .logging_util import PipelineError, info
from .slice_pipeline import SliceContext
from .terraform import TerraformRunner

_IMAGE_RE = re.compile(r'^\s*image\s*=\s*"([^"]*)"')


def make_pre_terraform(expected_arch: str):
    """Return a ``pre_terraform`` hook for the given agent architecture."""

    def hook(ctx: SliceContext) -> None:
        _run_pre_terraform_checks(ctx, expected_arch)

    return hook


def _run_pre_terraform_checks(ctx: SliceContext, expected_arch: str) -> None:
    controller_dir = ctx.root / "terraform" / "components" / "swarm" / "jenkins-controller" / "app"
    if not controller_dir.is_dir():
        raise PipelineError(
            f"Missing controller Terraform directory at {controller_dir}. Run the controller pipeline first."
        )

    info("Checking Jenkins controller outputs")
    controller = TerraformRunner(controller_dir)
    if controller.stream(["init", f"-backend-config={ctx.backend_config}"]) != 0:
        raise PipelineError(
            "Unable to initialize controller backend; ensure controller pipeline has been run."
        )

    controller_service_id = controller.output_raw("controller_service_id")
    if not controller_service_id:
        raise PipelineError(
            "Jenkins controller outputs unavailable. Run the controller pipeline before deploying agents."
        )

    _assert_agent_image_architecture(ctx, expected_arch)


def _resolve_agent_image(ctx: SliceContext) -> str:
    main_tf = ctx.terraform_dir / "main.tf"
    if main_tf.is_file():
        for line in main_tf.read_text(encoding="utf-8").splitlines():
            match = _IMAGE_RE.match(line)
            if match:
                return match.group(1)
    raise PipelineError(
        f"Unable to resolve Jenkins agent image literal from {main_tf}."
    )


def _registry_address_from_image(image_ref: str) -> str:
    candidate = image_ref.split("/", 1)[0]
    if "." in candidate or ":" in candidate or candidate == "localhost":
        return candidate
    return ""


def _load_registry_auth(ctx: SliceContext, image: str) -> tuple[str, str, str] | None:
    reg_host = _registry_address_from_image(image) or "docker.io"
    runner = TerraformRunner(ctx.terraform_dir)
    auths_json = runner.console(
        "jsonencode(coalesce(try(var.registry_auths, null), []))", var_files=ctx.var_files
    )
    if not auths_json:
        return None
    try:
        auths = json.loads(json.loads(auths_json)) if auths_json.startswith('"') else json.loads(auths_json)
    except json.JSONDecodeError:
        return None
    if not isinstance(auths, list) or not auths:
        return None

    reg = reg_host.lower().strip()
    pick = None
    for entry in auths:
        if (entry.get("address") or "ghcr.io").lower() == reg:
            pick = entry
            break
    if pick is None:
        pick = auths[0]
    return (pick.get("address") or "", pick.get("username") or "", pick.get("password") or "")


def _docker_manifest_inspect(image: str, docker_config: str | None = None) -> tuple[bool, str]:
    env = dict(os.environ)
    if docker_config:
        env["DOCKER_CONFIG"] = docker_config
    proc = subprocess.run(
        ["docker", "manifest", "inspect", image],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return proc.returncode == 0, proc.stdout or ""


def _inspect_agent_image_manifest(ctx: SliceContext, image: str) -> str:
    ok, output = _docker_manifest_inspect(image)
    if ok:
        return output
    inspect_error = output

    auth = _load_registry_auth(ctx, image)
    if not auth or not auth[1] or not auth[2]:
        info_msg = (
            f"Unable to inspect manifest for {image}. Anonymous registry access failed "
            "and no stage registry_auth credentials are configured."
        )
        if inspect_error:
            info_msg += f"\n      docker manifest inspect: {' '.join(inspect_error.split())}"
        raise PipelineError(info_msg)

    address, username, password = auth
    registry_address = address or _registry_address_from_image(image)
    if not registry_address:
        raise PipelineError(
            f"Unable to determine a registry address for {image} during manifest validation."
        )

    tmp_config = tempfile.mkdtemp(prefix="docker-config-")
    try:
        login = subprocess.run(
            ["docker", "login", registry_address, "--username", username, "--password-stdin"],
            input=password,
            env={**os.environ, "DOCKER_CONFIG": tmp_config},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if login.returncode != 0:
            raise PipelineError(
                f"Unable to authenticate to {registry_address} for Jenkins agent image validation.\n"
                f"      docker login: {' '.join((login.stdout or '').split())}"
            )

        ok, output = _docker_manifest_inspect(image, docker_config=tmp_config)
        if not ok:
            raise PipelineError(
                f"Unable to inspect manifest for {image} after authenticating to {registry_address}.\n"
                f"      docker manifest inspect: {' '.join(output.split())}"
            )
        return output
    finally:
        shutil.rmtree(tmp_config, ignore_errors=True)


def _assert_agent_image_architecture(ctx: SliceContext, expected_arch: str) -> None:
    image = _resolve_agent_image(ctx)
    if shutil.which("docker") is None:
        raise PipelineError("docker is required to validate Jenkins agent image manifests.")

    info(f"Validating Jenkins agent image supports {expected_arch}: {image}")
    manifest = _inspect_agent_image_manifest(ctx, image)

    pattern = re.compile(r'"architecture"\s*:\s*"' + re.escape(expected_arch) + r'"')
    if not pattern.search(manifest):
        raise PipelineError(
            f"Jenkins agent image {image} does not advertise {expected_arch} support."
        )
