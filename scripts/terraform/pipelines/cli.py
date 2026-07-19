"""CLI argument parsing shared by the slice pipeline entrypoints.

Reproduces the exact option handling every bash ``pipeline/<slice>.sh`` uses:

    <slice>.py [--tfvars <path>] [--backend <path>] [slice_tfvars] [backend_config]

Values are returned split into ``--option`` vs positional so callers can apply
bash's precedence exactly (see ``SlicePipeline`` for the resolution order).
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from .logging_util import PipelineError


@dataclass
class SliceArgs:
    opt_tfvars: str | None = None
    opt_backend: str | None = None
    pos_tfvars: str | None = None
    pos_backend: str | None = None
    help: bool = False


def parse_slice_args(argv: list[str], *, usage: str) -> SliceArgs:
    """Parse ``--tfvars/--backend`` options + up to two positionals."""

    result = SliceArgs()
    i = 0
    n = len(argv)
    while i < n:
        arg = argv[i]
        if arg == "--tfvars":
            if i + 1 >= n:
                raise PipelineError("--tfvars requires a path", code=2)
            result.opt_tfvars = argv[i + 1]
            i += 2
            continue
        if arg == "--backend":
            if i + 1 >= n:
                raise PipelineError("--backend requires a path", code=2)
            result.opt_backend = argv[i + 1]
            i += 2
            continue
        if arg in ("-h", "--help"):
            print(usage)
            result.help = True
            return result
        if arg.startswith("--"):
            raise PipelineError(f"Unknown option: {arg}\n{usage}", code=2)
        if result.pos_tfvars is None:
            result.pos_tfvars = arg
        elif result.pos_backend is None:
            result.pos_backend = arg
        else:
            raise PipelineError(f"Unexpected argument: {arg}\n{usage}", code=2)
        i += 1

    return result


def env_first(*names: str) -> str | None:
    """Return the first non-empty environment value among ``names``."""

    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return None
