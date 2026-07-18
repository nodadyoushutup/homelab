"""Tests for the required live-config acknowledgment gate."""

from __future__ import annotations

from pathlib import Path

from bootstrap.config_ack import ConfigAcknowledger
from bootstrap.prompt import OperatorPrompt


def test_run_blocks_until_acknowledged(tmp_path: Path, caplog) -> None:
    """run re-asks until the operator confirms live config is set up."""
    config_dir = tmp_path / ".config"
    config_dir.mkdir()
    answers = iter(["n", "", "y"])

    acknowledger = ConfigAcknowledger(
        config_dir=config_dir,
        prompt=OperatorPrompt(input_func=lambda _: next(answers)),
    )
    with caplog.at_level("INFO"):
        acknowledger.run()

    assert "Update your live config files" in caplog.text
    assert "This step is required" in caplog.text
    assert "Configuration acknowledged" in caplog.text


def test_run_acknowledges_on_first_yes(tmp_path: Path, caplog) -> None:
    """A single affirmative answer satisfies the gate."""
    config_dir = tmp_path / ".config"
    config_dir.mkdir()
    calls: list[str] = []

    def fake_input(_: str) -> str:
        calls.append("read")
        return "yes"

    acknowledger = ConfigAcknowledger(
        config_dir=config_dir,
        prompt=OperatorPrompt(input_func=fake_input),
    )
    with caplog.at_level("INFO"):
        acknowledger.run()

    assert calls == ["read"]
    assert "Configuration acknowledged" in caplog.text
