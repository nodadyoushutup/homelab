"""Operator prompts that surface as warning-level log messages."""

from __future__ import annotations

import getpass
import logging
from collections.abc import Callable

logger = logging.getLogger(__name__)


class OperatorPrompt:
    """Ask the operator for confirmation via stdin.

    Prompt text is always emitted at WARNING so interactive questions stand out
    from routine INFO progress logs.
    """

    def __init__(
        self,
        input_func: Callable[[str], str] = input,
        secret_func: Callable[[str], str] = getpass.getpass,
    ) -> None:
        """Initialize the prompter.

        Args:
            input_func: Callable used to read a line from the operator.
            secret_func: Callable used to read a secret without echoing it.
        """
        self._input = input_func
        self._secret = secret_func

    def confirm(self, question: str, *, default: bool = False) -> bool:
        """Ask a yes/no question and return whether the answer was affirmative.

        Args:
            question: Question text shown to the operator (without the ``[y/N]`` hint).
            default: Value used when the operator submits an empty answer.

        Returns:
            ``True`` when the operator accepts (or accepts by default).
        """
        hint = "[Y/n]" if default else "[y/N]"
        logger.warning("%s %s", question, hint)
        answer = self._input("> ").strip().lower()
        if not answer:
            accepted = default
        else:
            accepted = answer in {"y", "yes"}
        if accepted:
            logger.info("Operator confirmed: %s", question)
        else:
            logger.info("Operator declined: %s", question)
        return accepted

    def require_yes(self, question: str, *, default: bool = False) -> None:
        """Block until the operator affirmatively answers a required question.

        The question is re-asked on any non-affirmative answer, so bootstrap
        cannot proceed until the operator confirms. When ``default`` is ``True``
        an empty answer (pressing enter) counts as confirmation.

        Args:
            question: Question text shown to the operator (without the hint).
            default: Value used when the operator submits an empty answer.
        """
        while not self.confirm(question, default=default):
            logger.warning("This step is required; please answer 'y' to continue.")

    def ask(self, question: str, *, default: str = "") -> str:
        """Ask a free-text question and return the operator's answer.

        Args:
            question: Question text shown to the operator.
            default: Value returned when the operator submits an empty answer.

        Returns:
            The trimmed operator answer, or ``default`` when left blank.
        """
        hint = f" [{default}]" if default else ""
        logger.warning("%s%s", question, hint)
        answer = self._input("> ").strip()
        if not answer:
            answer = default
        # Log that input was captured without echoing arbitrary free-text values.
        logger.info("Captured operator input for: %s", question)
        return answer

    def ask_secret(self, question: str) -> str:
        """Ask for a secret value without echoing it to the terminal or logs.

        Args:
            question: Question text shown to the operator.

        Returns:
            The secret entered by the operator (never logged).
        """
        logger.warning("%s", question)
        secret = self._secret("> ")
        logger.info("Captured secret input for: %s", question)
        return secret
