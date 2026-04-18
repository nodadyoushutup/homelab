from __future__ import annotations

import contextlib
import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import redis.asyncio as redis
import uvicorn
from mcp.server.fastmcp import Context, FastMCP
from mcp.server.session import ServerSession
from mcp.server.transport_security import TransportSecuritySettings
from starlette.applications import Starlette
from starlette.routing import Mount


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    value = int(raw)
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


@dataclass(slots=True)
class Settings:
    host: str
    port: int
    redis_url: str
    key_prefix: str
    allowed_hosts: list[str]
    allowed_origins: list[str]
    agent_ttl_seconds: int
    task_ttl_seconds: int
    completed_task_ttl_seconds: int
    summary_ttl_seconds: int
    message_list_limit: int


@dataclass(slots=True)
class AppContext:
    redis: redis.Redis
    settings: Settings


def load_settings() -> Settings:
    redis_url = os.getenv("MCP_AGENT_PROTOCOL_REDIS_URL", "").strip()
    if not redis_url:
        raise ValueError("MCP_AGENT_PROTOCOL_REDIS_URL is required")

    default_allowed_hosts = [
        "127.0.0.1",
        "127.0.0.1:*",
        "localhost",
        "localhost:*",
        "[::1]",
        "[::1]:*",
        "swarm-cp-0.local",
        "swarm-cp-0.local:*",
        "mcp.agent-protocol.nodadyoushutup.com",
        "mcp.agent-protocol.nodadyoushutup.com:*",
    ]
    default_allowed_origins = [
        "http://127.0.0.1",
        "http://127.0.0.1:*",
        "http://localhost",
        "http://localhost:*",
        "http://[::1]",
        "http://[::1]:*",
        "http://swarm-cp-0.local",
        "http://swarm-cp-0.local:*",
        "https://mcp.agent-protocol.nodadyoushutup.com",
    ]

    allowed_hosts = [
        value.strip()
        for value in os.getenv("MCP_AGENT_PROTOCOL_ALLOWED_HOSTS", ",".join(default_allowed_hosts)).split(",")
        if value.strip()
    ]
    allowed_origins = [
        value.strip()
        for value in os.getenv("MCP_AGENT_PROTOCOL_ALLOWED_ORIGINS", ",".join(default_allowed_origins)).split(",")
        if value.strip()
    ]

    return Settings(
        host=os.getenv("MCP_AGENT_PROTOCOL_HOST", "0.0.0.0"),
        port=_env_int("MCP_AGENT_PROTOCOL_LISTEN_PORT", 8100),
        redis_url=redis_url,
        key_prefix=os.getenv("MCP_AGENT_PROTOCOL_KEY_PREFIX", "agent-protocol").strip(),
        allowed_hosts=allowed_hosts,
        allowed_origins=allowed_origins,
        agent_ttl_seconds=_env_int("MCP_AGENT_PROTOCOL_DEFAULT_AGENT_TTL_SECONDS", 90),
        task_ttl_seconds=_env_int("MCP_AGENT_PROTOCOL_DEFAULT_TASK_TTL_SECONDS", 300),
        completed_task_ttl_seconds=_env_int("MCP_AGENT_PROTOCOL_COMPLETED_TASK_TTL_SECONDS", 604800),
        summary_ttl_seconds=_env_int("MCP_AGENT_PROTOCOL_DEFAULT_SUMMARY_TTL_SECONDS", 86400),
        message_list_limit=_env_int("MCP_AGENT_PROTOCOL_MESSAGE_LIST_LIMIT", 200),
    )


