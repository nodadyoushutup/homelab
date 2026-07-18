"""Tests for .config scaffolding from *.example templates."""

from __future__ import annotations

from pathlib import Path

from bootstrap.config_scaffold import ConfigScaffolder
from bootstrap.prompt import OperatorPrompt


def test_live_path_for_strips_example_suffix() -> None:
    """Example paths map to live siblings without the suffix."""
    example = Path("/tmp/.config/docker/site.env.example")
    assert ConfigScaffolder.live_path_for(example) == Path("/tmp/.config/docker/site.env")


def test_scaffold_creates_missing_and_skips_existing(tmp_path: Path, caplog) -> None:
    """Missing live files are created; existing ones are left alone."""
    config_dir = tmp_path / ".config"
    docker = config_dir / "docker"
    docker.mkdir(parents=True)
    example = docker / "site.env.example"
    example.write_text("CONFIG_DIR=\n", encoding="utf-8")
    existing_example = docker / "shared.env.example"
    existing_example.write_text("KEY=\n", encoding="utf-8")
    existing_live = docker / "shared.env"
    existing_live.write_text("KEY=keep-me\n", encoding="utf-8")

    scaffolder = ConfigScaffolder(
        config_dir=config_dir,
        prompt=OperatorPrompt(input_func=lambda _: "y"),
    )
    with caplog.at_level("INFO"):
        scaffolder.scaffold()

    assert (docker / "site.env").read_text(encoding="utf-8") == "CONFIG_DIR=\n"
    assert existing_live.read_text(encoding="utf-8") == "KEY=keep-me\n"
    assert "Scaffolded config file" in caplog.text
    assert "already exists" in caplog.text


def test_run_defaults_yes_on_empty_answer(tmp_path: Path) -> None:
    """Empty operator answer accepts the scaffold prompt."""
    config_dir = tmp_path / ".config"
    config_dir.mkdir()
    example = config_dir / "minio.backend.hcl.example"
    example.write_text('bucket = ""\n', encoding="utf-8")

    scaffolder = ConfigScaffolder(
        config_dir=config_dir,
        prompt=OperatorPrompt(input_func=lambda _: ""),
    )
    scaffolder.run()
    assert (config_dir / "minio.backend.hcl").is_file()


def test_run_skips_when_declined(tmp_path: Path, caplog) -> None:
    """Declining the prompt does not create live files."""
    config_dir = tmp_path / ".config"
    config_dir.mkdir()
    example = config_dir / "site.env.example"
    example.write_text("X=\n", encoding="utf-8")

    scaffolder = ConfigScaffolder(
        config_dir=config_dir,
        prompt=OperatorPrompt(input_func=lambda _: "n"),
    )
    with caplog.at_level("INFO"):
        scaffolder.run()

    assert not (config_dir / "site.env").exists()
    assert "Skipping .config scaffold" in caplog.text
