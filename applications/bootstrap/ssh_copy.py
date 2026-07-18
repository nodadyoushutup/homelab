"""Copy the host ``~/.ssh`` tree into ``.config/.ssh`` for site operations."""

from __future__ import annotations

import logging
import shutil
import stat
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt

logger = logging.getLogger(__name__)

_SKIP_DIR_NAMES = frozenset({"agent"})


class SshCopyError(RuntimeError):
    """Raised when the host SSH directory cannot be copied into ``.config``."""


class SshConfigCopier:
    """Copy host SSH materials into the site ``.config/.ssh`` tree."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        config_dir: Path | None = None,
        source_dir: Path | None = None,
        prompt: OperatorPrompt | None = None,
    ) -> None:
        """Initialize the copier.

        Args:
            project_root: Repository root (for relative log paths).
            config_dir: Site config root; defaults to ``<repo>/.config``.
            source_dir: Host SSH directory; defaults to ``~/.ssh``.
            prompt: Operator confirmation collaborator.
        """
        self._project_root = project_root
        self._config_dir = (
            config_dir if config_dir is not None else project_root / ".config"
        )
        self._dest_dir = self._config_dir / ".ssh"
        self._source_dir = (
            source_dir if source_dir is not None else Path.home() / ".ssh"
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

    def exists(self) -> bool:
        """Return whether the site SSH directory is already present.

        Returns:
            ``True`` when ``.config/.ssh`` exists as a directory.
        """
        present = self._dest_dir.is_dir()
        if present:
            logger.info(
                "Site SSH directory already exists: %s",
                self._rel(self._dest_dir),
            )
        else:
            logger.info(
                "Site SSH directory does not exist: %s",
                self._rel(self._dest_dir),
            )
        return present

    def run(self) -> None:
        """Warn, confirm, and copy host ``~/.ssh`` into ``.config/.ssh``.

        If ``.config/.ssh`` already exists, acknowledge it and do not overwrite.
        """
        if self.exists():
            return

        logger.warning(
            "Bootstrap can copy your host machine SSH directory into %s. "
            "This becomes a separate site copy used by Terraform, Swarm, and "
            "CI/CD — it is not your live host ~/.ssh. Keeping an up-to-date "
            "copy here is highly recommended.",
            self._rel(self._dest_dir),
        )

        if not self._prompt.confirm(
            f"Copy host ~/.ssh into {self._rel(self._dest_dir)} "
            "(separate site copy for Terraform/Swarm/CI/CD; highly recommended)?",
            default=True,
        ):
            logger.info("Skipping host ~/.ssh copy into %s", self._rel(self._dest_dir))
            return

        self.copy()

    def copy(self) -> None:
        """Copy regular files from the host SSH directory into ``.config/.ssh``.

        Raises:
            SshCopyError: If the host SSH directory is missing or unreadable.
        """
        if self._dest_dir.is_dir():
            logger.info(
                "Site SSH directory already exists: %s",
                self._rel(self._dest_dir),
            )
            return

        if not self._source_dir.is_dir():
            raise SshCopyError(
                f"Host SSH directory missing: {self._source_dir} "
                f"(expected ~/.ssh on this machine)"
            )

        self._dest_dir.mkdir(parents=True, exist_ok=False)
        self._dest_dir.chmod(0o700)
        logger.info(
            "Copying host ~/.ssh -> %s (site copy; host ~/.ssh unchanged)",
            self._rel(self._dest_dir),
        )

        copied = 0
        skipped = 0
        for source_path in sorted(self._source_dir.rglob("*")):
            relative = source_path.relative_to(self._source_dir)
            if any(part in _SKIP_DIR_NAMES for part in relative.parts):
                logger.info("Skipping SSH runtime path: %s", relative.as_posix())
                skipped += 1
                continue
            if not source_path.is_file() or source_path.is_symlink():
                skipped += 1
                continue

            dest_path = self._dest_dir / relative
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, dest_path)
            self._apply_safe_mode(source_path, dest_path)
            logger.info("Copied SSH file %s", self._rel(dest_path))
            copied += 1

        logger.info(
            "SSH copy complete: copied=%d skipped=%d dest=%s",
            copied,
            skipped,
            self._rel(self._dest_dir),
        )

    def _apply_safe_mode(self, source_path: Path, dest_path: Path) -> None:
        """Apply conservative permissions on copied SSH materials.

        Args:
            source_path: Original host file (used to detect private keys).
            dest_path: Destination file under ``.config/.ssh``.
        """
        mode = source_path.stat().st_mode
        # Private keys and config should stay owner-readable only.
        if source_path.name in {"config", "known_hosts", "known_hosts.old"} or (
            not source_path.name.endswith(".pub")
            and "id_" in source_path.name
        ):
            dest_path.chmod(0o600)
            return
        if mode & (stat.S_IRWXG | stat.S_IRWXO):
            dest_path.chmod(stat.S_IMODE(mode) & 0o755)
            return
        dest_path.chmod(stat.S_IMODE(mode))


__all__ = ["SshConfigCopier", "SshCopyError"]
