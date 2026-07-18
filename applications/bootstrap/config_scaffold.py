"""Scaffold live `.config` files from tracked `*.example` templates."""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from bootstrap.paths import CONFIG_DIR, display_path
from bootstrap.prompt import OperatorPrompt

logger = logging.getLogger(__name__)

_EXAMPLE_SUFFIX = ".example"


class ConfigScaffolder:
    """Copy ``*.example`` templates to live config paths under ``.config``."""

    def __init__(
        self,
        config_dir: Path = CONFIG_DIR,
        prompt: OperatorPrompt | None = None,
    ) -> None:
        """Initialize the scaffolder.

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
        """Ask whether to scaffold, then copy missing live files from examples."""
        if not self._config_dir.is_dir():
            logger.info(
                "Config directory missing at %s; skipping .config scaffold",
                self._rel(self._config_dir),
            )
            return

        if not self._prompt.confirm(
            f"Scaffold live config files under {self._rel(self._config_dir)} "
            "from *.example templates?",
            default=True,
        ):
            logger.info("Skipping .config scaffold")
            return

        self.scaffold()

    def scaffold(self) -> None:
        """Create missing live files from every ``*.example`` under config_dir.

        Existing live targets are left untouched and only logged.
        """
        examples = sorted(self._iter_examples())
        if not examples:
            logger.info(
                "No *.example templates found under %s",
                self._rel(self._config_dir),
            )
            return

        logger.info(
            "Scaffolding %d *.example template(s) under %s",
            len(examples),
            self._rel(self._config_dir),
        )
        created = 0
        skipped = 0
        for example_path in examples:
            target = self.live_path_for(example_path)
            if target.exists():
                logger.info("Config file already exists: %s", self._rel(target))
                skipped += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(example_path, target)
            logger.info(
                "Scaffolded config file %s from %s",
                self._rel(target),
                self._rel(example_path),
            )
            created += 1

        logger.info(
            "Config scaffold complete: created=%d skipped_existing=%d",
            created,
            skipped,
        )

    def _iter_examples(self) -> list[Path]:
        """Return all example template paths under the config directory.

        Returns:
            Sorted list of files whose names end with ``.example``.
        """
        return [
            path
            for path in self._config_dir.rglob(f"*{_EXAMPLE_SUFFIX}")
            if path.is_file() and path.name.endswith(_EXAMPLE_SUFFIX)
        ]

    @staticmethod
    def live_path_for(example_path: Path) -> Path:
        """Map an example template path to its live config path.

        Args:
            example_path: Path ending in ``.example``.

        Returns:
            Sibling path with the ``.example`` suffix removed.

        Raises:
            ValueError: If ``example_path`` does not end with ``.example``.
        """
        if not example_path.name.endswith(_EXAMPLE_SUFFIX):
            raise ValueError(f"Not an example template: {example_path}")
        live_name = example_path.name[: -len(_EXAMPLE_SUFFIX)]
        return example_path.with_name(live_name)


__all__ = ["ConfigScaffolder"]
