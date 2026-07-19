"""Cross-slice Terraform state helpers.

Used by the config/database slices that depend on a previously-applied app
slice (they read its remote state via ``terraform_remote_state``).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from .logging_util import PipelineError, info
from .terraform import TerraformRunner

_TOKEN_RE = re.compile(r'([A-Za-z0-9_-]+)\s*=\s*(".*?"|\{[^{}]*\}|[^,#\s]+)')


def ensure_app_state_exists(app_terraform_dir: Path, backend_config: Path, *, stage: str = "config") -> None:
    """Init + ``state pull`` the app slice so its outputs are available.

    Mirrors ``ensure_app_state_exists`` in the NPM/Grafana bespoke pipelines.
    """

    info(f"Verifying app remote state exists before running {stage} stage")
    app_runner = TerraformRunner(app_terraform_dir)
    try:
        app_runner.init(backend_config)
    except PipelineError as exc:
        raise PipelineError(
            f"Unable to initialize app Terraform state. Run the app stage before {stage}."
        ) from exc

    if not app_runner.state_pull():
        raise PipelineError(
            "Failed to pull app state; ensure the app stage has been applied successfully."
        )


def backend_to_json(backend_path: Path) -> str:
    """Render an S3 backend HCL file to a JSON object string.

    Port of the inline Python in ``grafana/pipeline/database.sh`` used to feed
    ``TF_VAR_remote_state_backend``.
    """

    path = Path(backend_path)
    if not path.is_file():
        raise PipelineError("Backend file not found")

    data: dict = {}
    stack: list[dict] = [data]
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.endswith("{") and "=" not in line:
                block = line[:-1].strip()
                new_map: dict = {}
                stack[-1][block] = new_map
                stack.append(new_map)
                continue
            if line == "}":
                if len(stack) == 1:
                    raise PipelineError("Unexpected closing brace in backend file")
                stack.pop()
                continue
            if "=" not in line:
                continue
            key, raw_val = (part.strip() for part in line.split("=", 1))
            stack[-1][key] = _parse_value(raw_val)

    return json.dumps(data)


def _parse_value(raw: str):
    val = raw.strip().rstrip(",")
    if val.startswith("{") and val.endswith("}"):
        inner = val[1:-1].strip()
        nested: dict = {}
        if inner:
            for key, inner_val in _TOKEN_RE.findall(inner):
                nested[key] = _parse_value(inner_val)
        return nested
    if val.startswith('"') and val.endswith('"'):
        return val[1:-1]
    if val.lower() in ("true", "false"):
        return val.lower() == "true"
    try:
        if "." in val:
            return float(val)
        return int(val)
    except ValueError:
        return val
