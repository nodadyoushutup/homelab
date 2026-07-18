"""Native OS package-manager helpers for bootstrap prerequisites."""

from __future__ import annotations

import logging
import shutil
import subprocess
from dataclasses import dataclass
from enum import Enum

logger = logging.getLogger(__name__)


class PackageManagerKind(Enum):
    """Supported native package managers."""

    APT = "apt-get"
    DNF = "dnf"
    YUM = "yum"
    PACMAN = "pacman"
    ZYPPER = "zypper"
    BREW = "brew"


@dataclass(frozen=True)
class PackageInstallPlan:
    """Command plan to install Python venv support.

    Attributes:
        kind: Detected package manager.
        package: Package name that provides ``python3 -m venv``.
        command: Full argv to install the package.
    """

    kind: PackageManagerKind
    package: str
    command: tuple[str, ...]


class UnsupportedPackageManagerError(RuntimeError):
    """Raised when no supported package manager is available."""


class PackageManager:
    """Detect the host package manager and install Python venv support."""

    _DETECT_ORDER: tuple[PackageManagerKind, ...] = (
        PackageManagerKind.APT,
        PackageManagerKind.DNF,
        PackageManagerKind.YUM,
        PackageManagerKind.PACMAN,
        PackageManagerKind.ZYPPER,
        PackageManagerKind.BREW,
    )

    def detect(self) -> PackageInstallPlan:
        """Detect a usable package manager and return an install plan.

        Returns:
            Plan describing how to install Python venv support.

        Raises:
            UnsupportedPackageManagerError: If no known package manager is found.
        """
        for kind in self._DETECT_ORDER:
            if shutil.which(kind.value) is None:
                continue
            plan = self._plan_for(kind)
            logger.info(
                "Detected package manager %s; will install %s if needed",
                kind.value,
                plan.package,
            )
            return plan
        raise UnsupportedPackageManagerError(
            "No supported package manager found "
            "(looked for apt-get, dnf, yum, pacman, zypper, brew)"
        )

    def install_python_venv(self, plan: PackageInstallPlan | None = None) -> None:
        """Install the OS package that provides ``python3 -m venv``.

        Args:
            plan: Optional precomputed plan; detected automatically when omitted.

        Raises:
            UnsupportedPackageManagerError: If no supported package manager exists.
            subprocess.CalledProcessError: If the install command fails.
        """
        resolved = plan or self.detect()
        logger.info(
            "Installing %s with %s: %s",
            resolved.package,
            resolved.kind.value,
            " ".join(resolved.command),
        )
        subprocess.run(list(resolved.command), check=True)
        logger.info("Installed %s via %s", resolved.package, resolved.kind.value)

    def _plan_for(self, kind: PackageManagerKind) -> PackageInstallPlan:
        """Build an install plan for a package manager.

        Args:
            kind: Detected package manager kind.

        Returns:
            Install plan for that manager.
        """
        if kind is PackageManagerKind.APT:
            return PackageInstallPlan(
                kind=kind,
                package="python3-venv",
                command=("sudo", "apt-get", "install", "-y", "python3-venv"),
            )
        if kind is PackageManagerKind.DNF:
            return PackageInstallPlan(
                kind=kind,
                package="python3-venv",
                command=("sudo", "dnf", "install", "-y", "python3-venv"),
            )
        if kind is PackageManagerKind.YUM:
            return PackageInstallPlan(
                kind=kind,
                package="python3-venv",
                command=("sudo", "yum", "install", "-y", "python3-venv"),
            )
        if kind is PackageManagerKind.PACMAN:
            return PackageInstallPlan(
                kind=kind,
                package="python",
                command=("sudo", "pacman", "-S", "--noconfirm", "python"),
            )
        if kind is PackageManagerKind.ZYPPER:
            return PackageInstallPlan(
                kind=kind,
                package="python3-venv",
                command=("sudo", "zypper", "install", "-y", "python3-venv"),
            )
        return PackageInstallPlan(
            kind=kind,
            package="python3",
            command=("brew", "install", "python3"),
        )
