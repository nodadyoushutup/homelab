"""Install host packages and tooling via ``scripts/install`` helpers."""

from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt

logger = logging.getLogger(__name__)

INSTALL_DIR = PROJECT_ROOT / "scripts" / "install"
AUTOMATION_TOOLING_SCRIPT = INSTALL_DIR / "automation_tooling.sh"


class HostToolingError(RuntimeError):
    """Raised when host tooling installation fails."""


class HostToolingInstaller:
    """Run the shared automation tooling install bundle on the host."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        script_path: Path | None = None,
        prompt: OperatorPrompt | None = None,
    ) -> None:
        """Initialize the installer.

        Args:
            project_root: Repository root (used for relative log paths).
            script_path: Bundle script to execute; defaults to automation_tooling.sh.
            prompt: Operator confirmation collaborator.
        """
        self._project_root = project_root
        self._script_path = (
            script_path
            if script_path is not None
            else project_root / "scripts" / "install" / "automation_tooling.sh"
        )
        self._prompt = prompt or OperatorPrompt()

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display.

        Args:
            path: Path to render.

        Returns:
            Repo-relative display string.
        """
        return display_path(path, root=self._project_root)

    def run(self) -> None:
        """Ask whether to install host tooling, then run the install bundle."""
        if not self._prompt.confirm(
            "Install host packages and dependencies "
            f"(via {self._rel(self._script_path)})?",
            default=True,
        ):
            logger.info("Skipping host tooling install")
            return

        self.install()

    def install(self) -> None:
        """Execute the automation tooling install script.

        Raises:
            HostToolingError: If the script is missing or exits non-zero.
        """
        if not self._script_path.is_file():
            raise HostToolingError(
                f"Install script missing: {self._rel(self._script_path)}"
            )

        self._ensure_executable()
        logger.info("Running host tooling install: %s", self._rel(self._script_path))
        try:
            subprocess.run(
                [str(self._script_path)],
                check=True,
                cwd=str(self._project_root),
            )
        except subprocess.CalledProcessError as exc:
            raise HostToolingError(
                f"Host tooling install failed "
                f"({self._rel(self._script_path)} exit {exc.returncode})"
            ) from exc

        logger.info("Host tooling install complete")

    def _ensure_executable(self) -> None:
        """Ensure the install script has an executable bit set."""
        mode = self._script_path.stat().st_mode
        if mode & 0o111:
            logger.info(
                "Install script already executable: %s",
                self._rel(self._script_path),
            )
            return
        os.chmod(self._script_path, mode | 0o111)
        logger.info(
            "Marked install script executable: %s",
            self._rel(self._script_path),
        )


__all__ = ["HostToolingError", "HostToolingInstaller"]
