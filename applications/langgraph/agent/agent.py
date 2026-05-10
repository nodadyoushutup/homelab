from __future__ import annotations

from pathlib import Path

from framework.agents import CodeAgent
from framework.agents import GitAgent
from framework.agents import HomelabSupervisorAgent
from framework.agents import JiraAgent
from framework.agents import TechLeadAgent


APP_DIR = Path(__file__).resolve().parent
SUBAGENTS_DIR = APP_DIR / "subagents"
CODE_APP_DIR = SUBAGENTS_DIR / "code"
GIT_APP_DIR = SUBAGENTS_DIR / "git"
JIRA_APP_DIR = SUBAGENTS_DIR / "jira"
TECH_LEAD_APP_DIR = SUBAGENTS_DIR / "tech-lead"

_code = CodeAgent(CODE_APP_DIR).build()
_git = GitAgent(GIT_APP_DIR).build()
_jira = JiraAgent(JIRA_APP_DIR).build()
_tech_lead = TechLeadAgent(TECH_LEAD_APP_DIR).build()
agent = HomelabSupervisorAgent(
    APP_DIR,
    local_subagents=[
        {
            "name": "code",
            "description": "Code specialist for repository-backed source code, configuration, filesystem, path, and implementation work. Always returns findings, changed files, risks, and next actions to the supervisor.",
            "runnable": _code,
        },
        {
            "name": "git",
            "description": "Git + GitHub specialist for local git operations (branches, sync, commits when requested) and GitHub operations (pull requests, checks, reviews). Always returns git/GitHub results and recommended next steps to the supervisor.",
            "runnable": _git,
        },
        {
            "name": "jira",
            "description": "Jira specialist for issue discovery, updates, comments, and workflow actions. Always returns Jira results to the supervisor for the next routing decision.",
            "runnable": _jira,
        },
        {
            "name": "tech_lead",
            "description": "Tech Lead specialist for technical soundness review, architecture review, code impact analysis, workflow impact analysis, and senior implementation guidance. Always returns review findings, risks, blockers, and recommended next actions to the supervisor.",
            "runnable": _tech_lead,
        },
    ],
).build()
