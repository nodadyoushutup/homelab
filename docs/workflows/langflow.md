# Langflow Workflow

This document describes how to operate and evolve the Langflow deployment in
this repo. Use [docs/rules/langflow.md](./../rules/langflow.md) for the
steady-state rules and [docs/workflows/kubernetes.md](./kubernetes.md) for the
shared Kubernetes delivery flow.

## Scope

Use this workflow for:

- Kubernetes deployment changes under `kubernetes/langflow/`
- Argo CD wiring changes for the Langflow app
- flow definition changes in the live Langflow instance
- custom Langflow component changes
- Langflow project MCP endpoint changes used by local tooling

## Current Deployment Model

The current Langflow deployment is a Kubernetes app with:

- a frontend service exposed at `langflow.nodadyoushutup.com`
- a backend service running Langflow on port `7860`
- an internal PostgreSQL database at `langflow-postgres`
- `LANGFLOW_AUTO_LOGIN=True`
- `LANGFLOW_UPDATE_STARTER_PROJECTS=false`
- `LANGFLOW_API_KEY_SOURCE=env`

Current repo evidence:

- `kubernetes/langflow/Chart.yaml`
- `kubernetes/langflow/values.yaml`
- `kubernetes/langflow/templates/*`
- `kubernetes/argocd-management/langflow-{project,app}.yaml`

Current limitation:

- the deployment does not currently set `LANGFLOW_LOAD_FLOWS_PATH` or
  `LANGFLOW_COMPONENTS_PATH`
- repeatable flow definitions are therefore not yet repo-managed by default
- live flows currently persist in the Langflow PostgreSQL database

## Preferred Repo-Managed Model

When making Langflow durable and reproducible, prefer this model:

1. export flows as Langflow JSON files
2. store custom components as Python files in a repo-managed components path
3. mount or bake those directories into the Langflow container
4. set:
   - `LANGFLOW_LOAD_FLOWS_PATH=<flows-dir>`
   - `LANGFLOW_COMPONENTS_PATH=<components-dir>`
5. keep secrets out of exported flow JSON by using variables or external secret
   sources

This is the closest supported IaC-style workflow Langflow currently offers in
practice: JSON flows plus Python components plus deployment env vars.

## Standard Flow

When a task changes Langflow:

1. decide whether the task changes:
   - deployment infrastructure
   - flow definitions
   - custom components
   - client endpoint wiring
2. read `kubernetes/langflow/values.yaml` and this workflow before editing
3. if the change is deployment-related, update the chart wrapper and Argo CD
   app definition as needed
4. if the change is flow-related, decide whether the change should stay UI-only
   temporarily or be captured as repo-managed JSON
5. if the change is component-related, implement it as repo-managed Python
   rather than in-editor code when the behavior is durable or reusable
6. if the change affects the project MCP endpoint, update the matching client
   config intentionally
7. if the change affects Langflow's API authentication for automation, update
   the backing Vault payload, `ExternalSecret`, and deployment env wiring
   together
8. if the change affects Langflow's external MCP server registry, sync the
   repo-managed `mcp_*` server set from `.codex/config.toml` into Langflow
9. validate the live Langflow deployment after the change
10. update docs if the stable pattern changed

## Deployment Change Flow

Use this when changing `kubernetes/langflow/` or Argo CD wiring:

1. update the Helm wrapper files under `kubernetes/langflow/`
2. update `kubernetes/argocd-management/langflow-app.yaml` or
   `langflow-project.yaml` if the app/project wiring changes
3. commit and push the GitOps source-of-truth changes
4. verify Argo CD sync and health
5. verify:
   - `langflow-frontend`
   - `langflow`
   - `langflow-postgres`
   - ingress reachability at `langflow.nodadyoushutup.com`

## Flow Change Flow

Use this when changing an agent, component graph, prompt, tool metadata, or
project configuration inside Langflow:

1. identify the target flow and project
2. make the live edit through the Langflow UI or API
3. validate the flow behavior in the Playground or through the API
4. if the change should be durable, export the flow JSON and capture it in
   repo-managed assets
5. if repo-managed flow loading is enabled, re-import or load the captured JSON
   through the supported startup/API path

Do not rely on memory or screenshots as the only record of a stable flow.

## Custom Component Flow

Use this when the task needs reusable Langflow behavior implemented as Python:

1. create a category-based component directory
2. add the Python component file and `__init__.py`
3. mount or bake that directory into the Langflow runtime
4. set `LANGFLOW_COMPONENTS_PATH` to the mounted directory
5. restart or redeploy Langflow
6. confirm the component appears in the editor and executes correctly

If a curated component index is also needed, configure
`LANGFLOW_COMPONENTS_INDEX_PATH`, but do not confuse that with loading Python
modules from disk.

## External MCP Server Registry Flow

Use this when Langflow should expose the repo-managed external MCP servers in
Settings > MCP Servers:

1. confirm the desired external `mcp_*` server URLs in `.codex/config.toml`
2. run `python3 scripts/misc/sync_langflow_mcp_servers.py --apply`
3. verify the expected servers appear in Langflow's MCP server registry
4. leave Langflow-only registry entries in place unless the task explicitly
   calls for cleanup

## Repo Adoption Flow

When we choose to make Langflow repo-managed instead of DB-only:

1. create a repo path for exported flow JSON files
2. create a repo path for custom components if needed
3. update the Langflow deployment to mount those paths
4. set `LANGFLOW_LOAD_FLOWS_PATH` and `LANGFLOW_COMPONENTS_PATH`
5. export and commit the current live flows that should survive redeploys
6. redeploy Langflow
7. verify the expected flows and components load on startup

## Validation

After any Langflow change, validate the layer you changed:

1. Kubernetes layer:
   - `kubectl get pods -n langflow`
   - `kubectl get svc,ingress -n langflow`
2. application layer:
   - open `https://langflow.nodadyoushutup.com`
   - confirm the target flow loads
3. behavior layer:
   - run the changed flow in Playground or via API
   - if the flow exposes MCP, test the expected endpoint
4. persistence layer:
   - if the change was meant to be durable, confirm the exported JSON or
     component files were captured in repo-managed artifacts

## Change Boundaries

- Do not assume Langflow’s PostgreSQL state is sufficient as long-term source
  control for important flows.
- Do not add filesystem-mounted custom components without also documenting the
  mount path and deployment env var changes.
- Do not introduce repo-managed flow JSON without deciding where that directory
  lives and how Langflow will load it on startup or via API.
