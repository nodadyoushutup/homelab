from __future__ import annotations

import json
from dataclasses import dataclass
from uuid import uuid4

import httpx
from langchain.tools import tool


@dataclass(frozen=True)
class RemoteAgentDefinition:
    name: str
    description: str
    base_url: str | None
    assistant_id: str | None
    graph_id: str | None = None
    api_key: str | None = None

    def endpoint_for(self, assistant_id: str | None) -> str | None:
        if not self.base_url or not assistant_id:
            return None
        return f"{self.base_url.rstrip('/')}/a2a/{assistant_id}"


async def resolve_remote_assistant_id(
    client: httpx.AsyncClient,
    definition: RemoteAgentDefinition,
) -> str | None:
    if definition.assistant_id:
        return definition.assistant_id

    if not definition.base_url or not definition.graph_id:
        return None

    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if definition.api_key:
        headers["X-Api-Key"] = definition.api_key
        headers["X-Auth-Scheme"] = "langsmith-api-key"

    response = await client.post(
        f"{definition.base_url.rstrip('/')}/assistants/search",
        json={
            "graph_id": definition.graph_id,
            "limit": 10,
            "offset": 0,
        },
        headers=headers,
    )
    response.raise_for_status()
    payload = response.json()
    if not payload:
        return None
    return payload[0]["assistant_id"]


def _extract_text(result_obj: dict) -> str:
    for artifact in result_obj.get("artifacts", []) or []:
        for part in artifact.get("parts", []) or []:
            if part.get("kind") == "text" and part.get("text"):
                return part["text"]

    status_message = (result_obj.get("status") or {}).get("message") or {}
    for part in status_message.get("parts", []) or []:
        if part.get("kind") == "text" and part.get("text"):
            return part["text"]

    return json.dumps(result_obj, indent=2, sort_keys=True)


def build_remote_delegate_tool(definition: RemoteAgentDefinition):
    if not definition.base_url or not (definition.assistant_id or definition.graph_id):
        @tool(definition.name, description=definition.description)
        def missing_remote_agent_delegate(request: str) -> str:
            """Explain that the remote agent has not been configured yet."""
            return (
                f"The remote agent tool `{definition.name}` is scaffolded but not configured yet. "
                "Set the remote agent URL and either an assistant id or graph id in this app's .env file, then retry. "
                f"Original request: {request}"
            )

        return missing_remote_agent_delegate

    @tool(definition.name, description=definition.description)
    async def remote_agent_delegate(request: str) -> str:
        """Delegate a task to a remote LangGraph agent over A2A."""
        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        if definition.api_key:
            headers["X-Api-Key"] = definition.api_key
            headers["X-Auth-Scheme"] = "langsmith-api-key"

        async with httpx.AsyncClient(timeout=45.0) as client:
            assistant_id = await resolve_remote_assistant_id(client, definition)
            endpoint = definition.endpoint_for(assistant_id)
            if not endpoint:
                raise RuntimeError(
                    f"Could not resolve a remote assistant endpoint for `{definition.name}`. "
                    "Check the remote base URL and graph or assistant id configuration."
                )

            payload = {
                "jsonrpc": "2.0",
                "id": str(uuid4()),
                "method": "message/send",
                "params": {
                    "message": {
                        "role": "user",
                        "parts": [{"kind": "text", "text": request}],
                        "messageId": str(uuid4()),
                    }
                },
                "metadata": {"thread_id": str(uuid4())},
            }

            response = await client.post(endpoint, json=payload, headers=headers)
            response.raise_for_status()
            result = response.json()

        if "error" in result:
            error_message = result["error"].get("message", "Unknown remote agent error")
            raise RuntimeError(error_message)

        return _extract_text(result.get("result", {}))

    return remote_agent_delegate
