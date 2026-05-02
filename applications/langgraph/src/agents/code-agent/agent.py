from __future__ import annotations

from pathlib import Path

from homelab_langgraph.agent_factories import create_code_agent


APP_DIR = Path(__file__).resolve().parent
agent = create_code_agent(APP_DIR)
