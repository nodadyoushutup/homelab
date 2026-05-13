# mcp-fortigate

Streamable HTTP MCP for **FortiGate** REST API operations (policies, objects, diagnostics as implemented by the server image).

## URL and path

Publish behind HTTPS at a hostname on your management network; clients connect to your Streamable MCP URL (**`MCP_HTTP_PATH`** defaults to **`/mcp`** in **`terraform/swarm/mcp-fortigate/app/main.tf`**).

## Usage

- Prefer **read-heavy** checks and small, well-scoped writes; confirm **VDOM** and appliance address before mutating policy.
- Swarm defaults include **`FORTIGATE_HOST`**, **`FORTIGATE_VDOM`**, and **`FORTIGATE_VERIFY_SSL`** (see **`terraform/swarm/mcp-fortigate/app/main.tf`**).

## Cursor / LangGraph

Enable in **`.cursor/mcp.json`** or LangGraph **`mcp.json`** only on trusted machines; this MCP can change network security posture.

## Swarm

- Stack: **`terraform/swarm/mcp-fortigate/app/`** — API user, secret, and host overrides via **`env_file_path`** or **`env`**, not in git.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
