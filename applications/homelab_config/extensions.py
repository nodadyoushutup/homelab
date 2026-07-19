"""Shared Flask extensions for the homelab-config application.

Instantiated here without an app so they can be imported anywhere without
circular imports, then bound to the app in
:func:`homelab_config.server.create_app`.
"""

from __future__ import annotations

from flask_socketio import SocketIO

# Threading async mode keeps the dependency footprint small (no eventlet/gevent).
socketio = SocketIO()
