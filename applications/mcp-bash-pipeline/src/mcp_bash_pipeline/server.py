from __future__ import annotations

import os
import shlex
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import Context, FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from pydantic import Field


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    value = int(raw)
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


def _split_csv(raw: str) -> list[str]:
    return [value.strip() for value in raw.split(",") if value.strip()]


@dataclass(slots=True)
class Settings:
    host: str
    port: int
    http_path: str
    default_workspace_root: str
    allowed_workspace_roots: list[Path]
    tfvars_root: Path
    workspace_root_header: str
    workspace_root_query_param: str
    workspace_name_header: str
    default_workspace_name: str
    max_output_chars: int
    default_timeout_seconds: int
    allowed_hosts: list[str]
    allowed_origins: list[str]


def load_settings() -> Settings:
    default_workspace_root = os.getenv("BASH_PIPELINE_DEFAULT_WORKSPACE_ROOT", "").strip()
    allowed_roots_raw = os.getenv("BASH_PIPELINE_ALLOWED_WORKSPACE_ROOTS", "/mnt/eapp/code")
    allowed_workspace_roots = [Path(root).resolve() for root in allowed_roots_raw.split(":") if root.strip()]
    tfvars_root = Path(os.getenv("BASH_PIPELINE_TFVARS_ROOT", "/mnt/eapp/.tfvars")).resolve()

    default_allowed_hosts = [
        "127.0.0.1",
        "127.0.0.1:*",
        "localhost",
        "localhost:*",
        "[::1]",
        "[::1]:*",
        "mcp.bash-pipeline.nodadyoushutup.com",
        "mcp.bash-pipeline.nodadyoushutup.com:*",
    ]
    default_allowed_origins = [
        "http://127.0.0.1",
        "http://127.0.0.1:*",
        "http://localhost",
        "http://localhost:*",
        "http://[::1]",
        "http://[::1]:*",
        "https://mcp.bash-pipeline.nodadyoushutup.com",
    ]

    return Settings(
        host=os.getenv("BASH_PIPELINE_HOST", "0.0.0.0"),
        port=_env_int("BASH_PIPELINE_PORT", 8107),
        http_path=os.getenv("BASH_PIPELINE_HTTP_PATH", "/mcp"),
        default_workspace_root=default_workspace_root,
        allowed_workspace_roots=allowed_workspace_roots,
        tfvars_root=tfvars_root,
        workspace_root_header=os.getenv("BASH_PIPELINE_WORKSPACE_ROOT_HEADER", "x-workspace-root"),
        workspace_root_query_param=os.getenv("BASH_PIPELINE_WORKSPACE_ROOT_QUERY_PARAM", "workspace_root"),
        workspace_name_header=os.getenv("BASH_PIPELINE_WORKSPACE_NAME_HEADER", "x-homelab-workspace"),
        default_workspace_name=os.getenv("BASH_PIPELINE_DEFAULT_WORKSPACE_NAME", "homelab").strip(),
        max_output_chars=_env_int("BASH_PIPELINE_MAX_OUTPUT_CHARS", 12000),
        default_timeout_seconds=_env_int("BASH_PIPELINE_DEFAULT_TIMEOUT_SECONDS", 1800),
        allowed_hosts=_split_csv(os.getenv("BASH_PIPELINE_ALLOWED_HOSTS", ",".join(default_allowed_hosts))),
        allowed_origins=_split_csv(
            os.getenv("BASH_PIPELINE_ALLOWED_ORIGINS", ",".join(default_allowed_origins))
        ),
    )


SETTINGS = load_settings()

BLOCKED_PIPELINES: dict[str, str] = {
    "terraform/cluster/talos/app/pipeline/app.sh": (
        "Requires operator-local kubeconfig and kubectl-based cluster readiness checks."
    ),
    "terraform/swarm/vault/app/pipeline/app.sh": (
        "Requires host-level SSH and Docker bootstrap behavior outside this runner contract."
    ),
}


MCP = FastMCP(
    "bash-pipeline",
    host=SETTINGS.host,
    stateless_http=True,
    json_response=True,
    streamable_http_path=SETTINGS.http_path,
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=SETTINGS.allowed_hosts,
        allowed_origins=SETTINGS.allowed_origins,
    ),
)


def _truncate_output(text: str, max_chars: int) -> tuple[str, bool]:
    if len(text) <= max_chars:
        return text, False
    remaining = len(text) - max_chars
    return f"{text[:max_chars]}\n\n... [truncated {remaining} characters]", True


def _get_request_workspace_root(context: Context | None) -> str:
    if context is None:
        return ""
    request = context.request_context.request
    if request is None:
        return ""
    header_value = request.headers.get(SETTINGS.workspace_root_header, "").strip()
    if header_value:
        return header_value
    query_value = request.query_params.get(SETTINGS.workspace_root_query_param, "").strip()
    if query_value:
        return query_value
    return ""


