# mcp-redis

`mcp-redis` is a repo-local native Streamable HTTP MCP server for Redis.

It is intended to give agents a structured way to use Redis without exposing a
raw shell-like interface. The server focuses on safe, common Redis workflows:

- ping and key inspection
- namespaced key listing
- string and JSON get/set
- counters and TTL updates
- hashes, lists, sets, and streams

The matching Swarm runtime lives in `terraform/swarm/mcp-redis/app`.