SETTINGS = load_settings()


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _isoformat(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _future_iso(seconds: int) -> str:
    return _isoformat(_utc_now() + timedelta(seconds=seconds))


def _serialize(payload: dict[str, object]) -> str:
    return json.dumps(payload, separators=(",", ":"), sort_keys=True)


def _deserialize(payload: str | None) -> dict[str, Any] | None:
    if payload is None:
        return None
    return json.loads(payload)


def _agent_key(settings: Settings, agent_id: str) -> str:
    return f"{settings.key_prefix}:agent:{agent_id}"


def _active_agents_key(settings: Settings) -> str:
    return f"{settings.key_prefix}:agents:active"


def _task_key(settings: Settings, task_id: str) -> str:
    return f"{settings.key_prefix}:task:{task_id}"


def _summary_key(settings: Settings, scope: str, scope_id: str) -> str:
    return f"{settings.key_prefix}:summary:{scope}:{scope_id}"


def _message_key(settings: Settings) -> str:
    return f"{settings.key_prefix}:messages"


def _message_thread_key(settings: Settings, request_id: str) -> str:
    return f"{settings.key_prefix}:messages:request:{request_id}"


def _normalize_list(values: list[str] | None) -> list[str]:
    if not values:
        return []
    return [value for value in values if value.strip()]


def _normalize_mapping(values: dict[str, object] | None) -> dict[str, object]:
    if not values:
        return {}
    return values


async def _prune_active_agents(client: redis.Redis, settings: Settings) -> None:
    await client.zremrangebyscore(_active_agents_key(settings), "-inf", _utc_now().timestamp())


async def _store_message(client: redis.Redis, settings: Settings, payload: dict[str, object]) -> None:
    serialized = _serialize(payload)
    await client.lpush(_message_key(settings), serialized)
    await client.ltrim(_message_key(settings), 0, settings.message_list_limit - 1)
    await client.lpush(_message_thread_key(settings, str(payload["request_id"])), serialized)
    await client.ltrim(_message_thread_key(settings, str(payload["request_id"])), 0, settings.message_list_limit - 1)


@contextlib.asynccontextmanager
async def app_lifespan(_server: FastMCP) -> AppContext:
    client = redis.from_url(SETTINGS.redis_url, decode_responses=True)
    await client.ping()
    try:
        yield AppContext(redis=client, settings=SETTINGS)
    finally:
        await client.aclose()


MCP = FastMCP(
    "Agent Protocol",
    stateless_http=True,
    json_response=True,
    lifespan=app_lifespan,
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=SETTINGS.allowed_hosts,
        allowed_origins=SETTINGS.allowed_origins,
    ),
)


@MCP.resource("agent-protocol://contract")
def protocol_contract() -> str:
    """Return the JSON-oriented request/response contract and storage guidance."""
    return json.dumps(
        {
            "request_contract": {
                "request_id": "<unique-id>",
                "from_agent": "<caller-name>",
                "to_agent": "<target-name>",
                "task_type": "<short-capability-name>",
                "objective": "<what must be achieved>",
                "repo_scope": ["<bounded paths or services>"],
                "context": {"known_facts": ["<background>"]},
                "constraints": ["<rules or limits>"],
                "inputs": {"artifacts": ["<prior findings or file paths>"]},
                "expected_output": "<what form the answer should take>",
                "done_criteria": "<how the caller knows the task is complete>",
            },
            "response_contract": {
                "request_id": "<same-id>",
                "from_agent": "<responder-name>",
                "status": "<completed|partial|blocked>",
                "summary": "<short answer>",
                "findings": ["<facts discovered from the work>"],
                "assumptions": ["<things inferred but not proven>"],
                "risks": ["<important caveats or failure modes>"],
                "artifacts": ["<files, commands, references>"],
                "recommended_next_actions": ["<what the caller should do next>"],
                "questions": ["<only if blocked or critically ambiguous>"],
            },
            "storage_guidance": {
                "persist_as_json": True,
                "store_raw_chain_of_thought": False,
                "store_long_lived_secrets": False,
                "intended_use": [
                    "agent liveness",
                    "task claims",
                    "request/response envelopes",
                    "short-lived summaries",
                ],
            },
        },
        indent=2,
        sort_keys=True,
    )


