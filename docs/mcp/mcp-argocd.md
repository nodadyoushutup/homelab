# mcp-argocd

HTTP MCP for **Argo CD** visibility and operations from [argoproj-labs/mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd).

## URL and path

Front the Swarm-published port with your reverse proxy and TLS. Clients use your **`https://<your-host>/mcp`** (or the path you configure that forwards to the container’s MCP route).

## Usage

- Use for **application health**, sync status, and other tools the server exposes.
- The container entrypoint may honor **`ARGOCD_INSECURE_SKIP_VERIFY`** for TLS to the Argo CD API when set in the service env (see **`terraform/swarm/mcp-argocd/app/main.tf`**).

## Cursor / LangGraph

Add an MCP server block in **`.cursor/mcp.json`** or LangGraph **`mcp.json`** when agents should use this stack.

## Secrets and Swarm

- Swarm: **`terraform/swarm/mcp-argocd/app/`** — Argo CD base URL, auth token, and related env belong in **`env_file_path`** or **`env`** (never commit live tokens).

## Related

- [mcp-kubernetes.md](mcp-kubernetes.md)
