"""Streamable HTTP front door that requires x-api-key before mcp-proxy."""

from __future__ import annotations

import hmac
import os
from collections.abc import AsyncIterator, Iterable

import httpx
import uvicorn
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import Response, StreamingResponse
from starlette.routing import Route

API_KEY_ENV = "MCP_AGENTMEMORY_API_KEY"
API_KEY_HEADER = "x-api-key"
UPSTREAM_ENV = "MCP_AGENTMEMORY_UPSTREAM"
DEFAULT_UPSTREAM = "http://127.0.0.1:18087"
LISTEN_HOST_ENV = "MCP_AGENTMEMORY_HOST"
LISTEN_PORT_ENV = "MCP_AGENTMEMORY_LISTEN_PORT"
HOP_BY_HOP = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        "content-length",
        "host",
    }
)


def _api_key() -> str:
    return (os.getenv(API_KEY_ENV) or "").strip()


def _upstream_base() -> str:
    return (os.getenv(UPSTREAM_ENV) or DEFAULT_UPSTREAM).rstrip("/")


def _filter_headers(headers: Iterable[tuple[str, str]]) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, value in headers:
        if key.lower() in HOP_BY_HOP:
            continue
        out[key] = value
    return out


async def proxy(request: Request) -> Response:
    """Authenticate with x-api-key, then stream-proxy to local mcp-proxy."""
    expected = _api_key()
    if not expected:
        return Response(
            content=b'{"error":"Unauthorized","message":"MCP_AGENTMEMORY_API_KEY is not configured."}',
            status_code=503,
            media_type="application/json",
        )

    provided = (request.headers.get(API_KEY_HEADER) or "").strip()
    if not hmac.compare_digest(provided, expected):
        return Response(
            content=b'{"error":"Unauthorized","message":"Invalid API key."}',
            status_code=401,
            media_type="application/json",
        )

    upstream = f"{_upstream_base()}{request.url.path}"
    if request.url.query:
        upstream = f"{upstream}?{request.url.query}"

    body = await request.body()
    headers = _filter_headers(request.headers.items())
    client = httpx.AsyncClient(timeout=None)
    upstream_req = client.build_request(
        request.method,
        upstream,
        content=body,
        headers=headers,
    )
    upstream_resp = await client.send(upstream_req, stream=True)
    response_headers = _filter_headers(upstream_resp.headers.items())

    async def body_iter() -> AsyncIterator[bytes]:
        try:
            async for chunk in upstream_resp.aiter_raw():
                yield chunk
        finally:
            await upstream_resp.aclose()
            await client.aclose()

    return StreamingResponse(
        content=body_iter(),
        status_code=upstream_resp.status_code,
        headers=response_headers,
        media_type=upstream_resp.headers.get("content-type"),
    )


app = Starlette(
    routes=[
        Route(
            "/{path:path}",
            endpoint=proxy,
            methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
        ),
        Route(
            "/",
            endpoint=proxy,
            methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
        ),
    ]
)


def main() -> None:
    """Run the auth gateway."""
    host = (os.getenv(LISTEN_HOST_ENV) or "0.0.0.0").strip()
    port = int((os.getenv(LISTEN_PORT_ENV) or "8087").strip())
    uvicorn.run(app, host=host, port=port, log_level="info")


if __name__ == "__main__":
    main()
