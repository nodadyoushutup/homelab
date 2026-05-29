"""Model layer: abstract base, CRUD mixin, and concrete tables."""

from __future__ import annotations

from torrent_manager.models.base import BaseModel, BaseRecord, utcnow
from torrent_manager.models.crud import CRUDModel
from torrent_manager.models.pipeline import Pipeline, PipelineStatus, PipelineStep
from torrent_manager.models.task import Task, TaskRunStatus
from torrent_manager.models.torrent import Torrent, TorrentStatus

__all__ = [
    "BaseModel",
    "BaseRecord",
    "CRUDModel",
    "Pipeline",
    "PipelineStatus",
    "PipelineStep",
    "Task",
    "TaskRunStatus",
    "Torrent",
    "TorrentStatus",
    "utcnow",
]
