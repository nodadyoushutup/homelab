"""Flask application factory and web server entrypoint for homelab-config."""

from __future__ import annotations

import atexit
import logging
import os
import signal
import time
from pathlib import Path

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
    PID_FILE,
)

logger = logging.getLogger(__name__)

# How long to wait for a previous instance to exit before escalating signals.
_TERM_WAIT_SECONDS = 5.0
_KILL_WAIT_SECONDS = 2.0
_POLL_INTERVAL_SECONDS = 0.1


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


def _pid_alive(pid: int) -> bool:
    """Return whether a process with ``pid`` currently exists."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _read_pidfile() -> int | None:
    """Return the PID recorded in the pidfile, or ``None`` when unavailable."""
    try:
        text = PID_FILE.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, OSError):
        return None
    try:
        return int(text)
    except ValueError:
        return None


def _process_is_homelab_config(pid: int) -> bool:
    """Return whether ``pid`` looks like a homelab-config server process.

    Guards against killing an unrelated process that happened to reuse the PID
    recorded in a stale pidfile.
    """
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except (FileNotFoundError, OSError):
        # No procfs (non-Linux) or process gone; trust the pidfile.
        return True
    text = cmdline.replace(b"\x00", b" ").decode("utf-8", "replace")
    return "config.py" in text or "homelab_config" in text


def _wait_for_exit(pid: int, timeout: float) -> bool:
    """Poll until ``pid`` exits or ``timeout`` elapses; return True if it exited."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not _pid_alive(pid):
            return True
        time.sleep(_POLL_INTERVAL_SECONDS)
    return not _pid_alive(pid)


def _terminate_existing() -> None:
    """Stop a previously launched server so this launch can take over."""
    pid = _read_pidfile()
    if pid is None or pid == os.getpid():
        return
    if not _pid_alive(pid) or not _process_is_homelab_config(pid):
        return

    logger.warning(
        "homelab-config already running (pid %d); restarting it", pid
    )
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    if _wait_for_exit(pid, _TERM_WAIT_SECONDS):
        logger.info("Previous homelab-config instance (pid %d) stopped", pid)
        return

    logger.warning(
        "pid %d did not exit after SIGTERM; sending SIGKILL", pid
    )
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    _wait_for_exit(pid, _KILL_WAIT_SECONDS)


def _remove_pidfile() -> None:
    """Remove the pidfile if it still points at this process."""
    if _read_pidfile() == os.getpid():
        try:
            PID_FILE.unlink()
        except FileNotFoundError:
            pass


def _write_pidfile() -> None:
    """Record this process's PID and schedule cleanup on exit."""
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    atexit.register(_remove_pidfile)


def run_server() -> int:
    """Run the homelab-config web server.

    If a previous instance is still running (recorded in the pidfile), it is
    stopped first so this launch replaces it. Honors ``HOMELAB_CONFIG_HOST`` and
    ``HOMELAB_CONFIG_PORT`` overrides.

    Returns:
        Process exit code.
    """
    _terminate_existing()
    _write_pidfile()

    app = create_app()
    host = os.environ.get("HOMELAB_CONFIG_HOST", DEFAULT_HOST)
    port = int(os.environ.get("HOMELAB_CONFIG_PORT", str(DEFAULT_PORT)))
    logger.info("homelab-config listening on http://%s:%d", host, port)
    # allow_unsafe_werkzeug lets the bundled dev server run outside debug mode.
    socketio.run(app, host=host, port=port, allow_unsafe_werkzeug=True)
    return 0


__all__ = ["create_app", "run_server"]
