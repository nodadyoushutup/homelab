from __future__ import annotations

from langchain.tools import tool

from framework.mcp_support import load_mcp_tools

from .base import BaseAgent


class GithubAgent(BaseAgent):
    model_setting = "GITHUB_MODEL"
    agent_prompt_filename = "github_system_prompt.md"
    docs_prompt_name = "github"
    require_docs_prompt = True

    def tools(self) -> list:
        @tool
        def describe_github_contract() -> str:
            """Summarize the GitHub specialist scope (GitHub MCP only)."""
            return (
                "The GitHub specialist owns GitHub platform work exposed by the GitHub "
                "MCP: pull requests, checks and CI, reviews, repository queries, and "
                "related API operations. It does not edit source files; route patches "
                "to `code`. Local git (branch, fetch, pull, commit, push) is handled by "
                "`code` when mcp-code exposes git tools. Follow the concrete GitHub "
                "runtime docs for this deployment."
            )

        return [describe_github_contract, *load_mcp_tools(self.app_dir / "mcp.json")]
