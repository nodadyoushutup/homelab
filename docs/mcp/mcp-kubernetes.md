# mcp-kubernetes

Read-oriented **Kubernetes** MCP using a **kubeconfig** file mounted into the task at a path you configure (see **`terraform/swarm/mcp-kubernetes/app/main.tf`**).

## URL and path

Publish the service’s MCP HTTP port behind HTTPS at a hostname you control; clients connect to the resulting Streamable MCP base URL (upstream **`/mcp`** per your image args).

## Usage

- Default Swarm args emphasize **`--read-only`**, **`--toolsets core,config`**, and **`--stateless`** (see **`terraform/swarm/mcp-kubernetes/app/main.tf`**).
- Use for **inspecting** resources, events, and config—not for unconstrained write unless you intentionally change args and accept the risk.

## Cursor / LangGraph

Enable per client by adding your URL to **`.cursor/mcp.json`** or LangGraph **`mcp.json`** when needed.

## Swarm

- Stack: **`terraform/swarm/mcp-kubernetes/app/`** — place **`kubeconfig`** on the volume mounted at the path expected by **`--kubeconfig`**.

## Related

- [mcp-argocd.md](mcp-argocd.md)
