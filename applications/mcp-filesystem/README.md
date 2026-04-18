## mcp-filesystem

`mcp-filesystem` is a repo-local native Streamable HTTP MCP server for
filesystem operations over the shared `/mnt/eapp/code` NFS tree.

It is designed to be:

- workspace-scoped by request headers instead of one hard-coded repo root
- policy-aware so read-only clients never see write tools in `tools/list`
- Kubernetes-friendly so the same HTTP endpoint can be routed through ingress

Supported request scoping headers:

- `x-workspace-root`: absolute workspace path inside the mounted code tree
- `x-workspace-name`: logical workspace key resolved from the configured map
- `x-mcp-filesystem-access`: `read-only` or `read-write`

The matching Kubernetes runtime lives in `kubernetes/mcp-filesystem/`.

The deployed ingress endpoint is:

- `https://mcp.filesystem.nodadyoushutup.com/mcp/`
