from __future__ import annotations

from pathlib import Path

from homelab_langgraph.agent_factories import create_supervisor_agent
from homelab_langgraph.agent_factories import create_code_analysis_agent
from homelab_langgraph.agent_factories import create_jira_agent


APP_DIR = Path(__file__).resolve().parent
APPS_DIR = APP_DIR.parent
CODE_ANALYSIS_APP_DIR = APPS_DIR / "code-analysis-agent"
JIRA_APP_DIR = APPS_DIR / "jira-agent"

code_analysis_agent = create_code_analysis_agent(CODE_ANALYSIS_APP_DIR)
jira_agent = create_jira_agent(JIRA_APP_DIR)
controller_agent = create_supervisor_agent(
    APP_DIR,
    local_subagents=[
        {
            "name": "code_analysis_agent",
            "description": "Repository and implementation analysis specialist for code paths, ownership, and change surfaces.",
            "runnable": code_analysis_agent,
        },
        {
            "name": "jira_agent",
            "description": "Jira specialist for issue discovery, updates, comments, and workflow actions.",
            "runnable": jira_agent,
        },
    ],
)

agent = controller_agent
