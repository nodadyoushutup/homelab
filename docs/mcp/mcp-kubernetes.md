# mcp-kubernetes

Read-oriented **Kubernetes** MCP using a **kubeconfig** file mounted into the task at a path you configure (see **`terraform/swarm/mcp-kubernetes/app/main.tf`**).

## URL and path

Publish the service behind TLS at **`https://mcp.kubernetes.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8106**; Swarm publishes **18210** → **8106**.

## Usage

- Default Swarm args emphasize **`--read-only`**, **`--toolsets core,config`**, and **`--stateless`** (see **`terraform/swarm/mcp-kubernetes/app/main.tf`**).
- Use for **inspecting** resources, events, and config—not for unconstrained write unless you intentionally change args and accept the risk.

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_kubernetes`** at **`https://mcp.kubernetes.nodadyoushutup.com/mcp`**. No client API key — cluster credentials live in the kubeconfig baked from **`.config/terraform/swarm/mcp-kubernetes/kubeconfig`** (see Swarm). After deploy or kubeconfig edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

Add a server block in the relevant **`mcp.json`** when a graph should call Kubernetes through this stack.

## Swarm

- Stack: **`terraform/swarm/mcp-kubernetes/app/`** — set **`kubeconfig_path`** in **`.config/terraform/swarm/mcp-kubernetes/app.tfvars`** to the operator kubeconfig file on the Terraform host (same pattern as Grafana **`ini_path`**). Terraform bakes it into a Swarm config mounted at **`/etc/kubernetes/kubeconfig`** in the task.

## Related

- [mcp-argocd.md](mcp-argocd.md)
