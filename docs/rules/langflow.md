# Langflow Rules

This document defines the steady-state rules for the Langflow deployment in
this repo. Use [docs/workflows/langflow.md](./../workflows/langflow.md) for the
operator workflow.

## Scope

This document applies to:

- `kubernetes/langflow/`
- `kubernetes/argocd-management/langflow-app.yaml`
- `kubernetes/argocd-management/langflow-project.yaml`
- repo-local Langflow client references such as `.codex/config.toml`

## Deployment Ownership

- The Langflow deployment is a Kubernetes-managed app and belongs under
  `kubernetes/langflow/`. Do not move its deployment source of truth into
  `terraform/swarm/`.
- Kubernetes infrastructure for Langflow stays adjacent to the app chart
  wrapper:
  - Helm wrapper and values: `kubernetes/langflow/`
  - Argo CD project and application wiring:
    `kubernetes/argocd-management/langflow-{project,app}.yaml`
- The current deployment shape is split frontend plus backend plus PostgreSQL:
  - frontend service: `langflow`
  - backend service: `langflow-backend`
  - internal PostgreSQL service: `langflow-postgres`

## Runtime Rules

- Keep the backend at one replica unless Langflow's build/job state handling is
  changed and revalidated. The current deployment intentionally pins the
  backend to one replica because build/job tracking is pod-local.
- Keep PostgreSQL as the persistent Langflow database for this deployment.
  Flows, projects, variables, and related runtime state currently live in that
  database.
- Treat the database as the live runtime store, not the long-term authorship
  format for repeatable flow definitions.

## Source-of-Truth Rules

- The preferred repo-managed format for repeatable Langflow assets is:
  - flows exported as Langflow JSON
  - custom components stored as Python files
  - deployment behavior controlled through Langflow environment variables
- Do not treat ad hoc UI-only flow edits as complete change management when the
  flow is intended to be durable or reproducible. Export or otherwise capture
  the authored flow in repo-managed artifacts.
- There is no repo-managed Langflow flow archive in this repo yet. Until that
  pattern is implemented, the Langflow PostgreSQL database remains the
  effective live state.

## Component Rules

- Prefer repo-managed custom components over large in-editor custom code when
  the behavior is reusable, long-lived, or important enough to review in Git.
- Custom Python components should be loaded from a filesystem path via
  `LANGFLOW_COMPONENTS_PATH` rather than copied manually into the container
  image internals.
- `LANGFLOW_COMPONENTS_INDEX_PATH` may be used to curate the component catalog,
  but it does not replace `LANGFLOW_COMPONENTS_PATH` for loading Python modules
  from disk.

## Flow Packaging Rules

- When we adopt repo-managed Langflow flows, they should be stored as exported
  Langflow JSON and loaded through `LANGFLOW_LOAD_FLOWS_PATH` or the Langflow
  API.
- Startup-loaded flow directories require `LANGFLOW_AUTO_LOGIN=True`.
- If a flow depends on custom components, ship the flow JSON and the matching
  component code together. Do not update one without the other.

## Security Rules

- Secrets for the Langflow deployment continue to come from Kubernetes
  `ExternalSecret` wiring and the backing Vault path, not from committed files
  in the repo.
- `LANGFLOW_SKIP_AUTH_AUTO_LOGIN=True` is a temporary auth-relaxation choice in
  the current deployment. Do not silently normalize that as a permanent safe
  default.
- `LANGFLOW_API_KEY_SOURCE=env` is the current deployment model for automated
  API consumers. Keep the backing key in the Vault -> ExternalSecret flow and
  do not hardcode it into repo-managed manifests or Swarm tfvars.
- API keys or tokens embedded directly into exported flow JSON are secrets. If
  flows are exported into the repo, scrub or variable-reference those values
  first.

## MCP Integration Rules

- The repo-local `.codex/config.toml` entry that points at the Langflow project
  MCP endpoint is workspace-specific configuration, not a replacement for the
  underlying flow source of truth.
- The repo-local `.codex/config.toml` file is also the intended source for the
  workspace's external `mcp_*` server URLs when Langflow's Settings > MCP
  Servers registry should mirror the repo-managed operator MCP set.
- Use `scripts/misc/sync_langflow_mcp_servers.py` to upsert those repo-managed
  external MCP server entries into Langflow instead of re-entering them by hand.
  The sync intentionally skips the `langflow` project endpoint and does not
  delete Langflow-only registry entries that are not declared in `.codex/config.toml`.
- If the Langflow project ID or MCP endpoint path changes, update the matching
  client config intentionally and validate the new endpoint.

## Documentation Rule

- If the stable Langflow operating pattern changes, update this file and
  [docs/workflows/langflow.md](./../workflows/langflow.md) in the same task.
