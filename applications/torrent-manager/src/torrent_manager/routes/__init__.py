"""HTTP route blueprints."""

from __future__ import annotations

from torrent_manager.routes.clients import clients_bp
from torrent_manager.routes.health import health_bp
from torrent_manager.routes.pipelines import pipelines_bp
from torrent_manager.routes.tasks import tasks_bp
from torrent_manager.routes.torrents import torrents_bp

__all__ = ["clients_bp", "health_bp", "pipelines_bp", "tasks_bp", "torrents_bp"]
