"""Run one task through its registered handler."""

from __future__ import annotations

from torrent_manager.models.base import utcnow
from torrent_manager.models.task import Task, TaskRunStatus
from torrent_manager.services.tasks.context import TaskContext
from torrent_manager.services.tasks.handlers import get_handler
from torrent_manager.services.tasks.result import TaskResult


class TaskExecutionError(RuntimeError):
    """Raised when a task cannot be executed."""


def execute_task(task: Task, context: TaskContext | None = None) -> TaskResult:
    """Execute ``task`` in isolation and persist its last-run fields."""
    runtime_context = context or TaskContext()
    handler = get_handler(task.task_type)
    if handler is None:
        result = TaskResult(success=False, error=f"Unknown task type: {task.task_type}")
    else:
        task.last_status = TaskRunStatus.RUNNING.value
        task.last_output = None
        task.last_error = None
        task.save()
        try:
            result = handler.execute(task, runtime_context)
        except Exception as exc:  # noqa: BLE001 — surface handler failures on the task row
            result = TaskResult(success=False, error=str(exc))

    task.last_status = (
        TaskRunStatus.COMPLETED.value if result.success else TaskRunStatus.FAILED.value
    )
    task.last_output = result.output or None
    task.last_error = result.error
    task.save()
    return result
