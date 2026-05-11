from __future__ import annotations

from pathlib import Path

from framework.agents import CodeAgent
from framework.agents import GithubAgent
from framework.agents import HomelabSupervisorAgent
from framework.agents import JiraAgent
from framework.agents import TechLeadAgent


APP_DIR = Path(__file__).resolve().parent
SUBAGENTS_DIR = APP_DIR.parent / "subagents"
CODE_APP_DIR = SUBAGENTS_DIR / "code"
GITHUB_APP_DIR = SUBAGENTS_DIR / "github"
JIRA_APP_DIR = SUBAGENTS_DIR / "jira"
TECH_LEAD_APP_DIR = SUBAGENTS_DIR / "tech-lead"

_code = CodeAgent(CODE_APP_DIR).build()
_github = GithubAgent(GITHUB_APP_DIR).build()
_jira = JiraAgent(JIRA_APP_DIR).build()
_tech_lead = TechLeadAgent(TECH_LEAD_APP_DIR).build()
agent = HomelabSupervisorAgent(
    APP_DIR,
    local_subagents=[
        {
            "name": "code",
            "description": "Code specialist for repository-backed source code, configuration, filesystem, local git (when exposed by mcp-code), path, and implementation work. Always returns findings, changed files, risks, and next actions to the supervisor.",
            "runnable": _code,
        },
        {
            "name": "github",
            "description": "GitHub specialist for pull requests, checks, reviews, repository queries, and GitHub Actions workflow visibility via the GitHub MCP. Does not edit repo files. Always returns GitHub results and recommended next steps to the supervisor.",
            "runnable": _github,
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
