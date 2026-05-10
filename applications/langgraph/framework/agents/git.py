from __future__ import annotations

from langchain.tools import tool

from framework.mcp_support import load_mcp_tools

from .base import BaseAgent


class GitAgent(BaseAgent):
    model_setting = "GIT_MODEL"
    agent_prompt_filename = "git_system_prompt.md"
    docs_prompt_name = "git"
    require_docs_prompt = True

    def tools(self) -> list:
        @tool
        def describe_git_github_contract() -> str:
            """Summarize the Git specialist scope (git MCP + GitHub MCP)."""
            return (
                "The Git specialist owns local git operations (status, fetch, pull, "
                "branches, commits when requested) via the Git MCP and GitHub operations "
                "(pull requests, checks, reviews, repository queries) via the GitHub MCP. "
                "It follows branch and PR policies in docs/subagents/git/. "
                "It does not edit source files directly; route implementation to `code`. "
                "It does not own Jira transitions; route those to `jira`."
            )

        return [describe_git_github_contract, *load_mcp_tools(self.app_dir / "mcp.json")]
