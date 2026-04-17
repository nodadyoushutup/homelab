# MCP Agent Protocol

Redis-backed MCP server that stores agent protocol JSON envelopes, liveness,
task claims, and short-lived summaries for Langflow-style supervisor and
subagent orchestration.

The server intentionally stores structured request/response objects and short
summaries, not raw chain-of-thought.

The HTTP transport also keeps an explicit host/origin allowlist so the deployed
endpoint can be reached by the Swarm node hostname and the intended MCP domain
without disabling DNS rebinding protection.
