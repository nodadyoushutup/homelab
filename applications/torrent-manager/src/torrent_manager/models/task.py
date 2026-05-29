"""Persisted task definitions — units of work executed standalone or in a pipeline."""

from __future__ import annotations

import json
from enum import StrEnum
from typing import Any

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from torrent_manager.models.crud import CRUDModel


class TaskRunStatus(StrEnum):
    """Result of the most recent standalone or pipeline step run."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class Task(CRUDModel):
    """A reusable unit of work with its own handler and JSON config."""

    __tablename__ = "tasks"

    name: Mapped[str] = mapped_column(String(256), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    task_type: Mapped[str] = mapped_column(String(64), nullable=False, default="noop")
    config_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=TaskRunStatus.PENDING.value,
    )
    last_output: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)

    def config(self) -> dict[str, Any]:
        """Return parsed task config, or an empty mapping when unset."""
        if not self.config_json:
            return {}
        try:
            parsed = json.loads(self.config_json)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}

    def set_config(self, value: dict[str, Any] | None) -> None:
        """Serialize a mapping into ``config_json``."""
        if not value:
            self.config_json = None
            return
        self.config_json = json.dumps(value, indent=2, sort_keys=True)

    @property
    def last_status_enum(self) -> TaskRunStatus:
        return TaskRunStatus(self.last_status)
