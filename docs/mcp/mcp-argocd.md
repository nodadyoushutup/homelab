# mcp-argocd

Streamable HTTP MCP for **Argo CD** visibility and operations from [argoproj-labs/mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd), wrapped by **`applications/mcp-argocd/`**.

## URL and path

Publish the service behind TLS at **`https://mcp.argocd.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **3000** via **`applications/mcp-argocd/entrypoint.sh`** (`http --stateless`); Swarm publishes **18201** → **3000**.

## Usage

- Use for **application health**, sync status, and other tools the server exposes.
- Set **`MCP_READ_ONLY=true`** in **`env`** to disable mutating tools (create/update/delete/sync).
- Set **`ARGOCD_INSECURE_SKIP_VERIFY=true`** only when the Argo CD API uses a cert your task cannot trust (see **`applications/mcp-argocd/entrypoint.sh`**).

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_argocd`** at **`https://mcp.argocd.nodadyoushutup.com/mcp`**. No client API key — **`ARGOCD_*`** credentials live in Swarm **`env`** on **`.config/terraform/swarm/mcp-argocd/app.tfvars`**. Add the same block to **User** MCP settings or **`~/.cursor/mcp.json`** for all workspaces. After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

Add a server block in the relevant **`mcp.json`** when a graph should call Argo CD through this stack.

## Swarm

- Stack: **`terraform/swarm/mcp-argocd/app/`** — all site credentials in the **`env`** map on **`.config/terraform/swarm/mcp-argocd/app.tfvars`** (flat keys such as **`ARGOCD_BASE_URL`**, **`ARGOCD_API_TOKEN`**; no Vault **`secrets`** block or **`env_file_path`**). Keep tokens out of git.

## Related

- [mcp-kubernetes.md](mcp-kubernetes.md)