@MCP.tool()
async def register_agent(
    agent_id: str,
    role: str,
    ctx: Context[ServerSession, AppContext],
    owner_agent: str | None = None,
    capabilities: list[str] | None = None,
    metadata: dict[str, object] | None = None,
    ttl_seconds: int | None = None,
) -> dict[str, object]:
    """Register or refresh an agent presence record."""
    app = ctx.request_context.lifespan_context
    ttl = ttl_seconds or app.settings.agent_ttl_seconds
    now = _utc_now()
    payload = {
        "agent_id": agent_id,
        "role": role,
        "owner_agent": owner_agent,
        "capabilities": _normalize_list(capabilities),
        "metadata": _normalize_mapping(metadata),
        "status": "active",
        "registered_at": _isoformat(now),
        "last_seen_at": _isoformat(now),
        "expires_at": _future_iso(ttl),
    }
    await app.redis.set(_agent_key(app.settings, agent_id), _serialize(payload), ex=ttl)
    await app.redis.zadd(_active_agents_key(app.settings), {agent_id: now.timestamp() + ttl})
    return {"registered": True, "ttl_seconds": ttl, "agent": payload}


@MCP.tool()
async def heartbeat_agent(
    agent_id: str,
    ctx: Context[ServerSession, AppContext],
    status: str = "active",
    metadata: dict[str, object] | None = None,
    ttl_seconds: int | None = None,
) -> dict[str, object]:
    """Refresh agent liveness and optional metadata."""
    app = ctx.request_context.lifespan_context
    ttl = ttl_seconds or app.settings.agent_ttl_seconds
    now = _utc_now()
    payload = _deserialize(await app.redis.get(_agent_key(app.settings, agent_id))) or {
        "agent_id": agent_id,
        "role": "unknown",
        "owner_agent": None,
        "capabilities": [],
        "metadata": {},
        "registered_at": _isoformat(now),
    }
    payload["status"] = status
    payload["metadata"] = {**_normalize_mapping(payload.get("metadata")), **_normalize_mapping(metadata)}
    payload["last_seen_at"] = _isoformat(now)
    payload["expires_at"] = _future_iso(ttl)
    await app.redis.set(_agent_key(app.settings, agent_id), _serialize(payload), ex=ttl)
    await app.redis.zadd(_active_agents_key(app.settings), {agent_id: now.timestamp() + ttl})
    return {"heartbeat": True, "ttl_seconds": ttl, "agent": payload}


@MCP.tool()
async def get_active_agents(
    ctx: Context[ServerSession, AppContext],
    limit: int = 100,
) -> dict[str, object]:
    """List currently active agents with their latest liveness payloads."""
    app = ctx.request_context.lifespan_context
    await _prune_active_agents(app.redis, app.settings)
    agent_ids = await app.redis.zrevrange(_active_agents_key(app.settings), 0, max(limit - 1, 0))
    agents: list[dict[str, Any]] = []
    for agent_id in agent_ids:
        payload = _deserialize(await app.redis.get(_agent_key(app.settings, agent_id)))
        if payload is not None:
            agents.append(payload)
    return {"count": len(agents), "agents": agents}


