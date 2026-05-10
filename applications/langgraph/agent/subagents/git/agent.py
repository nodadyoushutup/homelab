from __future__ import annotations

from pathlib import Path

from framework.agents import GitAgent


APP_DIR = Path(__file__).resolve().parent
agent = GitAgent(APP_DIR).build()
