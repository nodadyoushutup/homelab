from __future__ import annotations

from pathlib import Path

from framework.agents import CodeAgent


APP_DIR = Path(__file__).resolve().parent
agent = CodeAgent(APP_DIR).build()
