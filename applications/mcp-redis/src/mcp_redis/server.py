from __future__ import annotations

import contextlib
import json
import os
from dataclasses import dataclass
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


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(slots=True)
class Settings:
    host: str
    port: int
    redis_url: str
    key_prefix: str
    allowed_hosts: list[str]
    allowed_origins: list[str]
    max_scan_count: int
    default_expire_seconds: int
    allow_destructive_operations: bool


@dataclass(slots=True)
class AppContext:
    redis: redis.Redis
    settings: Settings


def load_settings() -> Settings:
    redis_url = os.getenv("MCP_REDIS_URL", "").strip()
    if not redis_url:
        raise ValueError("MCP_REDIS_URL is required")

    default_allowed_hosts = [
        "127.0.0.1",
        "127.0.0.1:*",
        "localhost",
        "localhost:*",
        "[::1]",
        "[::1]:*",
        "swarm-cp-0.local",
        "swarm-cp-0.local:*",
        "mcp.redis.nodadyoushutup.com",
        "mcp.redis.nodadyoushutup.com:*",
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
        "https://mcp.redis.nodadyoushutup.com",
    ]

    allowed_hosts = [
        value.strip()
        for value in os.getenv("MCP_REDIS_ALLOWED_HOSTS", ",".join(default_allowed_hosts)).split(",")
        if value.strip()
    ]
    allowed_origins = [
        value.strip()
        for value in os.getenv("MCP_REDIS_ALLOWED_ORIGINS", ",".join(default_allowed_origins)).split(",")
        if value.strip()
    ]

    return Settings(
        host=os.getenv("MCP_REDIS_HOST", "0.0.0.0"),
        port=_env_int("MCP_REDIS_LISTEN_PORT", 8101),
        redis_url=redis_url,
        key_prefix=os.getenv("MCP_REDIS_KEY_PREFIX", "shared").strip(),
        allowed_hosts=allowed_hosts,
        allowed_origins=allowed_origins,
        max_scan_count=_env_int("MCP_REDIS_MAX_SCAN_COUNT", 200),
        default_expire_seconds=_env_int("MCP_REDIS_DEFAULT_EXPIRE_SECONDS", 86400),
        allow_destructive_operations=_env_bool("MCP_REDIS_ALLOW_DESTRUCTIVE_OPERATIONS", True),
    )


SETTINGS = load_settings()


def _serialize(payload: dict[str, object]) -> str:
    return json.dumps(payload, indent=2, sort_keys=True)


def _encode_redis_value(value: Any) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _decode_maybe_json(value: str | None) -> Any:
    if value is None:
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value


def _apply_prefix(settings: Settings, key: str) -> str:
    clean_key = key.strip()
    if not clean_key:
        raise ValueError("key must not be empty")
    if not settings.key_prefix:
        return clean_key
    return f"{settings.key_prefix}:{clean_key}"


def _strip_prefix(settings: Settings, key: str) -> str:
    if settings.key_prefix and key.startswith(f"{settings.key_prefix}:"):
        return key[len(settings.key_prefix) + 1 :]
    return key


def _pattern_with_prefix(settings: Settings, pattern: str) -> str:
    clean_pattern = pattern.strip() or "*"
    if not settings.key_prefix:
        return clean_pattern
    return f"{settings.key_prefix}:{clean_pattern}"


def _normalize_expire(settings: Settings, expire_seconds: int | None) -> int | None:
    if expire_seconds is None:
        return None
    if expire_seconds <= 0:
        raise ValueError("expire_seconds must be a positive integer when provided")
    return expire_seconds


async def _key_length(client: redis.Redis, key: str, redis_type: str) -> int | None:
    if redis_type == "string":
        return await client.strlen(key)
    if redis_type == "hash":
        return await client.hlen(key)
    if redis_type == "list":
        return await client.llen(key)
    if redis_type == "set":
        return await client.scard(key)
    if redis_type == "stream":
        return await client.xlen(key)
    if redis_type == "zset":
        return await client.zcard(key)
    return None


async def _require_destructive_allowed(settings: Settings) -> None:
    if not settings.allow_destructive_operations:
        raise ValueError("Destructive Redis operations are disabled for this deployment")


@contextlib.asynccontextmanager
async def app_lifespan(_server: FastMCP) -> AppContext:
    client = redis.from_url(SETTINGS.redis_url, decode_responses=True)
    await client.ping()
    try:
        yield AppContext(redis=client, settings=SETTINGS)
    finally:
        await client.aclose()


