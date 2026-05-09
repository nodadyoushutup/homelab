from __future__ import annotations

from pathlib import Path

from framework.agents import TechLeadAgent


APP_DIR = Path(__file__).resolve().parent
agent = TechLeadAgent(APP_DIR).build()
