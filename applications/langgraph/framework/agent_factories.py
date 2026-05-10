from __future__ import annotations

from pathlib import Path
from typing import Sequence

from deepagents import CompiledSubAgent

from .agents import CodeAgent
from .agents import GitAgent
from .agents import HomelabSupervisorAgent
from .agents import JiraAgent
from .agents import TechLeadAgent


def create_supervisor_agent(
    app_dir: Path,
    *,
    local_subagents: Sequence[CompiledSubAgent],
):
    return HomelabSupervisorAgent(
        app_dir,
        local_subagents=local_subagents,
    ).build()


def create_code_agent(app_dir: Path):
    return CodeAgent(app_dir).build()


def create_git_agent(app_dir: Path):
    return GitAgent(app_dir).build()


def create_jira_agent(app_dir: Path):
    return JiraAgent(app_dir).build()


def create_tech_lead_agent(app_dir: Path):
    return TechLeadAgent(app_dir).build()
