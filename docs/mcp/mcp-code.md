# mcp-code

Aggregate **Streamable HTTP** MCP exposing workspace **filesystem**, **git**, and **ast-grep** tools against a single **`MCP_CODE_WORKSPACE_ROOT`**.

## URL and path

Configure your reverse proxy (or bind directly for lab use) so clients reach this service’s Streamable HTTP listener on path **`/mcp`** by default (**`MCP_HTTP_PATH`** in **`terraform/swarm/mcp-code/app/main.tf`**).

For local development, Compose or a manual **`docker run`** often publishes a host port; point **`.cursor/mcp.json`** or other clients at **`http://127.0.0.1:<published-port>/mcp`** (or HTTPS if you terminate TLS locally).

## Usage

- One running process equals **one Git working tree**. Parallel agents that must not share a checkout need **separate** endpoints or services, each with its own **`MCP_CODE_WORKSPACE_ROOT`** (typically **Git worktrees**). See [mcp-code-worktrees-and-multi-agent.md](../workflows/mcp-code-worktrees-and-multi-agent.md).

## LangGraph

The **Code** and **Tech Lead** specialists load **mcp-code** via **`applications/langgraph/framework/code_mcp_servers.json`** and **`code_tech_lead_mcp_servers.json`**, with optional override **`HOMELAB_MCP_CODE_URL`**. Kubernetes LangGraph can inject the default URL in **`kubernetes/langgraph/deployment.yaml`**.

## Deploy / build

- Application and image: **`applications/mcp-code/README.md`**
- Swarm Terraform: **`terraform/swarm/mcp-code/app/`**

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
