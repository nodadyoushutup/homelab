"""Enforce Homelab retrieval-first and read-before-write workflows.

Supervisor: block `task` to `code` until `rag_search` completed after the latest
user message; block `general-purpose` delegation (Deep Agents default) so work
routes through `code`, `git`, `jira`, or `tech_lead`.

Code specialist: block mutating filesystem / shell tools until at least one
read/search style tool produced a tool result in the current subagent thread.

Disable with env ``HOMELAB_DISABLE_WORKFLOW_GATES=1`` (break-glass only).
"""

from __future__ import annotations

import json
import os
from collections.abc import Awaitable, Callable
from typing import Any

from langchain.agents.middleware.types import AgentMiddleware, ContextT, ResponseT
from langchain.tools.tool_node import ToolCallRequest
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage

FORBIDDEN_TASK_SUBAGENTS = frozenset({"general-purpose"})
CODE_SUBAGENT = "code"
RAG_TOOL = "rag_search"
MUTATING_TOOLS = frozenset({"write_file", "edit_file", "execute"})
READ_OR_ANALYSIS_TOOLS = frozenset(
    {
        "read_file",
        "read_multiple_files",
        "read_text_file",
        "read_media_file",
        "list_directory",
        "list_directory_with_sizes",
        "directory_tree",
        "get_file_info",
        "search_files",
        "search_repository_files",
        "list_allowed_directories",
        "glob",
        "grep",
        "ls",
        "find_code",
        "find_code_by_rule",
        "dump_syntax_tree",
        "test_match_code_rule",
        "server_info",
    }
)


def workflow_gates_disabled() -> bool:
    return os.getenv("HOMELAB_DISABLE_WORKFLOW_GATES", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }


def _tool_call_name(tc: Any) -> str:
    if isinstance(tc, dict):
        name = tc.get("name")
        return str(name) if name else ""
    return str(getattr(tc, "name", "") or "")


def _tool_call_id(tc: Any) -> str:
    if isinstance(tc, dict):
        tid = tc.get("id")
        return str(tid) if tid else ""
    return str(getattr(tc, "id", "") or "")


def _messages_from_state(state: Any) -> list[Any]:
    if state is None:
        return []
    messages = state.get("messages") if isinstance(state, dict) else getattr(state, "messages", None)
    return list(messages or [])


def _rag_preflight_done_since_last_human(messages: list[Any]) -> bool:
    """True if an ``rag_search`` tool call completed after the last HumanMessage."""
    last_human_idx = -1
    for i, m in enumerate(messages):
        if isinstance(m, HumanMessage):
            last_human_idx = i
    if last_human_idx < 0:
        return False

    segment = messages[last_human_idx + 1 :]
    rag_ids: set[str] = set()
    for m in segment:
        if isinstance(m, AIMessage) and m.tool_calls:
            for tc in m.tool_calls:
                if _tool_call_name(tc) == RAG_TOOL:
                    tid = _tool_call_id(tc)
                    if tid:
                        rag_ids.add(tid)
    if not rag_ids:
        return False

    finished: set[str] = set()
    for m in segment:
        if isinstance(m, ToolMessage) and m.tool_call_id in rag_ids:
            finished.add(m.tool_call_id)
    return bool(finished & rag_ids)


def _read_analysis_completed(messages: list[Any]) -> bool:
    """True if a read/search tool produced a ToolMessage in this thread."""
    pending: set[str] = set()
    for m in messages:
        if isinstance(m, AIMessage) and m.tool_calls:
            for tc in m.tool_calls:
                name = _tool_call_name(tc)
                if name in READ_OR_ANALYSIS_TOOLS:
                    tid = _tool_call_id(tc)
                    if tid:
                        pending.add(tid)
    if not pending:
        return False

    done: set[str] = set()
    for m in messages:
        if isinstance(m, ToolMessage) and m.tool_call_id in pending:
            done.add(m.tool_call_id)
    return bool(done & pending)


def _gate_error_payload(*, gate: str, detail: str) -> str:
    return json.dumps(
        {
            "ok": False,
            "recoverable": True,
            "gate": gate,
            "error": detail,
            "instruction": (
                "Follow the gate, then retry this tool. "
                "Break-glass: set HOMELAB_DISABLE_WORKFLOW_GATES=1 on the agent process "
                "(not recommended)."
            ),
        },
        indent=2,
    )


def _task_delegation_denial(request: ToolCallRequest) -> ToolMessage | None:
    call = request.tool_call
    if call.get("name") != "task" or workflow_gates_disabled():
        return None

    args = call.get("args") or {}
    sub = str(args.get("subagent_type", "")).strip()

    if sub in FORBIDDEN_TASK_SUBAGENTS:
        return ToolMessage(
            content=_gate_error_payload(
                gate="forbidden_subagent",
                detail=(
                    "Homelab does not delegate to `general-purpose`. "
                    "Use `code` for repository file work, `git` for git/GitHub, `jira` for Jira, or `tech_lead` for review."
                ),
            ),
            tool_call_id=call["id"],
            name="task",
            status="error",
        )

    if sub == CODE_SUBAGENT and not _rag_preflight_done_since_last_human(
        _messages_from_state(request.state)
    ):
        return ToolMessage(
            content=_gate_error_payload(
                gate="rag_before_code",
                detail=(
                    "Call `rag_search` at least once after the user's latest message "
                    "(iterate with narrower queries until you know where relevant code "
                    "and docs live). Then delegate to `code` with that context."
                ),
            ),
            tool_call_id=call["id"],
            name="task",
            status="error",
        )
    return None


def _code_write_denial(request: ToolCallRequest) -> ToolMessage | None:
    call = request.tool_call
    tool_name = call.get("name", "")
    if tool_name not in MUTATING_TOOLS or workflow_gates_disabled():
        return None

    if not _read_analysis_completed(_messages_from_state(request.state)):
        return ToolMessage(
            content=_gate_error_payload(
                gate="read_before_write",
                detail=(
                    "Run targeted read or search tools first "
                    "(`read_file`, `grep`, `glob`, `find_code`, `list_directory`, …) "
                    "so the edit is grounded in inspected code. Then retry the write."
                ),
            ),
            tool_call_id=call["id"],
            name=tool_name,
            status="error",
        )
    return None


class HomelabTaskDelegationMiddleware(AgentMiddleware[Any, ContextT, ResponseT]):
    """Supervisor-only gates on the Deep Agents ``task`` tool."""

    def wrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], ToolMessage | Any],
    ) -> ToolMessage | Any:
        denied = _task_delegation_denial(request)
        if denied is not None:
            return denied
        return handler(request)

    async def awrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], Awaitable[ToolMessage | Any]],
    ) -> ToolMessage | Any:
        denied = _task_delegation_denial(request)
        if denied is not None:
            return denied
        return await handler(request)


class CodeReadBeforeWriteMiddleware(AgentMiddleware[Any, ContextT, ResponseT]):
    """Code specialist: require read/search tools before mutating tools."""

    def wrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], ToolMessage | Any],
    ) -> ToolMessage | Any:
        denied = _code_write_denial(request)
        if denied is not None:
            return denied
        return handler(request)

    async def awrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], Awaitable[ToolMessage | Any]],
    ) -> ToolMessage | Any:
        denied = _code_write_denial(request)
        if denied is not None:
            return denied
        return await handler(request)
