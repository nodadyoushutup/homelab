"""Task execution framework."""

from __future__ import annotations

from torrent_manager.services.tasks.context import TaskContext
from torrent_manager.services.tasks.executor import TaskExecutionError, execute_task
from torrent_manager.services.tasks.handlers import TASK_TYPE_CHOICES, get_handler
from torrent_manager.services.tasks.result import TaskResult

__all__ = [
    "TASK_TYPE_CHOICES",
    "TaskContext",
    "TaskExecutionError",
    "TaskResult",
    "execute_task",
    "get_handler",
]
