from __future__ import annotations

from pathlib import Path

from framework.agent_factories import create_jira_agent


APP_DIR = Path(__file__).resolve().parent
agent = create_jira_agent(APP_DIR)