def _get_request_workspace_name(context: Context | None) -> str:
    if context is None:
        return ""
    request = context.request_context.request
    if request is None:
        return ""
    return request.headers.get(SETTINGS.workspace_name_header, "").strip()


def _resolve_workspace_root(context: Context | None, explicit_workspace_root: str = "") -> Path:
    candidate = (
        explicit_workspace_root.strip()
        or _get_request_workspace_root(context)
        or SETTINGS.default_workspace_root
    )
    if not candidate:
        raise ValueError("workspace_root is required when no default workspace root is configured")

    workspace_root = Path(candidate).resolve()
    if not workspace_root.is_absolute():
        raise ValueError("workspace_root must be an absolute path")
    if not workspace_root.exists():
        raise ValueError(f"workspace_root does not exist: {workspace_root}")
    if SETTINGS.allowed_workspace_roots and not any(
        workspace_root == root or root in workspace_root.parents for root in SETTINGS.allowed_workspace_roots
    ):
        allowed = ", ".join(str(root) for root in SETTINGS.allowed_workspace_roots)
        raise ValueError(f"workspace_root must stay within the configured allowed roots: {allowed}")
    return workspace_root


def _pipeline_catalog(workspace_root: Path) -> list[dict[str, Any]]:
    terraform_root = workspace_root / "terraform"
    if not terraform_root.exists():
        return []

    entries: list[dict[str, Any]] = []
    for pipeline_file in sorted(terraform_root.rglob("pipeline/*.sh")):
        relative_path = pipeline_file.relative_to(workspace_root).as_posix()
        blocked_reason = BLOCKED_PIPELINES.get(relative_path)
        entries.append(
            {
                "path": relative_path,
                "supported": blocked_reason is None,
                "reason": blocked_reason or "",
            }
        )
    return entries


def _resolve_pipeline_path(workspace_root: Path, pipeline_path: str) -> Path:
    candidate = pipeline_path.strip()
    if not candidate:
        raise ValueError("pipeline_path must not be empty")

    requested = Path(candidate)
    resolved = requested.resolve() if requested.is_absolute() else (workspace_root / requested).resolve()
    if workspace_root != resolved and workspace_root not in resolved.parents:
        raise ValueError("pipeline_path must stay within the selected workspace root")
    if resolved.suffix != ".sh":
        raise ValueError("pipeline_path must point to a .sh file")
    if not resolved.is_file():
        raise ValueError(f"pipeline_path does not exist: {resolved}")

    relative_path = resolved.relative_to(workspace_root).as_posix()
    if not relative_path.startswith("terraform/") or "/pipeline/" not in relative_path:
        raise ValueError("pipeline_path must point to a repo-managed Terraform pipeline entrypoint")

    return resolved


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


@MCP.tool()
def server_info(context: Context | None = None) -> dict[str, Any]:
    """Return workspace, path, and runtime policy details for the pipeline server."""
    requested_workspace_root = _get_request_workspace_root(context)
    requested_workspace_name = _get_request_workspace_name(context)
    tfvars_root_exists = SETTINGS.tfvars_root.exists()
    tfvars_root_is_dir = SETTINGS.tfvars_root.is_dir()

    resolved_workspace_root = ""
    workspace_error = ""
    try:
        resolved_workspace_root = str(_resolve_workspace_root(context))
    except ValueError as exc:
        workspace_error = str(exc)

    return {
        "default_workspace_root": SETTINGS.default_workspace_root,
        "allowed_workspace_roots": [str(root) for root in SETTINGS.allowed_workspace_roots],
        "tfvars_root": str(SETTINGS.tfvars_root),
        "tfvars_root_exists": tfvars_root_exists,
        "tfvars_root_is_dir": tfvars_root_is_dir,
        "workspace_root_header": SETTINGS.workspace_root_header,
        "workspace_root_query_param": SETTINGS.workspace_root_query_param,
        "workspace_name_header": SETTINGS.workspace_name_header,
        "default_workspace_name": SETTINGS.default_workspace_name,
        "requested_workspace_root": requested_workspace_root,
        "requested_workspace_name": requested_workspace_name,
        "resolved_workspace_root": resolved_workspace_root,
        "workspace_error": workspace_error,
        "default_timeout_seconds": SETTINGS.default_timeout_seconds,
        "max_output_chars": SETTINGS.max_output_chars,
        "blocked_pipelines": BLOCKED_PIPELINES,
    }


@MCP.tool()
def list_stage_pipelines(
    context: Context | None = None,
    workspace_root: str = Field(
        default="",
        description="Absolute workspace root. Leave empty to use x-workspace-root or the default workspace root.",
    ),
    include_blocked: bool = Field(
        default=True,
        description="Whether to include known blocked pipelines in the results.",
    ),
) -> dict[str, Any]:
    """List repo-managed Terraform pipeline entrypoints for the selected workspace."""
    target_root = _resolve_workspace_root(context, workspace_root)
    entries = _pipeline_catalog(target_root)
    if not include_blocked:
        entries = [entry for entry in entries if entry["supported"]]
    return {
        "workspace_root": str(target_root),
        "count": len(entries),
        "pipelines": entries,
    }


