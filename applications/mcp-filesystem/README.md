## mcp-filesystem

`mcp-filesystem` is a repo-local HTTP wrapper around the official
`@modelcontextprotocol/server-filesystem` server.

It is designed to be:

- nothing more than the upstream filesystem MCP plus a stable HTTP transport
- rooted natively at the homelab workspace `/mnt/eapp/code/homelab` inside Swarm
- simple to publish and expose through Nginx Proxy Manager at one fixed hostname

The upstream server is started with `/mnt/eapp/code/homelab` as its allowed
workspace root, so clients should treat that exact path as the source of truth
for "our files" and use `.` or repo-relative paths within that workspace.

The deployed ingress endpoint is:

- `https://mcp.filesystem.nodadyoushutup.com/mcp/`
