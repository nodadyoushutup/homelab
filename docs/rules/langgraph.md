# LangGraph Rules

This document defines the steady-state rules for the repo-managed LangGraph and
Deep Agents implementation under `applications/langgraph/`.

Use [docs/workflows/langgraph.md](./../workflows/langgraph.md) for the standard
operator flow.

## Scope

This document applies to:

- `applications/langgraph/`
- repo-managed LangGraph agent configs such as
  `applications/langgraph/agent/langgraph.json` and
  `applications/langgraph/agent/subagents/*/langgraph.json`
- shared LangGraph Python code under `applications/langgraph/framework/`
- agent-local and subagent-local skills under
  `applications/langgraph/agent/**/skills/`

## Source-of-Truth Rules

- Keep shared Python logic under `applications/langgraph/framework/` and keep
  the default deployable agent boundary under `applications/langgraph/agent/`,
  with co-deployed specialist config in
  `applications/langgraph/agent/subagents/<specialist-name>/`.
- Each deployable LangGraph agent must keep its own `langgraph.json` in that
  agent's directory instead of relying on a monorepo-root config.
- Each deployable LangGraph agent should keep its runtime system prompt in an
  agent-local `system_prompt.md`.
- The top-level `docker/` directory may exist as a host-local development
  exception for bind-mounted dev containers. Do not treat it as the source of
  truth for deployment packaging or runtime ownership.
- A single deployable agent may expose multiple graphs from one `langgraph.json`
  when those graphs belong to the same runtime boundary.
- Treat `applications/langgraph/pyproject.toml` as the shared package
  dependency root for this monorepo scaffold unless a later change
  intentionally splits the apps into separate Python packages.

## App Boundary Rules

- Top-level remote agents should stay domain-oriented. Examples:
  `langgraph`, `code-agent`, `jira-agent`.
- Domain-oriented agents may be co-deployed as sibling graphs inside one app
  boundary when they share the same runtime and scaling needs.
- Internal Deep Agents subagents should stay task-oriented and narrower than
  their parent app. Examples inside a domain agent: `issue_discovery`,
  `issue_update`.
- Do not flatten every specialist into its own remote deployment unless the
  runtime or security boundary is worth the extra operational cost.
- Internal Deep Agents subagents are optional. The current `jira-agent`
  intentionally keeps its create and edit rules in the app-level prompt and
  skills instead of separate internal specialists.

## Environment Rules

- Keep local secrets and model overrides in the homelab-wide file
  `<repo>/.secrets/.env` instead of per-agent or per-subagent ``.env`` files.
  ``framework.configuration.merged_settings`` loads that path (override with
  ``HOMELAB_SECRETS_ENV`` when needed). The LangGraph app no longer declares an
  ``env`` entry in each ``langgraph.json``.
- Internal Deep Agents subagents may also own `system_prompt.md` files, which
  the parent app should load explicitly when building those subagents.
- Do not assume subagent-local env files create isolated process environments.
  Only separately deployed apps get real process-level env isolation.

## MCP Rules

- Deployed LangGraph apps should prefer HTTP or SSE MCP servers over `stdio`
  transports, because deployed environments do not spawn local subprocesses for
  tool servers.
- Agent-local `mcp.json` files define tool surfaces for the deployable agent.
- Subagent-local `mcp.json` files define tool surfaces that are loaded only into
  that internal subagent.
- Keep top-level supervisor tool surfaces thin. Domain-specific MCP access
  should usually live inside the specialist app or its internal subagents.
- When a specialist app uses a workspace-wide filesystem MCP for repo-backed
  analysis, wrap or constrain those filesystem tools to the intended repository
  root before exposing them to the model. Do not rely on the model to avoid the
  wider shared workspace on its own.
- In the `Homelab` runtime, questions about code, config, repository
  structure, file paths, filesystem contents, or MCP workspace visibility must
  route through the `Code` specialist instead of being answered directly by the
  supervisor.

## Agent Composition Rules

- The default deployed Homelab supervisor app boundary is
  `applications/langgraph/agent/`.
- Keep the default Homelab runtime as one deployed app boundary with named
  local specialist subagents delegated in-process.
- Do not keep unused remote agent delegation scaffolding or repo-specific
  `call_*_agent` wrappers in the default Homelab runtime.
- Prefer co-deploying related graphs in one app boundary first, then split them
  into remote deployments only when scaling, ownership, or security needs make
  the boundary worthwhile, and add the explicit transport in that same task.
- For local development, it is acceptable to run those same app boundaries with
  parallel `langgraph dev` processes instead of containers.
- Repo-local debug helpers are allowed under `applications/langgraph/` when
  they stay as thin wrappers around one documented app boundary and do not
  replace the app-local `langgraph.json` source of truth. Keep the container
  image definition and optional shell entrypoints under
  `applications/langgraph/docker/` so the Python tree stays separate from
  packaging glue.
- A top-level `docker/docker-compose.yml` is also allowed for local LangGraph
  plus LangChain Agent Chat development when it is clearly documented as a
  dev-only bind mount workflow and does not replace the app-local deployment
  sources of truth.
- A repo-local debug helper may also launch a paired local frontend for the
  same app boundary when it is clearly part of the same dev loop and the helper
  prints the resulting backend and frontend URLs explicitly.
- Internal Deep Agents subagents remain in-process and should be used for
  narrower specialization inside a single app boundary.
- Keep `Homelab` focused on coordination. It should not perform first-pass code
  or filesystem analysis directly when the `Code` specialist is available.
- Avoid circular remote delegation patterns such as `langgraph ->
  jira-agent -> langgraph` unless a future workflow explicitly defines
  how that loop is bounded.

## Skills Rules

- Keep skills in agent-local or subagent-local directories close to the code that
  owns them.
- Keep runtime prompt text in agent-local or subagent-local `system_prompt.md`
  files close to the code that owns them instead of burying long prompt bodies
  inside Python string literals.
- If a custom subagent needs its own skills, declare them explicitly instead of
  relying on parent inheritance.
- Keep skills small, bounded, and capability-specific.

## Documentation Rule

- If the stable LangGraph or Deep Agents operating pattern changes, update this
  file and [docs/workflows/langgraph.md](./../workflows/langgraph.md) in the
  same task.
