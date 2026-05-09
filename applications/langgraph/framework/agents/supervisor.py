from __future__ import annotations

from typing import Sequence

from deepagents import CompiledSubAgent
from langchain.tools import tool

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
            "code_delegate_instruction": "You must use the `task` tool to delegate every source code, repository, configuration, file path, filesystem, MCP workspace, or implementation request to the `code` specialist before answering directly.",
            "jira_delegate_instruction": "You must use the `task` tool to delegate every explicit Jira request, including create-issue requests, to the `jira` specialist before asking your own follow-up question or answering directly.",
            "tech_lead_delegate_instruction": "You must use the `task` tool to delegate every technical soundness review, architecture review, code impact review, workflow impact review, or pre-development implementation guidance request to the `tech_lead` specialist before answering directly.",
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
