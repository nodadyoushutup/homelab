"""Tests for bootstrap logging setup."""

from __future__ import annotations

import builtins
import logging
import sys

from bootstrap import logging_setup


def test_logging_setup_module_does_not_import_coloredlogs_at_load() -> None:
    """coloredlogs must not be bound on the logging_setup module at import time."""
    assert not hasattr(logging_setup, "coloredlogs")


def test_configure_logging_uses_stdlib(capsys) -> None:
    """Early configure_logging attaches a stdlib handler without coloredlogs."""
    root = logging.getLogger()
    root.handlers.clear()

    logging_setup.configure_logging()
    captured = capsys.readouterr()

    assert root.handlers
    assert "Configured stdlib logging" in captured.err


def test_configure_colored_logging_falls_back_without_dependency(
    monkeypatch, capsys
) -> None:
    """Missing coloredlogs falls back to stdlib logging."""
    monkeypatch.delitem(sys.modules, "coloredlogs", raising=False)
    real_import = builtins.__import__

    def fake_import(name: str, *args: object, **kwargs: object) -> object:
        if name == "coloredlogs":
            raise ImportError("forced missing coloredlogs")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", fake_import)
    root = logging.getLogger()
    root.handlers.clear()

    logging_setup.configure_colored_logging()
    captured = capsys.readouterr()

    assert "coloredlogs is not installed yet" in captured.err


def test_configure_colored_logging_imports_lazily(monkeypatch, capsys) -> None:
    """coloredlogs is imported only inside configure_colored_logging."""
    calls: list[str] = []

    class FakeColoredLogs:
        """Stub coloredlogs module."""

        @staticmethod
        def install(*, level: str, logger: logging.Logger) -> None:
            """Record install calls."""
            calls.append(level)

    monkeypatch.setitem(sys.modules, "coloredlogs", FakeColoredLogs)
    root = logging.getLogger()
    root.handlers.clear()
    handler = logging.StreamHandler(sys.stderr)
    root.addHandler(handler)

    logging_setup.configure_colored_logging(level="DEBUG")
    captured = capsys.readouterr()

    assert calls == ["DEBUG"]
    assert "Configured coloredlogs" in captured.err
