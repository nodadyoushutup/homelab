"""Normalized result from a task handler."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TaskResult:
    """Outcome of one isolated task execution."""

    success: bool
    output: str = ""
    error: str | None = None
