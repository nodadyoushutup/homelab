#!/usr/bin/env python3
"""Thin project-root entrypoint for the bootstrap application."""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
_APPLICATIONS = _ROOT / "applications"

# `python bootstrap.py` puts the repo root on sys.path first, which would
# shadow `applications/bootstrap`. Prefer the application package instead.
if sys.path and Path(sys.path[0]).resolve() == _ROOT:
    sys.path.pop(0)
sys.path.insert(0, str(_APPLICATIONS))

from bootstrap import main


if __name__ == "__main__":
    raise SystemExit(main())
