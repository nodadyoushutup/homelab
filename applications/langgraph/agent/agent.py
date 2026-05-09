from __future__ import annotations

from pathlib import Path

from framework.agent_factories import create_supervisor_agent
from framework.agent_factories import create_code_agent
from framework.agent_factories import create_jira_agent


APP_DIR = Path(__file__).resolve().parent
SUBAGENTS_DIR = APP_DIR / "subagents"
CODE_APP_DIR = SUBAGENTS_DIR / "code-agent"
JIRA_APP_DIR = SUBAGENTS_DIR / "jira-agent"

code_agent = create_code_agent(CODE_APP_DIR)
jira_agent = create_jira_agent(JIRA_APP_DIR)
langgraph = create_supervisor_agent(
    APP_DIR,
    local_subagents=[
        {
            "name": "code_agent",
            "description": "Mandatory specialist for any code, config, repository, path, filesystem, or implementation question.",
            "runnable": code_agent,
        },
        {
            "name": "jira_agent",
            "description": "Jira specialist for issue discovery, updates, comments, and workflow actions.",
            "runnable": jira_agent,
        },
    ],
)

agent = langgraph
