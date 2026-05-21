from __future__ import annotations

from pathlib import Path

from deepagents import create_deep_agent
from langchain.tools import tool

from framework.configuration import resolve_repo_root
from framework.middleware import CodeReadBeforeWriteMiddleware
from framework.middleware import McpWorkspaceBindingMiddleware
from framework.mcp_support import CODE_MCP_SERVERS_PATH
from framework.mcp_support import DEFAULT_REPO_SEARCH_EXCLUDES
from framework.mcp_support import load_workspace_routed_mcp_tools

from .base import BaseAgent


class CodeAgent(BaseAgent):
    model_setting = "CODE_MODEL"
    agent_prompt_filename = "code_system_prompt.md"
    docs_prompt_name = "code"
    require_docs_prompt = True

    @property
    def repo_root(self) -> Path:
        return resolve_repo_root(self.settings.get("CODE_REPOSITORY_ROOT"))

    def prompt_variables(self) -> dict[str, str]:
        return {
            "default_search_excludes": ", ".join(DEFAULT_REPO_SEARCH_EXCLUDES),
            "repo_root": str(self.repo_root),
        }

    def tools(self) -> list:
        @tool
        def describe_code_contract() -> str:
            """Describe what the Code agent is responsible for."""
            return (
                "The Code agent owns repository-backed analysis and implementation "
                "support for source code, configuration, paths, and any "
                "MCP tools configured for this runtime (for example RAG search or "
                "issue-tracker reads when the deployment enables them), and "
                "behavior. It should stay scoped to the repository root "
                f"`{self.repo_root}`, inspect source-of-truth files before acting, "
                "make explicit code changes only when requested, and return concise "
                "findings, artifacts, risks, and next actions to the caller. GitHub "
                "PR/check/Actions API work is normally routed to the github specialist."
            )

        mcp_tools = load_workspace_routed_mcp_tools(
            CODE_MCP_SERVERS_PATH,
            wrap_profile="code",
            static_repo=self.repo_root,
        )
        return [describe_code_contract, *mcp_tools]

    def build(self):
        kwargs = self.build_kwargs()
        kwargs["middleware"] = [
            McpWorkspaceBindingMiddleware(),
            CodeReadBeforeWriteMiddleware(),
            *kwargs.get("middleware", []),
        ]
        return create_deep_agent(**kwargs)