@MCP.tool()
def inspect_stage_pipeline(
    pipeline_path: str = Field(description="Absolute or workspace-relative path to a Terraform pipeline .sh file."),
    context: Context | None = None,
    workspace_root: str = Field(
        default="",
        description="Absolute workspace root. Leave empty to use x-workspace-root or the default workspace root.",
    ),
) -> dict[str, Any]:
    """Return metadata and source for one repo-managed pipeline entrypoint."""
    target_root = _resolve_workspace_root(context, workspace_root)
    resolved_pipeline = _resolve_pipeline_path(target_root, pipeline_path)
    relative_path = resolved_pipeline.relative_to(target_root).as_posix()
    blocked_reason = BLOCKED_PIPELINES.get(relative_path, "")
    content = _read_text(resolved_pipeline)
    preview, preview_truncated = _truncate_output(content, min(SETTINGS.max_output_chars, 8000))
    return {
        "workspace_root": str(target_root),
        "pipeline_path": relative_path,
        "absolute_path": str(resolved_pipeline),
        "supported": blocked_reason == "",
        "reason": blocked_reason,
        "line_count": content.count("\n") + 1,
        "preview": preview,
        "preview_truncated": preview_truncated,
    }


@MCP.tool()
def run_stage_pipeline(
    pipeline_path: str = Field(description="Absolute or workspace-relative path to a supported Terraform pipeline .sh file."),
    timeout_seconds: int = Field(
        default=0,
        description="Execution timeout in seconds. Leave at 0 to use the deployment default.",
    ),
    context: Context | None = None,
    workspace_root: str = Field(
        default="",
        description="Absolute workspace root. Leave empty to use x-workspace-root or the default workspace root.",
    ),
) -> dict[str, Any]:
    """Run one supported repo-managed Terraform pipeline entrypoint with its default inputs."""
    target_root = _resolve_workspace_root(context, workspace_root)
    resolved_pipeline = _resolve_pipeline_path(target_root, pipeline_path)
    relative_path = resolved_pipeline.relative_to(target_root).as_posix()
    blocked_reason = BLOCKED_PIPELINES.get(relative_path)
    if blocked_reason:
        raise ValueError(f"Pipeline is blocked for this server: {blocked_reason}")

    effective_timeout = SETTINGS.default_timeout_seconds if timeout_seconds <= 0 else timeout_seconds
    env = os.environ.copy()
    # Always drive the shared Terraform wrapper from the service-configured tfvars root.
    env["TFVARS_HOME_DIR"] = str(SETTINGS.tfvars_root)
    env["TFVARS_DIR"] = str(SETTINGS.tfvars_root)
    env.setdefault("HOME", "/tmp/mcp-bash-pipeline")

    command = ["bash", str(resolved_pipeline)]
    started = time.monotonic()
    try:
        result = subprocess.run(
            command,
            cwd=str(target_root),
            env=env,
            capture_output=True,
            text=True,
            timeout=effective_timeout,
            check=False,
        )
        duration_seconds = round(time.monotonic() - started, 3)
        stdout_text, stdout_truncated = _truncate_output(result.stdout, SETTINGS.max_output_chars)
        stderr_text, stderr_truncated = _truncate_output(result.stderr, SETTINGS.max_output_chars)
        return {
            "pipeline_path": relative_path,
            "workspace_root": str(target_root),
            "command": shlex.join(command),
            "timeout_seconds": effective_timeout,
            "timed_out": False,
            "exit_code": result.returncode,
            "ok": result.returncode == 0,
            "duration_seconds": duration_seconds,
            "stdout": stdout_text,
            "stdout_truncated": stdout_truncated,
            "stderr": stderr_text,
            "stderr_truncated": stderr_truncated,
        }
    except subprocess.TimeoutExpired as exc:
        duration_seconds = round(time.monotonic() - started, 3)
        stdout = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout or b"").decode("utf-8", errors="replace")
        stderr = exc.stderr if isinstance(exc.stderr, str) else (exc.stderr or b"").decode("utf-8", errors="replace")
        stdout_text, stdout_truncated = _truncate_output(stdout, SETTINGS.max_output_chars)
        stderr_text, stderr_truncated = _truncate_output(stderr, SETTINGS.max_output_chars)
        return {
            "pipeline_path": relative_path,
            "workspace_root": str(target_root),
            "command": shlex.join(command),
            "timeout_seconds": effective_timeout,
            "timed_out": True,
            "exit_code": None,
            "ok": False,
            "duration_seconds": duration_seconds,
            "stdout": stdout_text,
            "stdout_truncated": stdout_truncated,
            "stderr": stderr_text,
            "stderr_truncated": stderr_truncated,
        }


def main() -> None:
    MCP.settings.host = SETTINGS.host
    MCP.settings.port = SETTINGS.port
    MCP.settings.streamable_http_path = SETTINGS.http_path
    MCP.run(transport="streamable-http")


if __name__ == "__main__":
    main()
