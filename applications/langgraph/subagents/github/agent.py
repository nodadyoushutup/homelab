from __future__ import annotations

from pathlib import Path

from framework.agents import GithubAgent


APP_DIR = Path(__file__).resolve().parent
agent = GithubAgent(APP_DIR).build()
