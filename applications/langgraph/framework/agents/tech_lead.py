from __future__ import annotations

from pathlib import Path

from deepagents import create_deep_agent
from langchain.tools import tool

from framework.configuration import resolve_repo_root
from framework.middleware import McpWorkspaceBindingMiddleware
from framework.mcp_support import CODE_TECH_LEAD_MCP_SERVERS_PATH
from framework.mcp_support import DEFAULT_REPO_SEARCH_EXCLUDES
from framework.mcp_support import load_workspace_routed_mcp_tools

from .base import BaseAgent


class TechLeadAgent(BaseAgent):
    model_setting = "TECH_LEAD_MODEL"
    agent_prompt_filename = "tech_lead_system_prompt.md"
    docs_prompt_name = "tech-lead"
    require_docs_prompt = True

    @property
    def repo_root(self) -> Path:
        return resolve_repo_root(self.settings.get("TECH_LEAD_REPOSITORY_ROOT"))

    def prompt_variables(self) -> dict[str, str]:
        return {
            "default_search_excludes": ", ".join(DEFAULT_REPO_SEARCH_EXCLUDES),
            "repo_root": str(self.repo_root),
        }

    def tools(self) -> list:
        @tool
        def describe_tech_lead_contract() -> str:
            """Describe what the Tech Lead agent is responsible for."""
            return (
                "The Tech Lead agent owns technical soundness review, code impact "
                "analysis, workflow impact analysis, and senior implementation "
                "guidance before development starts. It should stay scoped to the "
                f"repository root `{self.repo_root}`, inspect source-of-truth files, "
                "identify risks and blockers, and return concise review results to "
                "the caller."
            )

        mcp_tools = load_workspace_routed_mcp_tools(
            CODE_TECH_LEAD_MCP_SERVERS_PATH,
            wrap_profile="tech_lead",
            static_repo=self.repo_root,
        )
        return [describe_tech_lead_contract, *mcp_tools]

    def build(self):
        kwargs = self.build_kwargs()
        kwargs["middleware"] = [
            McpWorkspaceBindingMiddleware(),
            *kwargs.get("middleware", []),
        ]
        return create_deep_agent(**kwargs)
