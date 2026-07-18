"""Tests for sanitized *.example generation."""

from __future__ import annotations

from pathlib import Path

from bootstrap.config_examples import ConfigExampleWriter


def test_is_b_scope_includes_ops_files_excludes_secrets(tmp_path: Path) -> None:
    """B-scope covers tfvars/yaml/env and skips ssh/secrets/backups."""
    config = tmp_path / ".config"
    writer = ConfigExampleWriter(config_dir=config)

    assert writer.is_b_scope(config / "terraform" / "app.tfvars") is True
    assert writer.is_b_scope(config / "docker" / "site.env") is True
    assert writer.is_b_scope(config / "swarm" / "grafana.ini") is True
    assert writer.is_b_scope(config / "swarm" / "prometheus.yaml") is True
    assert writer.is_b_scope(config / ".ssh" / "config") is False
    assert writer.is_b_scope(config / "agent.secret") is False
    assert writer.is_b_scope(config / "vault" / "init.json") is False
    assert writer.is_b_scope(config / "kubeconfig") is False
    assert writer.is_b_scope(config / "app.tfvars.bak.1") is False


def test_sanitize_env_and_tfvars_strip_secrets() -> None:
    """Sanitizers clear secret-bearing values while keeping structure."""
    writer = ConfigExampleWriter()
    env = writer.sanitize(
        Path("site.env"),
        "CONFIG_DIR=/secret/path\n# comment\nTOKEN=abc\n",
    )
    assert "CONFIG_DIR=\n" in env
    assert "TOKEN=\n" in env
    assert "# comment" in env

    tfvars = writer.sanitize(
        Path("app.tfvars"),
        'password = "super-secret"\nhost = "example.local"\ncount = 3\n',
    )
    assert 'password = ""' in tfvars
    assert 'host = ""' in tfvars
    assert "count = 3" in tfvars


def test_sanitize_yaml_redacts_unquoted_secrets() -> None:
    """YAML sanitizer clears unquoted user:pass and swarm tokens."""
    writer = ConfigExampleWriter()
    yaml_text = writer.sanitize(
        Path("user-config.yaml"),
        "chpasswd:\n  list: |\n    alice:hunter2\n"
        "token SWMTKN-1-abc-def\nowner: root:root\n",
    )
    assert "alice:changeme" in yaml_text
    assert "SWMTKN-changeme" in yaml_text
    assert "hunter2" not in yaml_text
    assert "owner: root:root" in yaml_text


def test_ensure_examples_writes_missing_only(tmp_path: Path) -> None:
    """ensure_examples creates sanitized siblings and skips existing examples."""
    config = tmp_path / ".config"
    docker = config / "docker"
    docker.mkdir(parents=True)
    live = docker / "site.env"
    live.write_text("CONFIG_DIR=/tmp/live\n", encoding="utf-8")
    existing_example = docker / "shared.env.example"
    existing_example.write_text("KEEP=\n", encoding="utf-8")
    (docker / "shared.env").write_text("KEEP=value\n", encoding="utf-8")

    writer = ConfigExampleWriter(config_dir=config)
    created, skipped = writer.ensure_examples()

    assert created == 1
    assert skipped == 1
    written = (docker / "site.env.example").read_text(encoding="utf-8")
    assert written == "CONFIG_DIR=\n"
    assert existing_example.read_text(encoding="utf-8") == "KEEP=\n"
