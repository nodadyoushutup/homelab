from __future__ import annotations

from typing import Sequence

from deepagents import CompiledSubAgent
from deepagents import create_deep_agent
from langchain.tools import tool

from framework.configuration import load_system_prompt
from framework.middleware import HomelabTaskDelegationMiddleware
from framework.mcp_support import load_mcp_tools

from .base import BaseAgent


class HomelabSupervisorAgent(BaseAgent):
    model_setting = "SUPERVISOR_MODEL"

    def __init__(
        self,
        app_dir,
        *,
        local_subagents: Sequence[CompiledSubAgent],
    ):
        super().__init__(app_dir)
        self.local_subagents = list(local_subagents)

    def prompt_variables(self) -> dict[str, str]:
        return {
            "specialist_topology": "specialist subagents that are co-deployed in this same Agent Server and callable only through this supervisor",
            "code_delegate_instruction": (
                "Before delegating repository work to `code`, run two `rag_search` calls: "
                "first a docs-oriented query for relevant `docs/subagents/code/` and "
                "`docs/workflows/` guidance, then a code-location query for likely files, "
                "services, manifests, or configuration. Then use the `task` tool to "
                "delegate every source code, repository, configuration, file path, filesystem, "
                "MCP workspace, or implementation request to the `code` specialist before "
                "answering directly, passing both RAG result sets as context. "
                "When implementation is driven by an **external issue record**, include "
                "a stable **issue identifier** in the `task` so `code` can load "
                "authoritative metadata if its configured MCPs provide issue-read "
                "tools; do not rely only on a paraphrased summary."
            ),
            "jira_delegate_instruction": (
                "Before delegating to `jira`, run a docs-oriented `rag_search` for "
                "relevant `docs/subagents/jira/` and workflow guidance. Then use "
                "the `task` tool to delegate every explicit Jira request, including "
                "create-issue requests, to the `jira` specialist before asking your "
                "own follow-up question or answering directly, passing the RAG doc "
                "anchors as context."
            ),
            "tech_lead_delegate_instruction": (
                "Before delegating to `tech_lead`, run two `rag_search` calls: "
                "first a docs-oriented query for relevant `docs/subagents/tech-lead/` "
                "and `docs/workflows/` guidance, then a code-location query for likely "
                "files, services, manifests, or configuration. Then use the `task` tool "
                "to delegate every technical soundness review, architecture review, "
                "code impact review, workflow impact review, or pre-development "
                "implementation guidance request to the `tech_lead` specialist before "
                "answering directly, passing both RAG result sets as context."
            ),
            "github_delegate_instruction": (
                "Before delegating to `github`, run a docs-oriented `rag_search` for "
                "relevant `docs/subagents/github/` and workflow guidance. Then use the "
                "`task` tool to delegate every explicit GitHub platform "
                "request (pull requests, PR review, checks, merge readiness, GitHub Actions "
                "workflow dispatch and run monitoring, repository queries via the GitHub MCP) "
                "to the `github` specialist before answering directly, passing the RAG doc "
                "anchors as context."
            ),
            "code_git_delegate_instruction": (
                "You must use the `task` tool to delegate every explicit **local repository git** "
                "request (status, fetch, pull, branch, checkout, commit, push) to the `code` "
                "specialist before answering directly, because git tools are exposed on mcp-code "
                "with filesystem work."
            ),
            "handoff_contract": "Every specialist call must return to this supervisor. A specialist may recommend another specialist, but it must not directly hand off, transfer, or continue the task outside its own response. After each specialist response, decide at the supervisor layer whether to call another specialist, call a tool, ask the user, or produce the final answer.",
        }

    def tools(self) -> list:
        @tool
        def describe_homelab_topology() -> str:
            """Describe the specialist topology this supervisor expects."""
            available = ", ".join(spec["name"] for spec in self.local_subagents)
            return (
                "This supervisor is running as the only supported user-facing graph in a single deployment with local specialist subagents. "
                f"Available specialists: {available}. "
                "Route work by calling specialists through the runtime task tool, capture their responses, and make every follow-up routing decision at the supervisor layer. "
                "Specialists do not transfer directly to each other."
            )

        rag_tools = load_mcp_tools(self.app_dir / "mcp.json")
        return [describe_homelab_topology, *rag_tools]

    def subagents(self) -> list[CompiledSubAgent]:
        return self.local_subagents

    def object_system_prompts(self) -> list[str]:
        """Supervisor instructions live only under the app directory, not docs/subagents/."""
        return [load_system_prompt(self.prompt_path, self.prompt_variables())]

    def build(self):
        kwargs = self.build_kwargs()
        kwargs["middleware"] = [HomelabTaskDelegationMiddleware(), *kwargs.get("middleware", [])]
        return create_deep_agent(**kwargs)
