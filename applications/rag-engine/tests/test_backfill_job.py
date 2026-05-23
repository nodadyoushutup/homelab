import threading
import time
import unittest
from types import SimpleNamespace

from ingest.backfill_job import (
    STATUS_RUNNING,
    STATUS_STOPPED,
    BackfillJobManager,
)


def _opts(**kwargs):
    base = {
        "dry_run": False,
        "max_files": 0,
        "commit": "",
        "json_summary": False,
        "yes": False,
        "force": False,
        "prune_orphans_only": False,
        "prune_dry_run": False,
    }
    base.update(kwargs)
    return SimpleNamespace(**base)


def _install_stop_worker(mgr: BackfillJobManager) -> None:
    def worker(opts) -> None:
        while not mgr._cancel.is_set():
            time.sleep(0.01)
        with mgr._lock:
            mgr._snapshot.exit_code = 130
            mgr._snapshot.result = {"user_stopped": True, "files_seen": 2, "files_completed": 1}
            mgr._snapshot.status = STATUS_STOPPED
            mgr._snapshot.finished_at = "2026-01-01T00:00:00+00:00"
            mgr._thread = None
            mgr._cancel = threading.Event()

    mgr._worker = worker  # type: ignore[method-assign]


def _install_gate_worker(mgr: BackfillJobManager, gate: threading.Event) -> None:
    def worker(opts) -> None:
        gate.set()
        while not mgr._cancel.is_set():
            time.sleep(0.01)
        with mgr._lock:
            mgr._snapshot.exit_code = 0
            mgr._snapshot.result = {"files_seen": 0, "files_completed": 0}
            mgr._snapshot.status = "completed"
            mgr._snapshot.finished_at = "2026-01-01T00:00:00+00:00"
            mgr._thread = None
            mgr._cancel = threading.Event()

    mgr._worker = worker  # type: ignore[method-assign]


class BackfillJobManagerTests(unittest.TestCase):
    def test_start_requires_confirm(self) -> None:
        mgr = BackfillJobManager()
        code, body = mgr.start(_opts(yes=False))
        self.assertEqual(code, 400)
        self.assertEqual(body["error"], "confirm_required")

    def test_start_stop_background_job(self) -> None:
        mgr = BackfillJobManager()
        _install_stop_worker(mgr)
        code, body = mgr.start(_opts(yes=True))
        self.assertEqual(code, 202)
        self.assertEqual(body["status"], STATUS_RUNNING)
        stop_code, _ = mgr.stop()
        self.assertEqual(stop_code, 202)
        deadline = time.time() + 3.0
        while time.time() < deadline:
            if mgr.snapshot()["status"] == STATUS_STOPPED:
                break
            time.sleep(0.05)
        snap = mgr.snapshot()
        self.assertEqual(snap["status"], STATUS_STOPPED)
        self.assertTrue(snap["result"]["user_stopped"])

    def test_second_start_returns_conflict(self) -> None:
        mgr = BackfillJobManager()
        gate = threading.Event()
        _install_gate_worker(mgr, gate)
        code, _ = mgr.start(_opts(yes=True))
        self.assertEqual(code, 202)
        self.assertTrue(gate.wait(timeout=2.0))
        code2, body2 = mgr.start(_opts(yes=True))
        self.assertEqual(code2, 409)
        self.assertEqual(body2["error"], "backfill_already_running")
        mgr._cancel.set()


if __name__ == "__main__":
    unittest.main()
