"""Shared helpers for bootstrap steps that drive Terraform slice pipelines.

These back the NPM and Jenkins deploy steps: running a slice's self-contained
pipeline script (which handles ``terraform init``/plan/apply on its own),
clearing a slice's local ``.terraform/`` cache so init re-pulls remote state
cleanly, and polling an HTTP endpoint until a service is healthy.
"""

from __future__ import annotations

import shutil
import ssl
import subprocess
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

from bootstrap.prompt import OperatorPrompt

PipelineRunner = Callable[[Path], int]
HttpProbe = Callable[[str], int | None]
PathFormatter = Callable[[Path | str], str]

# CPU architectures with dedicated per-arch deploy slices.
VALID_ARCHS = ("amd64", "arm64")


class TerraformDeployError(RuntimeError):
    """Raised when a Terraform-backed deploy step fails."""


def select_architectures(prompt: OperatorPrompt, subject: str, *, logger) -> list[str]:
    """Ask which CPU architectures to deploy for ``subject`` (default: both).

    The architecture answer doubles as the go/no-go gate — ``none``/``skip``
    deploys zero slices — so callers don't need a separate confirm question.

    Args:
        prompt: Operator prompt used to ask the question.
        subject: Human-readable thing being deployed (e.g. "Jenkins build agent").
        logger: Logger for the fallback warning.

    Returns:
        An ordered, de-duplicated list drawn from :data:`VALID_ARCHS` (possibly
        empty when the operator opts out).
    """
    answer = (
        prompt.ask(
            f"Which {subject} architectures to deploy? (both / amd64 / arm64 / none)",
            default="both",
        )
        .strip()
        .lower()
    )
    if answer in {"", "both", "all"}:
        return list(VALID_ARCHS)
    if answer in {"none", "skip"}:
        return []

    parts = [part for part in answer.replace(",", " ").split() if part]
    archs = [part for part in parts if part in VALID_ARCHS]
    if not archs:
        logger.warning(
            "Unrecognized architecture answer %r; defaulting to both", answer
        )
        return list(VALID_ARCHS)
    return list(dict.fromkeys(archs))


def default_pipeline_runner(project_root: Path) -> PipelineRunner:
    """Return a runner that executes a pipeline script with bash, streaming output."""

    def run(script: Path) -> int:
        proc = subprocess.run(["bash", str(script)], cwd=project_root, check=False)
        return proc.returncode

    return run


def default_http_probe(url: str) -> int | None:
    """Return the HTTP status of ``url`` (TLS unverified), or ``None`` on error."""
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(url, timeout=10, context=context) as response:
            return int(response.status)
    except urllib.error.HTTPError as exc:
        # A 401/403/404 still proves the service is answering requests.
        return int(exc.code)
    except (urllib.error.URLError, OSError):
        return None


def clean_backend_cache(
    slice_dir: Path, *, rel: PathFormatter, logger
) -> None:
    """Remove a slice's ``.terraform/`` so init re-pulls remote state cleanly.

    Deletes only the local ``.terraform/`` working directory (provider cache +
    backend pointer). The real state lives in the remote (S3/MinIO) backend and
    the pinned ``.terraform.lock.hcl`` is left in place, so this cannot lose
    state — it just avoids the "Backend configuration changed" reconcile prompt.

    Args:
        slice_dir: Terraform slice directory to clean.
        rel: Formatter that renders a path relative to the repo root.
        logger: Logger for progress output.
    """
    cache = slice_dir / ".terraform"
    if cache.is_dir():
        shutil.rmtree(cache, ignore_errors=True)
        logger.info("Cleared Terraform backend cache: %s", rel(cache))


def run_pipeline(
    runner: PipelineRunner,
    script: Path,
    *,
    label: str,
    rel: PathFormatter,
    logger,
    error_cls: type[Exception],
) -> None:
    """Run a slice pipeline script, raising ``error_cls`` on a non-zero exit.

    Args:
        runner: Pipeline runner returning the script exit code.
        script: Pipeline script to run.
        label: Human-readable stage label for logs/errors.
        rel: Formatter that renders a path relative to the repo root.
        logger: Logger for progress output.
        error_cls: Exception type to raise on failure.
    """
    if not script.is_file():
        raise error_cls(f"{label} pipeline script missing: {rel(script)}")
    logger.info("Running %s pipeline: %s", label, rel(script))
    exit_code = runner(script)
    if exit_code != 0:
        raise error_cls(f"{label} pipeline failed (exit {exit_code})")
    logger.info("%s pipeline complete", label)


def wait_healthy(
    probe: HttpProbe,
    probe_url: str,
    *,
    label: str,
    attempts: int,
    interval: float,
    sleep: Callable[[float], None],
    logger,
    error_cls: type[Exception],
) -> None:
    """Poll ``probe_url`` until it answers (HTTP < 500), else raise.

    A response below 500 (including 401/403) counts as healthy; 5xx (e.g. a
    starting service returning 503) keeps waiting.

    Args:
        probe: Callable returning an HTTP status for a URL (or ``None``).
        probe_url: URL to poll.
        label: Human-readable service label for logs/errors.
        attempts: Number of poll attempts.
        interval: Seconds between attempts.
        sleep: Sleep function (injectable for tests).
        logger: Logger for progress output.
        error_cls: Exception type to raise on timeout.
    """
    logger.info("Waiting for %s at %s", label, probe_url)
    for attempt in range(1, attempts + 1):
        status = probe(probe_url)
        if status is not None and status < 500:
            logger.info("%s is healthy (HTTP %d)", label, status)
            return
        logger.info(
            "Waiting for %s (%s) [%d/%d]",
            label,
            status if status is not None else "no response",
            attempt,
            attempts,
        )
        if attempt < attempts:
            sleep(interval)
    raise error_cls(
        f"{label} did not become reachable after {attempts} attempts"
    )


__all__ = [
    "VALID_ARCHS",
    "HttpProbe",
    "PathFormatter",
    "PipelineRunner",
    "TerraformDeployError",
    "clean_backend_cache",
    "default_http_probe",
    "default_pipeline_runner",
    "run_pipeline",
    "select_architectures",
    "wait_healthy",
]
