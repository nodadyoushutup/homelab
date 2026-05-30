"""Flask application factory."""

from __future__ import annotations

from flask import Flask, render_template

from torrent_manager.config import Config, load_config
from torrent_manager.extensions import db
from torrent_manager.models import Pipeline, PipelineStep, Task, Torrent  # noqa: F401 — register metadata
from torrent_manager.routes import clients_bp, health_bp, pipelines_bp, tasks_bp, torrents_bp
from torrent_manager.services.qbittorrent import QBitTorrentRegistry


def create_app(config: Config | None = None) -> Flask:
    """Build and configure the Flask application."""
    app = Flask(__name__, template_folder="templates", static_folder="static")
    settings = config or load_config()

    app.config.update(
        SECRET_KEY=settings.secret_key,
        SQLALCHEMY_DATABASE_URI=settings.database_url,
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        SQLALCHEMY_ECHO=settings.sqlalchemy_echo,
        TESTING=settings.testing,
    )

    db.init_app(app)
    registry = QBitTorrentRegistry(settings.qbittorrent_clients)
    app.extensions["qbittorrent_registry"] = registry

    app.register_blueprint(health_bp)
    app.register_blueprint(clients_bp)
    app.register_blueprint(torrents_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(pipelines_bp)

    @app.get("/")
    def index():
        """Landing page with quick stats."""
        statuses = registry.all_statuses()
        connected_clients = sum(1 for status in statuses if status.connected)
        return render_template(
            "index.html",
            torrent_count=Torrent.count(),
            client_count=len(statuses),
            connected_client_count=connected_clients,
        )

    with app.app_context():
        db.create_all()

    return app
