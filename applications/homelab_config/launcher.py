"""Bootstrap the virtualenv, then launch the homelab-config web server.

Mirrors the project-root ``bootstrap.py`` flow: run under system Python first,
ensure/activate the shared ``.venv`` (re-executing this process into it when
needed), install this app's requirements, and only then import Flask and start
serving. Flask and friends are imported lazily so this module can run before the
virtualenv exists.
"""

from __future__ import annotations

import logging

from bootstrap.logging_setup import configure_colored_logging, configure_logging
from bootstrap.venv import ProjectVenv, VenvEnsureError

from homelab_config.paths import REQUIREMENTS

logger = logging.getLogger(__name__)


def main() -> int:
    """Ensure the virtualenv is ready, then run the web server.

    Returns:
        Process exit code.
    """
    configure_logging()
    logger.info("Starting homelab-config")

    try:
        venv = ProjectVenv()
        venv.ensure()
        # May re-exec this process under the venv interpreter.
        venv.activate()
        venv.install_requirements(REQUIREMENTS)
    except VenvEnsureError as exc:
        logger.error("%s", exc)
        return 1

    # Safe only after activation (and re-exec into `.venv` when needed).
    configure_colored_logging()
    logger.info("Project virtualenv is ready and active")

    # Imported lazily: Flask is only available after the venv install above.
    from homelab_config.server import run_server

    return run_server()
