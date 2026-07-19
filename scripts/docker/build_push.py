#!/usr/bin/env python3
"""Docker multi-arch build+push — Python port of build_push.sh (run: python3 <path>).

Usage: scripts/docker/build_push.py --version <version> --target_registry <github|zot|both> --build_target <target> [options]
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines.docker_build import main

if __name__ == "__main__":
    main()
