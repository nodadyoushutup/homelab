"""Execute pipeline steps in order."""

from __future__ import annotations

from torrent_manager.extensions import db
from torrent_manager.models.base import utcnow
from torrent_manager.models.pipeline import Pipeline, PipelineStatus, PipelineStep
from torrent_manager.models.task import TaskRunStatus
from torrent_manager.services.tasks.context import TaskContext
from torrent_manager.services.tasks.executor import execute_task


class PipelineRunError(RuntimeError):
    """Raised when a pipeline cannot be started."""


def run_pipeline(pipeline: Pipeline) -> Pipeline:
    """Run every step in order, stopping on the first failure."""
    if not pipeline.steps:
        raise PipelineRunError("Pipeline has no steps.")

    if pipeline.status_enum == PipelineStatus.RUNNING:
        raise PipelineRunError("Pipeline is already running.")

    pipeline.status = PipelineStatus.RUNNING.value
    pipeline.started_at = utcnow()
    pipeline.finished_at = None
    pipeline.save()

    for step in pipeline.ordered_steps():
        step.status = TaskRunStatus.RUNNING.value
        step.output = None
        step.error = None
        step.started_at = utcnow()
        step.finished_at = None
        step.save()

        result = execute_task(
            step.task,
            TaskContext(
                pipeline_id=pipeline.id,
                pipeline_step_id=step.id,
                step_position=step.position,
            ),
        )

        step.output = result.output or None
        step.error = result.error
        step.finished_at = utcnow()
        if result.success:
            step.status = TaskRunStatus.COMPLETED.value
            step.save()
            continue

        step.status = TaskRunStatus.FAILED.value
        step.save()
        pipeline.status = PipelineStatus.FAILED.value
        pipeline.finished_at = utcnow()
        pipeline.save()
        return pipeline

    pipeline.status = PipelineStatus.COMPLETED.value
    pipeline.finished_at = utcnow()
    pipeline.save()
    return pipeline


def reset_pipeline(pipeline: Pipeline) -> Pipeline:
    """Return a pipeline to a draft state and clear step run metadata."""
    pipeline.status = PipelineStatus.DRAFT.value
    pipeline.started_at = None
    pipeline.finished_at = None
    for step in pipeline.steps:
        step.status = TaskRunStatus.PENDING.value
        step.output = None
        step.error = None
        step.started_at = None
        step.finished_at = None
    db.session.commit()
    return pipeline
