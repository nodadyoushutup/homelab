"""Console logging helpers matching the homelab bash pipeline prefixes.

The bash pipelines print structured, greppable lines like ``[STEP] ...`` and
``[ERR] ...`` (stderr).  These helpers reproduce that exact style so the Python
ports read identically in CI logs.
"""

from __future__ import annotations

import sys


def info(message: str) -> None:
    print(f"[INFO] {message}", flush=True)


def warn(message: str) -> None:
    print(f"[WARN] {message}", flush=True)


def step(message: str) -> None:
    print(f"[STEP] {message}", flush=True)


def stage(message: str) -> None:
    print(f"[STAGE] {message}", flush=True)


def done(message: str) -> None:
    print(f"[DONE] {message}", flush=True)


def err(message: str) -> None:
    print(f"[ERR] {message}", file=sys.stderr, flush=True)


class PipelineError(RuntimeError):
    """Raised to abort a pipeline with a non-zero exit code.

    ``code`` mirrors the exit codes the bash pipelines use (``1`` for runtime
    failures, ``2`` for CLI usage errors).
    """

    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code
