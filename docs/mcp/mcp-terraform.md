# mcp-terraform

Streamable HTTP MCP wrapping **Terraform** CLI operations (plan/apply patterns and related toolsets), using the image reference in **`terraform/swarm/mcp-terraform/app/`**.

## URL and path

Expose port **`8080`** (internal default) through your ingress; clients use your published **`https://<your-host>/mcp`** (or **`--mcp-endpoint`** path if you change it in **`main.tf`**).

## Usage

- Prefer **plan-before-apply** discipline; confirm state backends and workspaces match intent before any apply.
- Narrow the tool surface with **`MCP_TERRAFORM_TOOLSETS`** (merged in **`terraform/swarm/mcp-terraform/app/main.tf`**) or the **`terraform_toolsets`** variable.

## Cursor / LangGraph

Add to **`.cursor/mcp.json`** or LangGraph **`mcp.json`** when IDE or graph agents should drive Terraform through MCP.

## Swarm

- Stack: **`terraform/swarm/mcp-terraform/app/`** — credentials and provider env via **`env_file_path`** / **`env`**.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