@MCP.tool()
async def claim_task(
    task_id: str,
    agent_id: str,
    objective: str,
    ctx: Context[ServerSession, AppContext],
    task_type: str | None = None,
    repo_scope: list[str] | None = None,
    metadata: dict[str, object] | None = None,
    ttl_seconds: int | None = None,
) -> dict[str, object]:
    """Claim a task lock or refresh it if the same agent already owns it."""
    app = ctx.request_context.lifespan_context
    ttl = ttl_seconds or app.settings.task_ttl_seconds
    now = _utc_now()
    task = {
        "task_id": task_id,
        "agent_id": agent_id,
        "status": "claimed",
        "objective": objective,
        "task_type": task_type,
        "repo_scope": _normalize_list(repo_scope),
        "metadata": _normalize_mapping(metadata),
        "claimed_at": _isoformat(now),
        "updated_at": _isoformat(now),
        "expires_at": _future_iso(ttl),
    }
    task_key = _task_key(app.settings, task_id)
    serialized = _serialize(task)
    if await app.redis.set(task_key, serialized, ex=ttl, nx=True):
        return {"claimed": True, "task": task}

    existing = _deserialize(await app.redis.get(task_key))
    if existing and existing.get("agent_id") == agent_id:
        existing.update(
            {
                "objective": objective,
                "task_type": task_type,
                "repo_scope": _normalize_list(repo_scope),
                "metadata": _normalize_mapping(metadata),
                "updated_at": _isoformat(now),
                "expires_at": _future_iso(ttl),
            }
        )
        await app.redis.set(task_key, _serialize(existing), ex=ttl)
        return {"claimed": True, "refreshed": True, "task": existing}

    return {"claimed": False, "task": existing}


