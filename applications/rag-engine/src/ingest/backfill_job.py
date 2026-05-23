"""In-process async backfill job (single worker thread per rag-engine task)."""
from __future__ import annotations

import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from ingest.backfill import BackfillOptions

log = logging.getLogger(__name__)

STATUS_IDLE = "idle"
STATUS_RUNNING = "running"
STATUS_STOPPING = "stopping"
STATUS_STOPPED = "stopped"
STATUS_COMPLETED = "completed"
STATUS_FAILED = "failed"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


@dataclass
class BackfillJobSnapshot:
    status: str = STATUS_IDLE
    started_at: str | None = None
    finished_at: str | None = None
    exit_code: int | None = None
    files_seen: int = 0
    files_completed: int = 0
    last_path: str = ""
    result: dict[str, Any] = field(default_factory=dict)
    error: str = ""

    def to_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {
            "status": self.status,
            "files_seen": self.files_seen,
            "files_completed": self.files_completed,
        }
        if self.started_at:
            out["started_at"] = self.started_at
        if self.finished_at:
            out["finished_at"] = self.finished_at
        if self.last_path:
            out["last_path"] = self.last_path
        if self.exit_code is not None:
            out["exit_code"] = self.exit_code
        if self.result:
            out["result"] = self.result
        if self.error:
            out["error"] = self.error
        return out


class BackfillJobManager:
    """One background backfill at a time (Swarm default replicas=1)."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._cancel = threading.Event()
        self._thread: threading.Thread | None = None
        self._snapshot = BackfillJobSnapshot()

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return self._snapshot.to_dict()

    def _is_active_locked(self) -> bool:
        return self._snapshot.status in (STATUS_RUNNING, STATUS_STOPPING)

    def _progress_callback(self, update: dict[str, Any]) -> None:
        with self._lock:
            if "files_seen" in update:
                self._snapshot.files_seen = int(update["files_seen"])
            if "files_completed" in update:
                self._snapshot.files_completed = int(update["files_completed"])
            if "last_path" in update:
                self._snapshot.last_path = str(update["last_path"])

    def _worker(self, opts: BackfillOptions) -> None:
        from ingest.backfill import run_backfill

        try:
            code, payload = run_backfill(
                opts,
                interactive=False,
                cancel_event=self._cancel,
                on_progress=self._progress_callback,
            )
            with self._lock:
                self._snapshot.exit_code = code
                self._snapshot.result = payload
                if self._cancel.is_set() or payload.get("user_stopped"):
                    self._snapshot.status = STATUS_STOPPED
                elif code == 0:
                    self._snapshot.status = STATUS_COMPLETED
                else:
                    self._snapshot.status = STATUS_FAILED
                self._snapshot.finished_at = _utc_now_iso()
                if "files_seen" in payload:
                    self._snapshot.files_seen = int(payload["files_seen"])
                if "files_completed" in payload:
                    self._snapshot.files_completed = int(payload["files_completed"])
        except Exception as exc:
            log.exception("backfill job failed")
            with self._lock:
                self._snapshot.status = STATUS_FAILED
                self._snapshot.error = str(exc)
                self._snapshot.finished_at = _utc_now_iso()
                self._snapshot.exit_code = 1
        finally:
            with self._lock:
                self._thread = None
                self._cancel = threading.Event()

    def start(self, opts: BackfillOptions) -> tuple[int, dict[str, Any]]:
        """Return ``(http_status, json_body)``."""
        if not opts.yes and not opts.dry_run:
            return 400, {
                "error": "confirm_required",
                "message": "Pass confirm=true for mutating backfill runs.",
            }

        if opts.dry_run:
            from ingest.backfill import run_backfill

            code, payload = run_backfill(opts, interactive=False)
            return 200, {"exit_code": code, **payload}

        with self._lock:
            if self._is_active_locked():
                return 409, {
                    "error": "backfill_already_running",
                    "message": "A backfill job is already active.",
                    **self._snapshot.to_dict(),
                }
            self._cancel = threading.Event()
            self._snapshot = BackfillJobSnapshot(
                status=STATUS_RUNNING,
                started_at=_utc_now_iso(),
            )
            thread = threading.Thread(
                target=self._worker,
                args=(opts,),
                name="rag-backfill",
                daemon=True,
            )
            self._thread = thread
            thread.start()
            return 202, {
                "status": STATUS_RUNNING,
                "started_at": self._snapshot.started_at,
                "message": "Backfill started; watch rag-engine logs for progress.",
            }

    def stop(self) -> tuple[int, dict[str, Any]]:
        with self._lock:
            if not self._is_active_locked():
                return 404, {
                    "error": "backfill_not_running",
                    "message": "No active backfill job.",
                    **self._snapshot.to_dict(),
                }
            self._cancel.set()
            if self._snapshot.status == STATUS_RUNNING:
                self._snapshot.status = STATUS_STOPPING
            snap = self._snapshot.to_dict()
        return 202, {
            "status": STATUS_STOPPING,
            "message": "Stop requested; current file may finish before the job exits.",
            **snap,
        }


_manager: BackfillJobManager | None = None
_manager_lock = threading.Lock()


def backfill_job_manager() -> BackfillJobManager:
    global _manager
    with _manager_lock:
        if _manager is None:
            _manager = BackfillJobManager()
        return _manager
