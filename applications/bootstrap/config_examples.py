"""Create sanitized ``*.example`` templates for B-scope site config files."""

from __future__ import annotations

import logging
import re
from pathlib import Path

from bootstrap.paths import CONFIG_DIR, display_path

logger = logging.getLogger(__name__)

_EXAMPLE_SUFFIX = ".example"
_B_SCOPE_SUFFIXES = {".tfvars", ".env", ".hcl", ".yaml", ".yml", ".ini", ".json"}
_EXCLUDED_NAMES = {
    "init.json",
    "kubeconfig",
    "talosconfig",
    "htpasswd",
    "known_hosts",
    "known_hosts.old",
    "README.md",
}
_EXCLUDED_DIR_NAMES = {".ssh"}
_EXCLUDED_NAME_SUBSTRINGS = (".bak",)

# Empty quoted strings in HCL/tfvars-like files (keeps keys/structure).
_QUOTED_STRING = re.compile(r'"[^"\\]*(?:\\.[^"\\]*)*"|\'[^\'\\]*(?:\\.[^\'\\]*)*\'')
_SWARM_TOKEN = re.compile(r"SWMTKN-[A-Za-z0-9-]+")
_USER_PASS_LINE = re.compile(r"^(\s*)([A-Za-z0-9_.-]+):(\S+)\s*$", re.MULTILINE)


class ConfigExampleWriter:
    """Write sanitized ``*.example`` siblings for operator-facing config files."""

    def __init__(self, config_dir: Path = CONFIG_DIR) -> None:
        """Initialize the writer.

        Args:
            config_dir: Root of the site config tree.
        """
        self._config_dir = config_dir

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the repo root that owns config_dir.

        Args:
            path: Path to render.

        Returns:
            Repo-relative display string.
        """
        return display_path(path, root=self._config_dir.parent)

    def ensure_examples(self, *, overwrite: bool = False) -> tuple[int, int]:
        """Create ``*.example`` files for every B-scope live config.

        Args:
            overwrite: When ``True``, rewrite existing example files.

        Returns:
            Tuple of ``(written, skipped_existing)`` counts.
        """
        written = 0
        skipped = 0
        for live_path in self.iter_b_scope_files():
            example_path = live_path.with_name(live_path.name + _EXAMPLE_SUFFIX)
            if example_path.exists() and not overwrite:
                logger.info("Example already exists: %s", self._rel(example_path))
                skipped += 1
                continue
            content = live_path.read_text(encoding="utf-8")
            sanitized = self.sanitize(live_path, content)
            example_path.write_text(sanitized, encoding="utf-8")
            logger.info("Wrote sanitized example %s", self._rel(example_path))
            written += 1
        logger.info(
            "Example sync complete: written=%d skipped_existing=%d",
            written,
            skipped,
        )
        return written, skipped

    def iter_b_scope_files(self) -> list[Path]:
        """Return live config files that should have ``*.example`` templates.

        Returns:
            Sorted list of B-scope live config paths.
        """
        matches: list[Path] = []
        for path in sorted(self._config_dir.rglob("*")):
            if not path.is_file():
                continue
            if path.name.endswith(_EXAMPLE_SUFFIX):
                continue
            if not self.is_b_scope(path):
                continue
            matches.append(path)
        return matches

    def is_b_scope(self, path: Path) -> bool:
        """Return whether a path is in the B-scope example set.

        Args:
            path: Candidate live config path.

        Returns:
            ``True`` when the file should receive a sanitized ``*.example``.
        """
        try:
            relative = path.relative_to(self._config_dir)
        except ValueError:
            return False
        if any(part in _EXCLUDED_DIR_NAMES for part in relative.parts):
            return False
        if path.name in _EXCLUDED_NAMES:
            return False
        if path.suffix == ".secret":
            return False
        if any(token in path.name for token in _EXCLUDED_NAME_SUBSTRINGS):
            return False
        if path.suffix not in _B_SCOPE_SUFFIXES:
            return False
        return True

    def sanitize(self, path: Path, content: str) -> str:
        """Return sanitized example content for a live config file.

        Args:
            path: Live config path (used to choose sanitizer).
            content: Raw live file text.

        Returns:
            Placeholder-safe example text with secrets removed.
        """
        suffix = path.suffix.lower()
        if suffix == ".env" or path.name.endswith(".env"):
            return self._sanitize_env(content)
        if suffix in {".tfvars", ".hcl"}:
            return self._sanitize_hcl_like(content)
        if suffix == ".ini":
            return self._sanitize_ini(content)
        if suffix in {".yaml", ".yml"}:
            return self._sanitize_quoted_strings(content)
        if suffix == ".json":
            return self._sanitize_quoted_strings(content)
        return self._sanitize_quoted_strings(content)

    def _sanitize_env(self, content: str) -> str:
        """Sanitize dotenv content by clearing values.

        Args:
            content: Live dotenv text.

        Returns:
            Example dotenv with empty values.
        """
        lines: list[str] = []
        for line in content.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                lines.append(line)
                continue
            if "=" not in line:
                lines.append(line)
                continue
            key, _value = line.split("=", 1)
            lines.append(f"{key}=")
        return "\n".join(lines) + ("\n" if content.endswith("\n") else "")

    def _sanitize_ini(self, content: str) -> str:
        """Sanitize INI content by clearing values.

        Args:
            content: Live INI text.

        Returns:
            Example INI with empty values (sections preserved).
        """
        lines: list[str] = []
        for line in content.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or stripped.startswith(";"):
                lines.append(line)
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                lines.append(line)
                continue
            if "=" not in line:
                lines.append(line)
                continue
            key, _value = line.split("=", 1)
            lines.append(f"{key}=")
        return "\n".join(lines) + ("\n" if content.endswith("\n") else "")

    def _sanitize_hcl_like(self, content: str) -> str:
        """Sanitize tfvars/HCL by emptying quoted string literals.

        Args:
            content: Live HCL/tfvars text.

        Returns:
            Example text with string values cleared.
        """
        return self._sanitize_quoted_strings(content)

    def _sanitize_quoted_strings(self, content: str) -> str:
        """Replace quoted literals and common unquoted secret shapes.

        Args:
            content: Arbitrary text that may contain secrets in quotes.

        Returns:
            Text with secrets replaced by placeholders.
        """

        def _replace(match: re.Match[str]) -> str:
            token = match.group(0)
            return '""' if token.startswith('"') else "''"

        cleaned = _QUOTED_STRING.sub(_replace, content)
        cleaned = _SWARM_TOKEN.sub("SWMTKN-changeme", cleaned)
        cleaned = _USER_PASS_LINE.sub(r"\1\2:changeme", cleaned)
        return cleaned


def main() -> int:
    """CLI entry to sync sanitized example templates.

    Returns:
        Process exit code.
    """
    import argparse

    parser = argparse.ArgumentParser(description="Sync sanitized .config *.example files")
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Rewrite existing *.example files from sanitized live configs",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    ConfigExampleWriter().ensure_examples(overwrite=args.overwrite)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
