"""Bind mcp-code routing from LangGraph ``configurable`` for each tool call."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from langchain.agents.middleware.types import AgentMiddleware, ContextT, ResponseT
from langchain.tools.tool_node import ToolCallRequest
from langchain_core.messages import ToolMessage

from framework.mcp_workspace_context import bind_from_configurable
from framework.mcp_workspace_context import reset_tokens


class McpWorkspaceBindingMiddleware(AgentMiddleware[Any, ContextT, ResponseT]):
    """Set mcp-code URL / repo root contextvars from ``runtime.config`` before tools run."""

    def wrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], ToolMessage | Any],
    ) -> ToolMessage | Any:
        runtime = getattr(request, "runtime", None)
        config = getattr(runtime, "config", None) if runtime is not None else None
        configurable = (config or {}).get("configurable") if isinstance(config, dict) else None
        tokens = bind_from_configurable(configurable if isinstance(configurable, dict) else None)
        try:
            return handler(request)
        finally:
            reset_tokens(tokens)

    async def awrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], Awaitable[ToolMessage | Any]],
    ) -> ToolMessage | Any:
        runtime = getattr(request, "runtime", None)
        config = getattr(runtime, "config", None) if runtime is not None else None
        configurable = (config or {}).get("configurable") if isinstance(config, dict) else None
        tokens = bind_from_configurable(configurable if isinstance(configurable, dict) else None)
        try:
            return await handler(request)
        finally:
            reset_tokens(tokens)
