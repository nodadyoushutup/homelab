"""Pipelines chain tasks together and track ordered step progress."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from torrent_manager.models.crud import CRUDModel
from torrent_manager.models.task import Task, TaskRunStatus


class PipelineStatus(StrEnum):
    """Lifecycle state for a pipeline definition / run."""

    DRAFT = "draft"
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Pipeline(CRUDModel):
    """An ordered sequence of :class:`Task` rows executed as a CI/CD-style chain."""

    __tablename__ = "pipelines"

    name: Mapped[str] = mapped_column(String(256), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=PipelineStatus.DRAFT.value,
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    steps: Mapped[list[PipelineStep]] = relationship(
        "PipelineStep",
        back_populates="pipeline",
        order_by="PipelineStep.position",
        cascade="all, delete-orphan",
    )

    @property
    def status_enum(self) -> PipelineStatus:
        return PipelineStatus(self.status)

    @property
    def step_count(self) -> int:
        return len(self.steps)

    @property
    def completed_step_count(self) -> int:
        return sum(1 for step in self.steps if step.status_enum == TaskRunStatus.COMPLETED)

    @property
    def progress_percent(self) -> int:
        if not self.steps:
            return 0
        return int(round((self.completed_step_count / len(self.steps)) * 100))

    def ordered_steps(self) -> list[PipelineStep]:
        return sorted(self.steps, key=lambda step: step.position)


class PipelineStep(CRUDModel):
    """One task slot inside a pipeline, with its own run status and output."""

    __tablename__ = "pipeline_steps"
    __table_args__ = (
        UniqueConstraint("pipeline_id", "position", name="uq_pipeline_step_position"),
    )

    pipeline_id: Mapped[int] = mapped_column(ForeignKey("pipelines.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[int] = mapped_column(ForeignKey("tasks.id", ondelete="RESTRICT"), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=TaskRunStatus.PENDING.value,
    )
    output: Mapped[str | None] = mapped_column(Text, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    pipeline: Mapped[Pipeline] = relationship("Pipeline", back_populates="steps")
    task: Mapped[Task] = relationship("Task")

    @property
    def status_enum(self) -> TaskRunStatus:
        return TaskRunStatus(self.status)
