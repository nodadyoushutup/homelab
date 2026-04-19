## mcp-filesystem

`mcp-filesystem` is a repo-local HTTP wrapper around the official
`@modelcontextprotocol/server-filesystem` server.

It is designed to be:

- nothing more than the upstream filesystem MCP plus a stable HTTP transport
- rooted natively at the shared `/mnt/eapp/code` tree inside Kubernetes
- simple to publish to Harbor and expose through ingress at one fixed hostname

The upstream server is started with `/mnt/eapp/code` as its allowed workspace
root, so clients should use paths within that tree, such as
`/mnt/eapp/code/homelab` or `homelab/...` depending on the client tool.

The matching Kubernetes runtime lives in `kubernetes/mcp-filesystem/`.

The deployed ingress endpoint is:

- `https://mcp.filesystem.nodadyoushutup.com/mcp/`
