#!/usr/bin/env python3
"""Packer image build — Python port of packer/pipeline/packer.sh (run: python3 <path>).

Usage: packer/pipeline/packer.py --version <version> [options]
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines.packer_build import main

if __name__ == "__main__":
    main()