MCP = FastMCP(
    "Redis",
    stateless_http=True,
    json_response=True,
    lifespan=app_lifespan,
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=SETTINGS.allowed_hosts,
        allowed_origins=SETTINGS.allowed_origins,
    ),
)


@MCP.resource("redis://usage")
def redis_usage() -> str:
    """Return the Redis MCP server contract and deployment guidance."""
    return _serialize(
        {
            "description": "Structured Redis MCP server for shared agent and platform workflows.",
            "key_prefix": SETTINGS.key_prefix,
            "tool_groups": {
                "core": ["ping", "get_key_info", "list_keys", "delete_keys", "expire_key"],
                "values": ["get_text", "set_text", "get_json", "set_json", "increment_key"],
                "hashes": ["get_hash", "set_hash_fields"],
                "lists": ["push_list", "read_list"],
                "sets": ["add_set_members", "read_set_members"],
                "streams": ["append_stream", "read_stream"],
            },
            "guidance": {
                "logical_keys": "All tool inputs use logical keys; the deployment key prefix is applied automatically.",
                "json_behavior": "JSON tools serialize and parse Redis values for you.",
                "hash_list_set_behavior": "Non-string values are JSON-encoded on write and decoded on read when possible.",
                "destructive_operations_enabled": SETTINGS.allow_destructive_operations,
            },
        }
    )


@MCP.tool()
async def ping(ctx: Context[ServerSession, AppContext]) -> dict[str, object]:
    """Ping the Redis backend and return basic deployment settings."""
    app = ctx.request_context.lifespan_context
    pong = await app.redis.ping()
    return {
        "ok": bool(pong),
        "key_prefix": app.settings.key_prefix,
        "default_expire_seconds": app.settings.default_expire_seconds,
        "max_scan_count": app.settings.max_scan_count,
        "destructive_operations_enabled": app.settings.allow_destructive_operations,
    }


