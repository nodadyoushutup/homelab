"""Flask application factory and web server entrypoint for homelab-config."""

from __future__ import annotations

import logging
import os

from flask import Flask, render_template

from homelab_config.extensions import db, socketio
from homelab_config.models import (
    DEFAULT_SSH_USER,
    ROLE_MANAGER,
    ROLE_WORKER,
    SwarmNode,
)
from homelab_config.paths import (
    DATA_DIR,
    DATABASE_PATH,
    DEFAULT_HOST,
    DEFAULT_PORT,
)

logger = logging.getLogger(__name__)


def create_app() -> Flask:
    """Build and configure the Flask application.

    Returns:
        A ready-to-serve Flask app with the database created and seeded.
    """
    app = Flask(__name__)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    app.config["SQLALCHEMY_DATABASE_URI"] = f"sqlite:///{DATABASE_PATH}"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    db.init_app(app)
    socketio.init_app(app, cors_allowed_origins="*", async_mode="threading")

    from homelab_config.api.swarm import bp as swarm_bp

    app.register_blueprint(swarm_bp)

    @app.route("/")
    def index():  # noqa: ANN202 - Flask view
        return render_template("swarm.html", active="swarm")

    with app.app_context():
        db.create_all()
        _seed_defaults()

    return app


def _seed_defaults() -> None:
    """Seed the standard swarm topology on first run (empty database only)."""
    if SwarmNode.query.count() > 0:
        return

    logger.info("Seeding default swarm topology (control plane + 5 workers)")
    nodes = [
        SwarmNode(
            name="swarm-cp-0",
            host="swarm-cp-0.local",
            role=ROLE_MANAGER,
            ssh_user=DEFAULT_SSH_USER,
        )
    ]
    for index in range(5):
        nodes.append(
            SwarmNode(
                name=f"swarm-wk-{index}",
                host=f"swarm-wk-{index}.local",
                role=ROLE_WORKER,
                ssh_user=DEFAULT_SSH_USER,
            )
        )
    for node in nodes:
        node.labels = {}
    db.session.add_all(nodes)
    db.session.commit()


def run_server() -> int:
    """Run the homelab-config web server.

    Honors ``HOMELAB_CONFIG_HOST`` and ``HOMELAB_CONFIG_PORT`` overrides.

    Returns:
        Process exit code.
    """
    app = create_app()
    host = os.environ.get("HOMELAB_CONFIG_HOST", DEFAULT_HOST)
    port = int(os.environ.get("HOMELAB_CONFIG_PORT", str(DEFAULT_PORT)))
    logger.info("homelab-config listening on http://%s:%d", host, port)
    # allow_unsafe_werkzeug lets the bundled dev server run outside debug mode.
    socketio.run(app, host=host, port=port, allow_unsafe_werkzeug=True)
    return 0


__all__ = ["create_app", "run_server"]
