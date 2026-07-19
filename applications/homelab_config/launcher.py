"""Launch the homelab-config web server.

Dependencies are installed by the container image (see the Dockerfile /
requirements.txt), so this simply configures logging and starts serving.
"""

from __future__ import annotations

import logging

from homelab_config.logging_setup import (
    configure_colored_logging,
    configure_logging,
)

logger = logging.getLogger(__name__)


def main() -> int:
    """Configure logging and run the web server.

    Returns:
        Process exit code.
    """
    configure_logging()
    configure_colored_logging()
    logger.info("Starting homelab-config")

    from homelab_config.server import run_server

    return run_server()
