"""Ensure and activate a project-root Python virtual environment."""

from __future__ import annotations

import logging
import os
import subprocess
import sys
from pathlib import Path

from bootstrap.package_manager import PackageManager
from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt

logger = logging.getLogger(__name__)


class VenvEnsureError(RuntimeError):
    """Raised when the project virtualenv cannot be ensured or activated."""


class ProjectVenv:
    """Create, verify, and activate ``<project>/.venv``."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        venv_dir: Path | None = None,
        package_manager: PackageManager | None = None,
        prompt: OperatorPrompt | None = None,
        python_bin: str = "python3",
    ) -> None:
        """Initialize the venv manager.

        Args:
            project_root: Repository root that should contain ``.venv``.
            venv_dir: Explicit venv path; defaults to ``<project_root>/.venv``.
            package_manager: OS package manager collaborator.
            prompt: Operator confirmation collaborator.
            python_bin: Interpreter used to create the virtualenv.
        """
        self._project_root = project_root
        self._venv_dir = venv_dir if venv_dir is not None else project_root / ".venv"
        self._package_manager = package_manager or PackageManager()
        self._prompt = prompt or OperatorPrompt()
        self._python_bin = python_bin

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display.

        Args:
            path: Path to render.

        Returns:
            Repo-relative display string.
        """
        return display_path(path, root=self._project_root)

    @property
    def venv_dir(self) -> Path:
        """Return the project virtualenv path."""
        return self._venv_dir

    @property
    def python_path(self) -> Path:
        """Return the virtualenv ``python3`` interpreter path."""
        return self._venv_dir / "bin" / "python3"

    @property
    def bin_dir(self) -> Path:
        """Return the virtualenv ``bin`` directory."""
        return self._venv_dir / "bin"

    def exists(self) -> bool:
        """Return whether a usable project virtualenv is present.

        Returns:
            ``True`` when ``.venv`` exists and looks like a virtualenv.
        """
        present = self._is_venv_present()
        if present:
            logger.info("Project virtualenv exists at %s", self._rel(self._venv_dir))
        else:
            logger.info(
                "Project virtualenv does not exist at %s",
                self._rel(self._venv_dir),
            )
        return present

    def is_active(self) -> bool:
        """Return whether this process is already running inside the project venv.

        Returns:
            ``True`` when ``sys.prefix`` is the project virtualenv directory.

        Notes:
            Comparing resolved ``sys.executable`` is unreliable: venv ``python3``
            is often a symlink to the system interpreter, so both resolve equally.
        """
        try:
            prefix = Path(sys.prefix).resolve()
            expected = self._venv_dir.resolve()
        except OSError:
            return False
        active = prefix == expected
        logger.info(
            "Project virtualenv active check: %s (sys.prefix=%s)",
            "active" if active else "inactive",
            self._rel(prefix),
        )
        return active

    def ensure(self) -> Path:
        """Ensure the project virtualenv exists, creating it when missing.

        Returns:
            Path to the project virtualenv directory.

        Raises:
            VenvEnsureError: If the operator declines or creation fails.
        """
        if self.exists():
            return self._venv_dir

        if not self._prompt.confirm(
            f"Create project virtualenv at {self._rel(self._venv_dir)} "
            "(install OS python3-venv support first if needed)?"
        ):
            raise VenvEnsureError(
                "Operator declined creating virtualenv at "
                f"{self._rel(self._venv_dir)}"
            )

        if not self._venv_module_available():
            logger.info(
                "python3 venv module is unavailable; installing via OS package manager"
            )
            self._package_manager.install_python_venv()
            if not self._venv_module_available():
                raise VenvEnsureError(
                    "python3 -m venv is still unavailable after package install"
                )
            logger.info("python3 venv module is available after package install")
        else:
            logger.info("python3 venv module is already available")

        self._create()
        if not self._is_venv_present():
            raise VenvEnsureError(
                f"Failed to create virtualenv at {self._rel(self._venv_dir)}"
            )
        logger.info("Created project virtualenv at %s", self._rel(self._venv_dir))
        return self._venv_dir

    def activate(self) -> None:
        """Activate the project virtualenv for this process.

        Sets ``VIRTUAL_ENV`` and prepends the venv ``bin`` directory to ``PATH``,
        matching a normal shell ``activate``. If this interpreter is not already
        the venv's ``python3``, re-executes the current process under it.

        Raises:
            VenvEnsureError: If the venv or its interpreter is missing.
        """
        if not self._is_venv_present():
            raise VenvEnsureError(
                "Cannot activate; project virtualenv missing at "
                f"{self._rel(self._venv_dir)}"
            )
        if not self.python_path.is_file():
            raise VenvEnsureError(
                "Cannot activate; missing interpreter at "
                f"{self._rel(self.python_path)}"
            )

        self._apply_environ()

        if self.is_active():
            logger.info(
                "Project virtualenv already active at %s",
                self._rel(self._venv_dir),
            )
            return

        logger.info(
            "Activating project virtualenv; re-executing under %s",
            self._rel(self.python_path),
        )
        argv = [str(self.python_path), *sys.argv]
        os.execv(str(self.python_path), argv)

    def install_requirements(self, requirements: Path | None = None) -> None:
        """Install bootstrap Python dependencies into the project virtualenv.

        Runs after activation (so this executes under the venv interpreter) and is
        idempotent: pip skips already-satisfied requirements quickly.

        Args:
            requirements: Requirements file; defaults to the bootstrap app's
                ``requirements.txt`` next to this module.

        Raises:
            VenvEnsureError: If the requirements install fails.
        """
        req_path = (
            requirements
            if requirements is not None
            else Path(__file__).resolve().parent / "requirements.txt"
        )
        if not req_path.is_file():
            logger.info(
                "No requirements file at %s; skipping dependency install",
                self._rel(req_path),
            )
            return

        logger.info(
            "Installing bootstrap dependencies from %s", self._rel(req_path)
        )
        try:
            subprocess.run(
                [
                    str(self.python_path),
                    "-m",
                    "pip",
                    "install",
                    "-q",
                    "-r",
                    str(req_path),
                ],
                check=True,
            )
        except subprocess.CalledProcessError as exc:
            raise VenvEnsureError(
                f"Failed to install bootstrap dependencies from "
                f"{self._rel(req_path)} (exit {exc.returncode})"
            ) from exc
        logger.info("Bootstrap dependencies installed")

    def _is_venv_present(self) -> bool:
        """Return whether the venv directory looks usable.

        Returns:
            ``True`` when the directory and ``pyvenv.cfg`` exist.
        """
        marker = self._venv_dir / "pyvenv.cfg"
        return self._venv_dir.is_dir() and marker.is_file()

    def _apply_environ(self) -> None:
        """Apply shell-style virtualenv environment variables to this process."""
        bin_dir = str(self.bin_dir)
        current_path = os.environ.get("PATH", "")
        path_parts = [part for part in current_path.split(os.pathsep) if part]
        if bin_dir in path_parts:
            path_parts.remove(bin_dir)
        os.environ["PATH"] = os.pathsep.join([bin_dir, *path_parts])
        os.environ["VIRTUAL_ENV"] = str(self._venv_dir)
        os.environ.pop("PYTHONHOME", None)
        logger.info(
            "Applied virtualenv environment: VIRTUAL_ENV=%s PATH prefix=%s",
            self._rel(self._venv_dir),
            self._rel(self.bin_dir),
        )

    def _venv_module_available(self) -> bool:
        """Return whether ``python3 -m venv`` can run on this host.

        Returns:
            ``True`` when the venv module help command succeeds.
        """
        result = subprocess.run(
            [self._python_bin, "-m", "venv", "--help"],
            capture_output=True,
            check=False,
            text=True,
        )
        available = result.returncode == 0
        logger.info(
            "Checked %s -m venv availability: %s",
            self._python_bin,
            "available" if available else "unavailable",
        )
        return available

    def _create(self) -> None:
        """Create the project virtualenv directory.

        Raises:
            subprocess.CalledProcessError: If ``python3 -m venv`` fails.
        """
        logger.info(
            "Creating virtualenv with %s -m venv %s",
            self._python_bin,
            self._rel(self._venv_dir),
        )
        subprocess.run(
            [self._python_bin, "-m", "venv", str(self._venv_dir)],
            check=True,
        )


__all__ = ["ProjectVenv", "VenvEnsureError"]
