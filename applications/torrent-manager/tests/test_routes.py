"""HTTP route smoke tests."""

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
from torrent_manager.models.torrent import Torrent  # noqa: E402
from torrent_manager.models.task import Task  # noqa: E402
from torrent_manager.models.pipeline import Pipeline  # noqa: E402


class RouteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.app = create_app(load_config(testing=True))
        self.client = self.app.test_client()
        with self.app.app_context():
            db.drop_all()
            db.create_all()

    def test_healthz(self) -> None:
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "ok"})

    def test_create_and_list_torrent(self) -> None:
        response = self.client.post(
            "/torrents/new",
            data={
                "name": "Linux ISO",
                "magnet_uri": "magnet:?xt=urn:btih:abc",
                "status": "queued",
            },
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Linux ISO", response.data)

        with self.app.app_context():
            self.assertEqual(Torrent.count(), 1)

    def test_create_torrent_with_error_status(self) -> None:
        response = self.client.post(
            "/torrents/new",
            data={
                "name": "Failed download",
                "magnet_uri": "magnet:?xt=urn:btih:bad",
                "status": "error",
            },
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"badge-error", response.data)
        self.assertIn(b"Failed download", response.data)

        with self.app.app_context():
            torrent = Torrent.list_all()[0]
            self.assertEqual(torrent.status, "error")

    def test_tasks_list_and_create(self) -> None:
        response = self.client.get("/tasks/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"No tasks yet", response.data)

        response = self.client.post(
            "/tasks/new",
            data={
                "name": "Warmup",
                "task_type": "noop",
                "config_json": "{}",
            },
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Warmup", response.data)

        with self.app.app_context():
            task = Task.list_all()[0]
            detail = self.client.get(f"/tasks/{task.id}")
            self.assertEqual(detail.status_code, 200)
            self.assertIn(b"Run task", detail.data)

    def test_pipeline_detail_shows_progress(self) -> None:
        with self.app.app_context():
            task = Task.create(name="Step A", task_type="noop")
            pipeline = Pipeline.create(name="Release")
            from torrent_manager.models.pipeline import PipelineStep

            PipelineStep.create(pipeline_id=pipeline.id, task_id=task.id, position=0)
            pipeline_id = pipeline.id

        response = self.client.get(f"/pipelines/{pipeline_id}")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Release", response.data)
        self.assertIn(b"Progress", response.data)


if __name__ == "__main__":
    unittest.main()
