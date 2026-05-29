"""Built-in task handlers — each runs in isolation with only its config + context."""

from __future__ import annotations

import time
from typing import Protocol

from torrent_manager.models.task import Task
from torrent_manager.services.tasks.context import TaskContext
from torrent_manager.services.tasks.result import TaskResult


class TaskHandler(Protocol):
    """Contract for a task type that knows how to execute itself."""

    task_type: str
    label: str

    def execute(self, task: Task, context: TaskContext) -> TaskResult:
        """Run the task in a silo using only ``task.config()`` and ``context``."""


class NoOpHandler:
    task_type = "noop"
    label = "No-op"

    def execute(self, task: Task, context: TaskContext) -> TaskResult:
        return TaskResult(success=True, output="No-op completed.")


class LogHandler:
    task_type = "log"
    label = "Log message"

    def execute(self, task: Task, context: TaskContext) -> TaskResult:
        message = str(task.config().get("message", "")).strip() or task.name
        return TaskResult(success=True, output=message)


class SleepHandler:
    task_type = "sleep"
    label = "Sleep"

    def execute(self, task: Task, context: TaskContext) -> TaskResult:
        seconds_raw = task.config().get("seconds", 1)
        try:
            seconds = max(0.0, float(seconds_raw))
        except (TypeError, ValueError):
            return TaskResult(success=False, error="Config 'seconds' must be a number.")
        time.sleep(seconds)
        return TaskResult(success=True, output=f"Slept for {seconds:g} second(s).")


_HANDLERS: dict[str, TaskHandler] = {
    handler.task_type: handler
    for handler in (NoOpHandler(), LogHandler(), SleepHandler())
}


def get_handler(task_type: str) -> TaskHandler | None:
    """Return the handler for ``task_type``, or ``None`` when unknown."""
    return _HANDLERS.get(task_type)


TASK_TYPE_CHOICES: tuple[tuple[str, str], ...] = tuple(
    (handler.task_type, handler.label) for handler in _HANDLERS.values()
)
