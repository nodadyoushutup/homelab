"""Task CRUD pages, detail view, and standalone execution."""

from __future__ import annotations

import json

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import func, select

from torrent_manager.extensions import db
from torrent_manager.models.pipeline import PipelineStep
from torrent_manager.models.task import Task
from torrent_manager.services.tasks import TASK_TYPE_CHOICES, execute_task
from torrent_manager.utils.pagination import DEFAULT_PAGE_SIZE, paginate

tasks_bp = Blueprint("tasks", __name__, url_prefix="/tasks")

_TASK_TYPE_VALUES = {task_type for task_type, _label in TASK_TYPE_CHOICES}


def _form_fields() -> dict[str, str | None]:
    return {
        "name": (request.form.get("name") or "").strip(),
        "description": (request.form.get("description") or "").strip() or None,
        "task_type": (request.form.get("task_type") or "noop").strip(),
        "config_json": (request.form.get("config_json") or "").strip() or None,
    }


def _validate_fields(fields: dict[str, str | None]) -> list[str]:
    errors: list[str] = []
    if not fields["name"]:
        errors.append("Name is required.")
    if fields["task_type"] not in _TASK_TYPE_VALUES:
        errors.append("Task type is invalid.")
    if fields["config_json"]:
        try:
            parsed = json.loads(fields["config_json"])
        except json.JSONDecodeError:
            errors.append("Config must be valid JSON.")
        else:
            if not isinstance(parsed, dict):
                errors.append("Config JSON must be an object.")
    return errors


def _page_number() -> int:
    try:
        return max(1, int(request.args.get("page", "1")))
    except ValueError:
        return 1


@tasks_bp.get("/")
def list_tasks():
    """Paginated task list."""
    page = paginate(
        Task,
        page=_page_number(),
        per_page=DEFAULT_PAGE_SIZE,
        order_by=Task.created_at.desc(),
    )
    return render_template("tasks/list.html", page=page)


@tasks_bp.route("/new", methods=["GET", "POST"])
def create_task():
    """Create a task definition."""
    if request.method == "GET":
        return render_template(
            "tasks/form.html",
            task=None,
            task_type_choices=TASK_TYPE_CHOICES,
            form_action=url_for("tasks.create_task"),
            page_title="Add task",
        )

    fields = _form_fields()
    errors = _validate_fields(fields)
    if errors:
        for message in errors:
            flash(message, "error")
        return render_template(
            "tasks/form.html",
            task=fields,
            task_type_choices=TASK_TYPE_CHOICES,
            form_action=url_for("tasks.create_task"),
            page_title="Add task",
        ), 400

    Task.create(**fields)
    flash("Task created.", "success")
    return redirect(url_for("tasks.list_tasks"))


@tasks_bp.get("/<int:task_id>")
def task_detail(task_id: int):
    """Show one task and where it is used."""
    task = Task.get_by_id(task_id)
    if task is None:
        flash("Task not found.", "error")
        return redirect(url_for("tasks.list_tasks"))

    pipeline_steps = list(
        db.session.scalars(
            select(PipelineStep)
            .where(PipelineStep.task_id == task.id)
            .order_by(PipelineStep.created_at.desc())
        )
    )

    return render_template(
        "tasks/detail.html",
        task=task,
        pipeline_steps=pipeline_steps,
    )


@tasks_bp.route("/<int:task_id>/edit", methods=["GET", "POST"])
def edit_task(task_id: int):
    """Update a task definition."""
    task = Task.get_by_id(task_id)
    if task is None:
        flash("Task not found.", "error")
        return redirect(url_for("tasks.list_tasks"))

    if request.method == "GET":
        return render_template(
            "tasks/form.html",
            task=task,
            task_type_choices=TASK_TYPE_CHOICES,
            form_action=url_for("tasks.edit_task", task_id=task.id),
            page_title="Edit task",
        )

    fields = _form_fields()
    errors = _validate_fields(fields)
    if errors:
        for message in errors:
            flash(message, "error")
        return render_template(
            "tasks/form.html",
            task={**task.to_dict(), **fields},
            task_type_choices=TASK_TYPE_CHOICES,
            form_action=url_for("tasks.edit_task", task_id=task.id),
            page_title="Edit task",
        ), 400

    task.update_from_dict(fields).save()
    flash("Task updated.", "success")
    return redirect(url_for("tasks.task_detail", task_id=task.id))


@tasks_bp.post("/<int:task_id>/run")
def run_task(task_id: int):
    """Execute one task in isolation."""
    task = Task.get_by_id(task_id)
    if task is None:
        flash("Task not found.", "error")
        return redirect(url_for("tasks.list_tasks"))

    result = execute_task(task)
    if result.success:
        flash("Task completed.", "success")
    else:
        flash(result.error or "Task failed.", "error")
    return redirect(url_for("tasks.task_detail", task_id=task.id))


@tasks_bp.post("/<int:task_id>/delete")
def delete_task(task_id: int):
    """Delete a task when it is not referenced by a pipeline."""
    task = Task.get_by_id(task_id)
    if task is None:
        flash("Task not found.", "error")
        return redirect(url_for("tasks.list_tasks"))

    in_use = db.session.scalar(
        select(func.count())
        .select_from(PipelineStep)
        .where(PipelineStep.task_id == task.id)
    ) or 0
    if in_use:
        flash("Task is used by a pipeline and cannot be deleted.", "error")
        return redirect(url_for("tasks.task_detail", task_id=task.id))

    Task.delete_by_id(task_id)
    flash("Task deleted.", "success")
    return redirect(url_for("tasks.list_tasks"))
