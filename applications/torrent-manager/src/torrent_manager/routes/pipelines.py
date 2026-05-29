"""Pipeline CRUD pages, detail view, step management, and execution."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select

from torrent_manager.extensions import db
from torrent_manager.models.pipeline import Pipeline, PipelineStatus, PipelineStep
from torrent_manager.models.task import Task, TaskRunStatus
from torrent_manager.services.pipelines import PipelineRunError, reset_pipeline, run_pipeline
from torrent_manager.utils.pagination import DEFAULT_PAGE_SIZE, paginate

pipelines_bp = Blueprint("pipelines", __name__, url_prefix="/pipelines")


def _form_fields() -> dict[str, str | None]:
    return {
        "name": (request.form.get("name") or "").strip(),
        "description": (request.form.get("description") or "").strip() or None,
    }


def _validate_fields(fields: dict[str, str | None]) -> list[str]:
    errors: list[str] = []
    if not fields["name"]:
        errors.append("Name is required.")
    return errors


def _page_number() -> int:
    try:
        return max(1, int(request.args.get("page", "1")))
    except ValueError:
        return 1


def _next_step_position(pipeline: Pipeline) -> int:
    if not pipeline.steps:
        return 0
    return max(step.position for step in pipeline.steps) + 1


@pipelines_bp.get("/")
def list_pipelines():
    """Paginated pipeline list."""
    page = paginate(
        Pipeline,
        page=_page_number(),
        per_page=DEFAULT_PAGE_SIZE,
        order_by=Pipeline.created_at.desc(),
    )
    return render_template("pipelines/list.html", page=page)


@pipelines_bp.route("/new", methods=["GET", "POST"])
def create_pipeline():
    """Create a pipeline shell; add steps on the detail page."""
    if request.method == "GET":
        return render_template(
            "pipelines/form.html",
            pipeline=None,
            form_action=url_for("pipelines.create_pipeline"),
            page_title="Add pipeline",
        )

    fields = _form_fields()
    errors = _validate_fields(fields)
    if errors:
        for message in errors:
            flash(message, "error")
        return render_template(
            "pipelines/form.html",
            pipeline=fields,
            form_action=url_for("pipelines.create_pipeline"),
            page_title="Add pipeline",
        ), 400

    pipeline = Pipeline.create(**fields)
    flash("Pipeline created.", "success")
    return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))


@pipelines_bp.get("/<int:pipeline_id>")
def pipeline_detail(pipeline_id: int):
    """Show pipeline metadata, ordered steps, and run progress."""
    pipeline = Pipeline.get_by_id(pipeline_id)
    if pipeline is None:
        flash("Pipeline not found.", "error")
        return redirect(url_for("pipelines.list_pipelines"))

    available_tasks = Task.list_all(order_by=Task.name.asc())
    return render_template(
        "pipelines/detail.html",
        pipeline=pipeline,
        steps=pipeline.ordered_steps(),
        available_tasks=available_tasks,
        can_run=pipeline.status_enum
        not in {PipelineStatus.RUNNING},
    )


@pipelines_bp.route("/<int:pipeline_id>/edit", methods=["GET", "POST"])
def edit_pipeline(pipeline_id: int):
    """Update pipeline metadata."""
    pipeline = Pipeline.get_by_id(pipeline_id)
    if pipeline is None:
        flash("Pipeline not found.", "error")
        return redirect(url_for("pipelines.list_pipelines"))

    if request.method == "GET":
        return render_template(
            "pipelines/form.html",
            pipeline=pipeline,
            form_action=url_for("pipelines.edit_pipeline", pipeline_id=pipeline.id),
            page_title="Edit pipeline",
        )

    fields = _form_fields()
    errors = _validate_fields(fields)
    if errors:
        for message in errors:
            flash(message, "error")
        return render_template(
            "pipelines/form.html",
            pipeline={**pipeline.to_dict(), **fields},
            form_action=url_for("pipelines.edit_pipeline", pipeline_id=pipeline.id),
            page_title="Edit pipeline",
        ), 400

    pipeline.update_from_dict(fields).save()
    flash("Pipeline updated.", "success")
    return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))


@pipelines_bp.post("/<int:pipeline_id>/steps/add")
def add_pipeline_step(pipeline_id: int):
    """Append a task to the end of a pipeline."""
    pipeline = Pipeline.get_by_id(pipeline_id)
    if pipeline is None:
        flash("Pipeline not found.", "error")
        return redirect(url_for("pipelines.list_pipelines"))

    task_id_raw = (request.form.get("task_id") or "").strip()
    try:
        task_id = int(task_id_raw)
    except ValueError:
        flash("Select a task to add.", "error")
        return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))

    task = Task.get_by_id(task_id)
    if task is None:
        flash("Task not found.", "error")
        return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))

    PipelineStep.create(
        pipeline_id=pipeline.id,
        task_id=task.id,
        position=_next_step_position(pipeline),
        status=TaskRunStatus.PENDING.value,
        commit=False,
    )
    if pipeline.status_enum == PipelineStatus.DRAFT:
        pipeline.status = PipelineStatus.PENDING.value
    pipeline.save()
    flash(f"Added task “{task.name}”.", "success")
    return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))


@pipelines_bp.post("/<int:pipeline_id>/steps/<int:step_id>/remove")
def remove_pipeline_step(pipeline_id: int, step_id: int):
    """Remove one step and compact positions."""
    pipeline = Pipeline.get_by_id(pipeline_id)
    if pipeline is None:
        flash("Pipeline not found.", "error")
        return redirect(url_for("pipelines.list_pipelines"))

    step = PipelineStep.get_by_id(step_id)
    if step is None or step.pipeline_id != pipeline.id:
        flash("Pipeline step not found.", "error")
        return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))

    removed_position = step.position
    step.delete(commit=False)
    db.session.flush()
    remaining = db.session.scalars(
        select(PipelineStep)
        .where(PipelineStep.pipeline_id == pipeline.id)
        .order_by(PipelineStep.position.asc())
    ).all()
    for index, remaining_step in enumerate(remaining):
        remaining_step.position = index
    if not remaining:
        pipeline.status = PipelineStatus.DRAFT.value
    db.session.commit()
    flash("Step removed.", "success")
    return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))


@pipelines_bp.post("/<int:pipeline_id>/run")
def run_pipeline_view(pipeline_id: int):
    """Execute the pipeline from the first pending step."""
    pipeline = Pipeline.get_by_id(pipeline_id)
    if pipeline is None:
        flash("Pipeline not found.", "error")
        return redirect(url_for("pipelines.list_pipelines"))

    try:
        run_pipeline(pipeline)
    except PipelineRunError as exc:
        flash(str(exc), "error")
        return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))

    if pipeline.status_enum == PipelineStatus.COMPLETED:
        flash("Pipeline completed.", "success")
    else:
        flash("Pipeline failed.", "error")
    return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))


@pipelines_bp.post("/<int:pipeline_id>/reset")
def reset_pipeline_view(pipeline_id: int):
    """Clear run state so the pipeline can be executed again."""
    pipeline = Pipeline.get_by_id(pipeline_id)
    if pipeline is None:
        flash("Pipeline not found.", "error")
        return redirect(url_for("pipelines.list_pipelines"))

    reset_pipeline(pipeline)
    flash("Pipeline reset to draft.", "success")
    return redirect(url_for("pipelines.pipeline_detail", pipeline_id=pipeline.id))


@pipelines_bp.post("/<int:pipeline_id>/delete")
def delete_pipeline(pipeline_id: int):
    """Delete a pipeline and its steps."""
    deleted = Pipeline.delete_by_id(pipeline_id)
    if deleted:
        flash("Pipeline deleted.", "success")
    else:
        flash("Pipeline not found.", "error")
    return redirect(url_for("pipelines.list_pipelines"))
