"""Logging configuration for the bootstrap application."""

from __future__ import annotations

import logging
import sys

logger = logging.getLogger(__name__)

_BASIC_FORMAT = "%(asctime)s %(name)s %(levelname)s %(message)s"


def configure_logging(level: str = "INFO") -> None:
    """Install stdlib console logging safe to use before the venv is ready.

    Args:
        level: Root log level name (for example ``INFO`` or ``DEBUG``).
    """
    root = logging.getLogger()
    root.setLevel(level)
    if root.handlers:
        logger.info("Stdlib logging already configured at level %s", level)
        return
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter(_BASIC_FORMAT))
    root.addHandler(handler)
    logger.info("Configured stdlib logging at level %s", level)


def configure_colored_logging(level: str = "INFO") -> None:
    """Install coloredlogs after the project venv is active and deps are available.

    ``coloredlogs`` is imported inside this function so bootstrap can start under
    system Python before the virtualenv exists.

    Args:
        level: Root log level name (for example ``INFO`` or ``DEBUG``).
    """
    try:
        import coloredlogs
    except ImportError:
        configure_logging(level=level)
        logger.info(
            "coloredlogs is not installed yet; continuing with stdlib logging"
        )
        return

    coloredlogs.install(level=level, logger=logging.getLogger())
    logger.info("Configured coloredlogs at level %s", level)