@MCP.tool()
async def get_key_info(
    key: str,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Return type, TTL, and basic shape information for one key."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    exists = bool(await app.redis.exists(redis_key))
    if not exists:
        return {"found": False, "logical_key": key, "redis_key": redis_key}

    redis_type = await app.redis.type(redis_key)
    ttl_seconds = await app.redis.ttl(redis_key)
    length = await _key_length(app.redis, redis_key, redis_type)
    return {
        "found": True,
        "logical_key": key,
        "redis_key": redis_key,
        "redis_type": redis_type,
        "ttl_seconds": ttl_seconds,
        "length": length,
    }


@MCP.tool()
async def list_keys(
    ctx: Context[ServerSession, AppContext],
    pattern: str = "*",
    cursor: int = 0,
    count: int = 100,
) -> dict[str, object]:
    """List keys with SCAN semantics inside the configured namespace prefix."""
    app = ctx.request_context.lifespan_context
    if cursor < 0:
        raise ValueError("cursor must be zero or greater")
    if count <= 0:
        raise ValueError("count must be a positive integer")
    safe_count = min(count, app.settings.max_scan_count)
    next_cursor, keys = await app.redis.scan(
        cursor=cursor,
        match=_pattern_with_prefix(app.settings, pattern),
        count=safe_count,
    )
    logical_keys = [_strip_prefix(app.settings, item) for item in keys]
    return {
        "cursor": next_cursor,
        "count": len(logical_keys),
        "keys": logical_keys,
        "match_pattern": pattern,
        "scan_count": safe_count,
    }


@MCP.tool()
async def get_text(
    key: str,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Read a plain Redis string value."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    value = await app.redis.get(redis_key)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "found": value is not None,
        "logical_key": key,
        "redis_key": redis_key,
        "value": value,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def set_text(
    key: str,
    value: str,
    ctx: Context[ServerSession, AppContext],
    expire_seconds: int | None = None,
    only_if_missing: bool = False,
    only_if_exists: bool = False,
) -> dict[str, object]:
    """Write a Redis string value with optional TTL and existence guards."""
    app = ctx.request_context.lifespan_context
    if only_if_missing and only_if_exists:
        raise ValueError("only_if_missing and only_if_exists cannot both be true")
    redis_key = _apply_prefix(app.settings, key)
    expiry = _normalize_expire(app.settings, expire_seconds)
    stored = await app.redis.set(redis_key, value, ex=expiry, nx=only_if_missing, xx=only_if_exists)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "stored": bool(stored),
        "logical_key": key,
        "redis_key": redis_key,
        "value": value,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def get_json(
    key: str,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Read and parse a JSON value stored in Redis."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    raw_value = await app.redis.get(redis_key)
    ttl_seconds = await app.redis.ttl(redis_key)
    parsed_value = _decode_maybe_json(raw_value)
    return {
        "found": raw_value is not None,
        "logical_key": key,
        "redis_key": redis_key,
        "value": parsed_value,
        "raw_value": raw_value,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def set_json(
    key: str,
    value: Any,
    ctx: Context[ServerSession, AppContext],
    expire_seconds: int | None = None,
    only_if_missing: bool = False,
    only_if_exists: bool = False,
) -> dict[str, object]:
    """Serialize and store a JSON value in Redis."""
    app = ctx.request_context.lifespan_context
    if only_if_missing and only_if_exists:
        raise ValueError("only_if_missing and only_if_exists cannot both be true")
    redis_key = _apply_prefix(app.settings, key)
    expiry = _normalize_expire(app.settings, expire_seconds)
    serialized = json.dumps(value, separators=(",", ":"), sort_keys=True)
    stored = await app.redis.set(redis_key, serialized, ex=expiry, nx=only_if_missing, xx=only_if_exists)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "stored": bool(stored),
        "logical_key": key,
        "redis_key": redis_key,
        "value": value,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def increment_key(
    key: str,
    ctx: Context[ServerSession, AppContext],
    amount: int = 1,
    expire_seconds: int | None = None,
) -> dict[str, object]:
    """Increment an integer counter and optionally refresh its TTL."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    value = await app.redis.incrby(redis_key, amount)
    expiry = _normalize_expire(app.settings, expire_seconds)
    if expiry is not None:
        await app.redis.expire(redis_key, expiry)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "value": value,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def delete_keys(
    keys: list[str],
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Delete one or more Redis keys."""
    app = ctx.request_context.lifespan_context
    await _require_destructive_allowed(app.settings)
    if not keys:
        raise ValueError("keys must contain at least one item")
    redis_keys = [_apply_prefix(app.settings, key) for key in keys]
    deleted = await app.redis.delete(*redis_keys)
    return {
        "deleted": deleted,
        "logical_keys": keys,
        "redis_keys": redis_keys,
    }


@MCP.tool()
async def expire_key(
    key: str,
    expire_seconds: int,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Set or refresh the TTL on an existing Redis key."""
    app = ctx.request_context.lifespan_context
    expiry = _normalize_expire(app.settings, expire_seconds)
    redis_key = _apply_prefix(app.settings, key)
    updated = await app.redis.expire(redis_key, expiry)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "updated": bool(updated),
        "logical_key": key,
        "redis_key": redis_key,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def set_hash_fields(
    key: str,
    mapping: dict[str, Any],
    ctx: Context[ServerSession, AppContext],
    expire_seconds: int | None = None,
) -> dict[str, object]:
    """Write one or more hash fields with JSON-aware value encoding."""
    app = ctx.request_context.lifespan_context
    if not mapping:
        raise ValueError("mapping must not be empty")
    redis_key = _apply_prefix(app.settings, key)
    encoded_mapping = {field: _encode_redis_value(value) for field, value in mapping.items()}
    fields_written = await app.redis.hset(redis_key, mapping=encoded_mapping)
    expiry = _normalize_expire(app.settings, expire_seconds)
    if expiry is not None:
        await app.redis.expire(redis_key, expiry)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "fields_written": fields_written,
        "logical_key": key,
        "redis_key": redis_key,
        "mapping": {field: _decode_maybe_json(value) for field, value in encoded_mapping.items()},
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def get_hash(
    key: str,
    ctx: Context[ServerSession, AppContext],
    fields: list[str] | None = None,
) -> dict[str, object]:
    """Read a Redis hash fully or by a subset of fields."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    if fields:
        raw_values = await app.redis.hmget(redis_key, fields)
        value = {field: _decode_maybe_json(raw) for field, raw in zip(fields, raw_values, strict=True)}
    else:
        raw_mapping = await app.redis.hgetall(redis_key)
        value = {field: _decode_maybe_json(raw) for field, raw in raw_mapping.items()}
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "found": bool(value),
        "logical_key": key,
        "redis_key": redis_key,
        "value": value,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def push_list(
    key: str,
    values: list[Any],
    ctx: Context[ServerSession, AppContext],
    direction: str = "right",
    expire_seconds: int | None = None,
) -> dict[str, object]:
    """Push one or more values onto a Redis list."""
    app = ctx.request_context.lifespan_context
    if not values:
        raise ValueError("values must contain at least one item")
    normalized_direction = direction.strip().lower()
    if normalized_direction not in {"left", "right"}:
        raise ValueError("direction must be 'left' or 'right'")
    redis_key = _apply_prefix(app.settings, key)
    encoded_values = [_encode_redis_value(value) for value in values]
    if normalized_direction == "left":
        new_length = await app.redis.lpush(redis_key, *encoded_values)
    else:
        new_length = await app.redis.rpush(redis_key, *encoded_values)
    expiry = _normalize_expire(app.settings, expire_seconds)
    if expiry is not None:
        await app.redis.expire(redis_key, expiry)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "direction": normalized_direction,
        "new_length": new_length,
        "values": [_decode_maybe_json(item) for item in encoded_values],
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def read_list(
    key: str,
    ctx: Context[ServerSession, AppContext],
    start: int = 0,
    stop: int = -1,
) -> dict[str, object]:
    """Read values from a Redis list."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    raw_values = await app.redis.lrange(redis_key, start, stop)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "values": [_decode_maybe_json(item) for item in raw_values],
        "start": start,
        "stop": stop,
        "count": len(raw_values),
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def add_set_members(
    key: str,
    members: list[Any],
    ctx: Context[ServerSession, AppContext],
    expire_seconds: int | None = None,
) -> dict[str, object]:
    """Add one or more members to a Redis set."""
    app = ctx.request_context.lifespan_context
    if not members:
        raise ValueError("members must contain at least one item")
    redis_key = _apply_prefix(app.settings, key)
    encoded_members = [_encode_redis_value(member) for member in members]
    added = await app.redis.sadd(redis_key, *encoded_members)
    expiry = _normalize_expire(app.settings, expire_seconds)
    if expiry is not None:
        await app.redis.expire(redis_key, expiry)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "added": added,
        "members": [_decode_maybe_json(member) for member in encoded_members],
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def read_set_members(
    key: str,
    ctx: Context[ServerSession, AppContext],
) -> dict[str, object]:
    """Read all members from a Redis set."""
    app = ctx.request_context.lifespan_context
    redis_key = _apply_prefix(app.settings, key)
    raw_members = sorted(await app.redis.smembers(redis_key))
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "members": [_decode_maybe_json(member) for member in raw_members],
        "count": len(raw_members),
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def append_stream(
    key: str,
    fields: dict[str, Any],
    ctx: Context[ServerSession, AppContext],
    maxlen: int | None = None,
    approximate: bool = True,
) -> dict[str, object]:
    """Append one entry to a Redis stream."""
    app = ctx.request_context.lifespan_context
    if not fields:
        raise ValueError("fields must not be empty")
    redis_key = _apply_prefix(app.settings, key)
    encoded_fields = {field: _encode_redis_value(value) for field, value in fields.items()}
    entry_id = await app.redis.xadd(redis_key, encoded_fields, maxlen=maxlen, approximate=approximate)
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "entry_id": entry_id,
        "fields": {field: _decode_maybe_json(value) for field, value in encoded_fields.items()},
        "maxlen": maxlen,
        "approximate": approximate,
        "ttl_seconds": ttl_seconds,
    }


@MCP.tool()
async def read_stream(
    key: str,
    ctx: Context[ServerSession, AppContext],
    after_id: str = "0-0",
    count: int = 100,
) -> dict[str, object]:
    """Read entries from a Redis stream after a given entry id."""
    app = ctx.request_context.lifespan_context
    if count <= 0:
        raise ValueError("count must be a positive integer")
    safe_count = min(count, app.settings.max_scan_count)
    redis_key = _apply_prefix(app.settings, key)
    raw_entries = await app.redis.xrange(redis_key, min=after_id, max="+", count=safe_count)
    entries = []
    for entry_id, fields in raw_entries:
        entries.append(
            {
                "entry_id": entry_id,
                "fields": {field: _decode_maybe_json(value) for field, value in fields.items()},
            }
        )
    ttl_seconds = await app.redis.ttl(redis_key)
    return {
        "logical_key": key,
        "redis_key": redis_key,
        "after_id": after_id,
        "count": len(entries),
        "entries": entries,
        "ttl_seconds": ttl_seconds,
    }


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
