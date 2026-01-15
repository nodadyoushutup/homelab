#!/usr/bin/env python3
"""Helper to run Terraform and suppress specific -target warnings.

It forwards all Terraform output except the known warning blocks emitted when
using the -target flag, preserving exit codes and streaming behaviour.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import threading
from typing import Iterable, List


ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
WARNING_PHRASES: tuple[str, ...] = (
    "Warning: Resource targeting is in effect",
    "Warning: Applied changes may be incomplete",
)
RESUME_PREFIXES: tuple[str, ...] = (
    "Note:",
    "Apply complete",
    "Plan ",
    "No changes.",
    "Terraform has compared",
    "Outputs:",
    "Resources:",
    "Destroy complete",
    "Changes to Outputs",
)


def strip_ansi(text: str) -> str:
    """Remove ANSI escape sequences from *text*."""

    return ANSI_PATTERN.sub("", text)


def should_resume(stripped_line: str) -> bool:
    """Return True when the line marks the end of a warning block."""

    return any(stripped_line.startswith(prefix) for prefix in RESUME_PREFIXES)


def forward(line: str) -> None:
    """Write *line* to stdout immediately."""

    sys.stdout.write(line)
    sys.stdout.flush()


def pump_stderr(stream: Iterable[str]) -> None:
    """Continuously forward stderr output."""

    for chunk in stream:
        sys.stderr.write(chunk)
        sys.stderr.flush()


def run_terraform(args: List[str]) -> int:
    """Invoke Terraform with *args*, filtering targeted-apply warnings."""

    cmd = ["terraform", *args]
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    assert process.stdout is not None
    assert process.stderr is not None

    skip_block = False
    pending_line: str | None = None

    stderr_thread = threading.Thread(
        target=pump_stderr,
        args=(iter(process.stderr.readline, ""),),
        daemon=True,
    )
    stderr_thread.start()

    try:
        for line in iter(process.stdout.readline, ""):
            plain = strip_ansi(line)
            stripped = plain.strip()

            if skip_block:
                if should_resume(stripped):
                    skip_block = False
                    pending_line = None
                    forward(line)
                continue

            if any(phrase in plain for phrase in WARNING_PHRASES):
                skip_block = True
                pending_line = None
                continue

            if pending_line is not None:
                forward(pending_line)

            pending_line = line
    finally:
        process.stdout.close()
        stderr_thread.join()

    if not skip_block and pending_line is not None:
        forward(pending_line)

    return_code = process.wait()
    return return_code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run Terraform while hiding -target warning blocks.",
        add_help=False,
    )
    parser.add_argument("terraform_args", nargs=argparse.REMAINDER)

    known, _ = parser.parse_known_args()
    terraform_args = known.terraform_args

    # argparse.REMAINDER preserves the leading "--" separator if present.
    if terraform_args and terraform_args[0] == "--":
        terraform_args = terraform_args[1:]

    return run_terraform(terraform_args)


if __name__ == "__main__":
    sys.exit(main())
