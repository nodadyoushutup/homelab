"""Shared Flask extensions for the homelab-config application.

Extensions are instantiated here without an app so they can be imported by
models, blueprints, and the app factory without circular imports. They are bound
to the app in :func:`homelab_config.server.create_app`.
"""

from __future__ import annotations

from flask_socketio import SocketIO
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
# Threading async mode keeps the dependency footprint small (no eventlet/gevent).
socketio = SocketIO()
