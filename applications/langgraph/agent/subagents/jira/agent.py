from __future__ import annotations

from pathlib import Path

from framework.agents import JiraAgent


APP_DIR = Path(__file__).resolve().parent
agent = JiraAgent(APP_DIR).build()
