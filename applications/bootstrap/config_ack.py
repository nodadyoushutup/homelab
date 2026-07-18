"""Require the operator to acknowledge live config files are set up."""

from __future__ import annotations

import logging
from pathlib import Path

from bootstrap.paths import CONFIG_DIR, display_path
from bootstrap.prompt import OperatorPrompt

logger = logging.getLogger(__name__)


class ConfigAcknowledger:
    """Gate bootstrap on the operator confirming live config is filled in."""

    def __init__(
        self,
        config_dir: Path = CONFIG_DIR,
        prompt: OperatorPrompt | None = None,
    ) -> None:
        """Initialize the acknowledger.

        Args:
            config_dir: Root of the site config tree.
            prompt: Operator confirmation collaborator.
        """
        self._config_dir = config_dir
        self._prompt = prompt or OperatorPrompt()

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the repo root that owns config_dir.

        Args:
            path: Path to render.

        Returns:
            Repo-relative display string.
        """
        return display_path(path, root=self._config_dir.parent)

    def run(self) -> None:
        """Warn about live config, then block until the operator confirms setup.

        This step is required: any non-affirmative answer re-asks the question
        until the operator acknowledges that their live config files under
        ``.config`` contain real values.
        """
        logger.warning(
            "Update your live config files under %s with real values before "
            "continuing. The scaffolded files start from *.example placeholders "
            "and must be filled in for Terraform, Swarm, and CI/CD to work.",
            self._rel(self._config_dir),
        )
        self._prompt.require_yes(
            f"Have you updated your live config files under "
            f"{self._rel(self._config_dir)} with real values?",
            default=True,
        )
        logger.info(
            "Configuration acknowledged: live config files under %s are set up",
            self._rel(self._config_dir),
        )


__all__ = ["ConfigAcknowledger"]
