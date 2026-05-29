"""Execution context passed into every task handler."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TaskContext:
    """Runtime metadata for a single task invocation."""

    pipeline_id: int | None = None
    pipeline_step_id: int | None = None
    step_position: int | None = None
