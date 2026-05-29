"""Task and pipeline model tests."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from torrent_manager.app import create_app  # noqa: E402
from torrent_manager.config import load_config  # noqa: E402
from torrent_manager.extensions import db  # noqa: E402
from torrent_manager.models.pipeline import Pipeline, PipelineStatus, PipelineStep  # noqa: E402
from torrent_manager.models.task import Task, TaskRunStatus  # noqa: E402
from torrent_manager.services.pipelines import run_pipeline  # noqa: E402
from torrent_manager.services.tasks import execute_task  # noqa: E402
from torrent_manager.utils.pagination import paginate  # noqa: E402


class TaskPipelineModelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.app = create_app(load_config(testing=True))
        self.ctx = self.app.app_context()
        self.ctx.push()
        db.drop_all()
        db.create_all()

    def tearDown(self) -> None:
        db.session.remove()
        self.ctx.pop()

    def test_execute_task_log_handler(self) -> None:
        task = Task.create(
            name="Say hello",
            task_type="log",
            config_json='{"message": "hello"}',
        )
        result = execute_task(task)
        self.assertTrue(result.success)
        self.assertEqual(task.last_status_enum, TaskRunStatus.COMPLETED)
        self.assertEqual(task.last_output, "hello")

    def test_run_pipeline_executes_steps_in_order(self) -> None:
        first = Task.create(name="First", task_type="log", config_json='{"message": "one"}')
        second = Task.create(name="Second", task_type="log", config_json='{"message": "two"}')
        pipeline = Pipeline.create(name="Deploy flow")
        PipelineStep.create(pipeline_id=pipeline.id, task_id=first.id, position=0)
        PipelineStep.create(pipeline_id=pipeline.id, task_id=second.id, position=1)

        run_pipeline(pipeline)
        pipeline = Pipeline.get_by_id(pipeline.id)
        assert pipeline is not None
        self.assertEqual(pipeline.status_enum, PipelineStatus.COMPLETED)
        self.assertEqual(pipeline.progress_percent, 100)
        steps = pipeline.ordered_steps()
        self.assertEqual(steps[0].output, "one")
        self.assertEqual(steps[1].output, "two")

    def test_paginate_tasks(self) -> None:
        for index in range(3):
            Task.create(name=f"Task {index}", task_type="noop")
        page = paginate(Task, page=1, per_page=2, order_by=Task.id.asc())
        self.assertEqual(len(page.items), 2)
        self.assertEqual(page.total, 3)
        self.assertEqual(page.total_pages, 2)


if __name__ == "__main__":
    unittest.main()
