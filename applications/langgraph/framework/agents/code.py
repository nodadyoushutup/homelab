from __future__ import annotations

from pathlib import Path

from langchain.tools import tool

from framework.configuration import resolve_repo_root
from framework.mcp_support import DEFAULT_REPO_SEARCH_EXCLUDES
from framework.mcp_support import load_mcp_tools
from framework.mcp_support import wrap_ast_grep_tools
from framework.mcp_support import wrap_filesystem_tools

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
                "support for source code, configuration, paths, filesystem state, "
                "and behavior. It should stay scoped to the repository root "
                f"`{self.repo_root}`, inspect source-of-truth files before acting, "
                "make explicit code changes only when requested, and return concise "
                "findings, artifacts, risks, and next actions to the caller."
            )

        mcp_tools = wrap_ast_grep_tools(
            wrap_filesystem_tools(
                load_mcp_tools(self.app_dir / "mcp.json"),
                self.repo_root,
            ),
            self.repo_root,
        )
        return [describe_code_contract, *mcp_tools]
