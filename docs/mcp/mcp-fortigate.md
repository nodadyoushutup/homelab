# mcp-fortigate

Streamable HTTP MCP for **FortiGate** REST API operations (policies, objects, diagnostics as implemented by the server image), built from **`applications/mcp-fortigate/`** ([ftg_mcp](https://github.com/juststank/ftg_mcp)).

## URL and path

Publish the service behind TLS at **`https://mcp.fortigate.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8814** via **`applications/mcp-fortigate/entrypoint.sh`**; Swarm publishes **18205** → **8814**.

## Usage

- Prefer **read-heavy** checks and small, well-scoped writes; confirm **VDOM** and appliance address before mutating policy.
- Set **`FORTIGATE_HOST`** and either **`FORTIGATE_API_TOKEN`** or **`FORTIGATE_USERNAME`** / **`FORTIGATE_PASSWORD`** in Swarm **`env`** (see **`applications/mcp-fortigate/entrypoint.sh`**).

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_fortigate`** at **`https://mcp.fortigate.nodadyoushutup.com/mcp`** when enabled on trusted machines. No client API key — FortiGate credentials live in Swarm **`env`** on **`.config/terraform/swarm/mcp-fortigate/app.tfvars`**. After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

Add a server block in the relevant **`mcp.json`** when a graph should call FortiGate through this stack.

## Swarm

- Stack: **`terraform/swarm/mcp-fortigate/app/`** — all site credentials and device settings in the **`env`** map on **`.config/terraform/swarm/mcp-fortigate/app.tfvars`** (flat keys such as **`FORTIGATE_*`**, **`MCP_HTTP_PATH`**; no **`env_file_path`**). Keep tokens out of git.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
- Network appliance config (non-MCP): **`terraform/swarm/fortigate/config/`**