@MCP.tool()
async def read_task(
    task_id: str,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Read the current task claim or completion record."""
    app = ctx.request_context.lifespan_context
    task_key = _task_key(app.settings, task_id)
    payload = _deserialize(await app.redis.get(task_key))
    ttl_seconds = await app.redis.ttl(task_key)
    return {"found": payload is not None, "ttl_seconds": ttl_seconds, "task": payload}


@MCP.tool()
async def complete_task(
    task_id: str,
    agent_id: str,
    outcome: str,
    ctx: Context[ServerSession, AppContext],
    result_summary: str | None = None,
    metadata: dict[str, object] | None = None,
) -> dict[str, object]:
    """Mark a task as completed and retain its record for short-term inspection."""
    app = ctx.request_context.lifespan_context
    now = _utc_now()
    task_key = _task_key(app.settings, task_id)
    existing = _deserialize(await app.redis.get(task_key))
    if existing and existing.get("agent_id") not in {None, agent_id}:
        raise ValueError(f"Task {task_id} is owned by {existing['agent_id']}, not {agent_id}")

    task = existing or {
        "task_id": task_id,
        "agent_id": agent_id,
        "claimed_at": _isoformat(now),
        "objective": None,
        "task_type": None,
        "repo_scope": [],
        "metadata": {},
    }
    task.update(
        {
            "status": "completed",
            "outcome": outcome,
            "result_summary": result_summary,
            "metadata": {**_normalize_mapping(task.get("metadata")), **_normalize_mapping(metadata)},
            "completed_at": _isoformat(now),
            "updated_at": _isoformat(now),
        }
    )
    await app.redis.set(task_key, _serialize(task), ex=app.settings.completed_task_ttl_seconds)
    return {"completed": True, "task": task, "ttl_seconds": app.settings.completed_task_ttl_seconds}


@MCP.tool()
async def append_request(
    request_id: str,
    from_agent: str,
    to_agent: str,
    task_type: str,
    objective: str,
    expected_output: str,
    done_criteria: str,
    ctx: Context[ServerSession, AppContext],
    repo_scope: list[str] | None = None,
    context: dict[str, object] | None = None,
    constraints: list[str] | None = None,
    inputs: dict[str, object] | None = None,
) -> dict[str, object]:
    """Store a protocol REQUEST envelope as JSON."""
    app = ctx.request_context.lifespan_context
    payload = {
        "message_kind": "REQUEST",
        "request_id": request_id,
        "from_agent": from_agent,
        "to_agent": to_agent,
        "task_type": task_type,
        "objective": objective,
        "repo_scope": _normalize_list(repo_scope),
        "context": _normalize_mapping(context),
        "constraints": _normalize_list(constraints),
        "inputs": _normalize_mapping(inputs),
        "expected_output": expected_output,
        "done_criteria": done_criteria,
        "stored_at": _isoformat(_utc_now()),
    }
    await _store_message(app.redis, app.settings, payload)
    return {"stored": True, "message": payload}


@MCP.tool()
async def append_response(
    request_id: str,
    from_agent: str,
    status: str,
    summary: str,
    ctx: Context[ServerSession, AppContext],
    findings: list[str] | None = None,
    assumptions: list[str] | None = None,
    risks: list[str] | None = None,
    artifacts: list[str] | None = None,
    recommended_next_actions: list[str] | None = None,
    questions: list[str] | None = None,
) -> dict[str, object]:
    """Store a protocol RESPONSE envelope as JSON."""
    app = ctx.request_context.lifespan_context
    payload = {
        "message_kind": "RESPONSE",
        "request_id": request_id,
        "from_agent": from_agent,
        "status": status,
        "summary": summary,
        "findings": _normalize_list(findings),
        "assumptions": _normalize_list(assumptions),
        "risks": _normalize_list(risks),
        "artifacts": _normalize_list(artifacts),
        "recommended_next_actions": _normalize_list(recommended_next_actions),
        "questions": _normalize_list(questions),
        "stored_at": _isoformat(_utc_now()),
    }
    await _store_message(app.redis, app.settings, payload)
    return {"stored": True, "message": payload}


@MCP.tool()
async def read_messages(
    ctx: Context[ServerSession, AppContext],
    request_id: str | None = None,
    agent_id: str | None = None,
    limit: int = 20,
) -> dict[str, object]:
    """Read recent protocol messages globally or for a specific request thread."""
    app = ctx.request_context.lifespan_context
    key = _message_thread_key(app.settings, request_id) if request_id else _message_key(app.settings)
    raw_messages = await app.redis.lrange(key, 0, max((limit * 5) - 1, 0))
    messages: list[dict[str, Any]] = []
    for raw_message in raw_messages:
        payload = _deserialize(raw_message)
        if payload is None:
            continue
        if agent_id and agent_id not in {payload.get("from_agent"), payload.get("to_agent")}:
            continue
        messages.append(payload)
        if len(messages) >= limit:
            break
    return {"count": len(messages), "messages": messages}


@MCP.tool()
async def store_summary(
    scope: str,
    scope_id: str,
    author_agent: str,
    summary: str,
    ctx: Context[ServerSession, AppContext],
    metadata: dict[str, object] | None = None,
    ttl_seconds: int | None = None,
) -> dict[str, object]:
    """Store a short-lived structured summary for a workflow, task, or agent."""
    app = ctx.request_context.lifespan_context
    ttl = ttl_seconds or app.settings.summary_ttl_seconds
    payload = {
        "scope": scope,
        "scope_id": scope_id,
        "author_agent": author_agent,
        "summary": summary,
        "metadata": _normalize_mapping(metadata),
        "stored_at": _isoformat(_utc_now()),
        "expires_at": _future_iso(ttl),
    }
    await app.redis.set(_summary_key(app.settings, scope, scope_id), _serialize(payload), ex=ttl)
    return {"stored": True, "ttl_seconds": ttl, "summary": payload}


@MCP.tool()
async def read_summary(
    scope: str,
    scope_id: str,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Read a stored summary by scope and identifier."""
    app = ctx.request_context.lifespan_context
    key = _summary_key(app.settings, scope, scope_id)
    payload = _deserialize(await app.redis.get(key))
    ttl_seconds = await app.redis.ttl(key)
    return {"found": payload is not None, "ttl_seconds": ttl_seconds, "summary": payload}


@contextlib.asynccontextmanager
async def starlette_lifespan(_app: Starlette):
    async with MCP.session_manager.run():
        yield


APP = Starlette(
    routes=[Mount("/", app=MCP.streamable_http_app())],
    lifespan=starlette_lifespan,
)


def main() -> None:
    uvicorn.run(APP, host=SETTINGS.host, port=SETTINGS.port, log_level="info")
