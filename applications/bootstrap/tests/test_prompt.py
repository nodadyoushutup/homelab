"""Tests for operator prompts."""

from __future__ import annotations

from bootstrap.prompt import OperatorPrompt


def test_confirm_logs_warning_and_accepts_yes(caplog) -> None:
    """Confirmation prompts log at WARNING and accept yes."""
    prompt = OperatorPrompt(input_func=lambda _: "yes")

    with caplog.at_level("WARNING"):
        assert prompt.confirm("Proceed with install?") is True

    assert "Proceed with install?" in caplog.text
    assert "[y/N]" in caplog.text
    assert any(record.levelname == "WARNING" for record in caplog.records)


def test_confirm_declines_default_no(caplog) -> None:
    """Empty answer declines when default is no."""
    prompt = OperatorPrompt(input_func=lambda _: "")

    with caplog.at_level("INFO"):
        assert prompt.confirm("Create .venv?") is False

    assert "Operator declined" in caplog.text


def test_confirm_accepts_default_yes(caplog) -> None:
    """Empty answer accepts when default is yes."""
    prompt = OperatorPrompt(input_func=lambda _: "")

    with caplog.at_level("INFO"):
        assert prompt.confirm("Scaffold .config?", default=True) is True

    assert "[Y/n]" in caplog.text
    assert "Operator confirmed" in caplog.text


def test_require_yes_repeats_until_affirmative(caplog) -> None:
    """require_yes re-asks on non-affirmative answers until 'y'."""
    answers = iter(["n", "", "y"])
    calls: list[str] = []

    def fake_input(_: str) -> str:
        value = next(answers)
        calls.append(value)
        return value

    prompt = OperatorPrompt(input_func=fake_input)
    with caplog.at_level("WARNING"):
        assert prompt.require_yes("Config ready?") is None

    assert calls == ["n", "", "y"]
    assert "This step is required" in caplog.text


def test_require_yes_returns_immediately_on_yes() -> None:
    """require_yes reads exactly once when answered affirmatively."""
    calls: list[str] = []

    def fake_input(_: str) -> str:
        calls.append("read")
        return "y"

    prompt = OperatorPrompt(input_func=fake_input)
    prompt.require_yes("Config ready?")
    assert calls == ["read"]


def test_require_yes_default_true_accepts_empty() -> None:
    """With default=True, pressing enter (empty) counts as confirmation."""
    calls: list[str] = []

    def fake_input(_: str) -> str:
        calls.append("read")
        return ""

    prompt = OperatorPrompt(input_func=fake_input)
    prompt.require_yes("Config ready?", default=True)
    assert calls == ["read"]


def test_ask_returns_trimmed_answer(caplog) -> None:
    """ask returns the operator's trimmed free-text answer."""
    prompt = OperatorPrompt(input_func=lambda _: "  user@host  ")

    with caplog.at_level("WARNING"):
        assert prompt.ask("SSH target?") == "user@host"

    assert "SSH target?" in caplog.text


def test_ask_uses_default_on_empty() -> None:
    """ask returns the default when the answer is blank."""
    prompt = OperatorPrompt(input_func=lambda _: "")
    assert prompt.ask("Username?", default="admin") == "admin"


def test_ask_secret_reads_without_logging_value(caplog) -> None:
    """ask_secret reads via the secret func and never logs the value."""
    prompt = OperatorPrompt(
        input_func=lambda _: "unused",
        secret_func=lambda _: "s3cr3t",
    )

    with caplog.at_level("INFO"):
        assert prompt.ask_secret("Password?") == "s3cr3t"

    assert "Password?" in caplog.text
    assert "s3cr3t" not in caplog.text
