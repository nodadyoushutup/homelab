# LangGraph agent runtime index and contract workflow

This document is the **runtime contract index** for repo-managed LangGraph agents
under `applications/langgraph/`: design rules, where prompts live, and how to
update them. It also defines the **standard workflow** for changing agent
behavior.

These are not a repo-wide contributor startup checklist. Docker image publish
discipline for this repo lives in
[`docker-build-github-actions.md`](./docker-build-github-actions.md).

## Design principles

- Route work intentionally inside the runtime instead of relying on unnamed
  generic behavior.
- Parent agents own role-specific behavior, prioritization, and decision-making.
- Subagents own narrow capabilities and should remain reusable across parent agents.
- The default LangGraph app uses named in-process subagents inside one LangGraph
  app boundary, exposed through one user-facing graph named `agent`. Do not
  maintain repo-specific remote `call_*_agent` wrappers unless a future task
  explicitly reintroduces a remote boundary.
- The default app is hub-and-spoke: `agent` chooses the subagent, receives the
  subagent response, and decides the next step. Subagents may recommend another
  subagent, but they must not transfer directly to one.
- Subagents should not assume who called them. They should rely on the incoming
  task input schema, not parent-specific hidden context.
- Each agent or subagent should document its own accepted input schema and
  emitted output schema in its own file.
- Callers should adapt to the callee's documented schema instead of relying on a
  repo-wide shared protocol file.

## Current runtime set

- Parent graph: `agent` (supervisor implementation: `HomelabSupervisorAgent` in
  `applications/langgraph/framework/agents/supervisor.py`; instructions in
  `applications/langgraph/agent/system_prompt.md`)
- Subagent: `Code`
- Subagent: `GitHub`
- Subagent: `Jira`
- Subagent: `Tech Lead`

## File map

- `applications/langgraph/agent/system_prompt.md`: top-level supervisor
  orchestration contract for the `agent` graph (not customized via `docs/`)
- `docs/subagents/code/*.md`: **homelab** overlays for the Code specialist (runtime
  URLs, paths, validation commands, Terraform layout, docs tree policy). Generic
  coding, discovery, implementation, tool/search, validation posture, local-git and
  GitHub handoff rules, output contract, and cross-language conventions live in
  `applications/langgraph/framework/agents/system_prompts/code_system_prompt.md`
  (loaded by `CodeAgent`). Numbered `01`–`06` are contracts and filesystem rules;
  `07`–`14` include per-language or per-format **homelab** shelves (including local
  git) that point at the framework prompt for shared guidance.
- `docs/subagents/github/*.md`: **homelab** overlays for the GitHub specialist (PR
  policy, Actions dispatch, responsibility split vs `code`). Generic GitHub MCP
  behavior lives in
  `applications/langgraph/framework/agents/system_prompts/github_system_prompt.md`
  (loaded by `GithubAgent`).
- `docs/subagents/jira/*.md`: **homelab** overlays for the Jira specialist (HOME
  project, status names, custom fields, supervisor routing to `tech_lead` / `code`).
  Generic Jira behavior lives in
  `applications/langgraph/framework/agents/system_prompts/jira_system_prompt.md`
  (loaded by `JiraAgent`).
- `docs/subagents/tech-lead/*.md`: **homelab** overlays for Tech Lead (MCP URLs,
  paths, Jira field mapping). Generic review behavior lives in
  `applications/langgraph/framework/agents/system_prompts/tech_lead_system_prompt.md`
  (loaded by `TechLeadAgent`).

## Required creation artifacts

When adding a new repo-managed runtime agent or subagent, create the concrete
Python instantiation and the Markdown contract docs in the same change.
Reusable builder classes under `applications/langgraph/framework/agents/` are
implementation scaffolding; they are not part of the supported runtime set until
an app or subagent directory instantiates and exports them.

**Parent graph:**

- repo-managed Python instantiation under a concrete `applications/langgraph/`
  app directory, optionally backed by a reusable builder class in
  `applications/langgraph/framework/agents/`
- `applications/langgraph/<app>/system_prompt.md` (or an equivalent app-local
  prompt file wired by that app’s agent class)
- update this document if the supported runtime set or file map changes

**Subagent:**

- repo-managed Python instantiation under a concrete `applications/langgraph/`
  subagent directory, optionally backed by a reusable builder class in
  `applications/langgraph/framework/agents/`
- `docs/subagents/<runtime-name>/*.md`
- update this document if the runtime set or file map changes

Do not treat a new subagent as part of the supported agent set until both the
Python file and the `docs/subagents/<runtime-name>/*.md` overlay set exist. For
a new parent graph, require the Python export and its app-local supervisor
prompt file.

Do not create a doc-only agent or a Python-only agent. Do not treat a reusable
`framework/agents/` builder class as a runtime agent unless a concrete app or
subagent directory exports it.

## Runtime prompt source (layers)

- Shared guardrails for every agent and subagent live in
  `applications/langgraph/framework/agents/system_prompts/base_system_prompt.md`
- Reusable class-level guidance lives with the reusable builder (`jira_system_prompt.md`,
  `code_system_prompt.md`, `github_system_prompt.md`, `tech_lead_system_prompt.md`
  under `applications/langgraph/framework/agents/system_prompts/`)
- Top-level supervisor prompts for the default app live in
  `applications/langgraph/agent/system_prompt.md` (`HomelabSupervisorAgent` does
  not load `docs/subagents/agent/`)
- Concrete runtime object-level prompt docs for **specialists** live in
  `docs/subagents/<runtime-name>/*.md` (loaded in sorted filename order; use numeric
  prefixes to control ordering)
- Python wiring under `applications/langgraph/framework/agents/` should load those
  Markdown layers into the runtime `system_prompt` argument

When specialist overlays or routing expectations change, update the relevant
`docs/subagents/` files and this document. When supervisor behavior changes,
update `applications/langgraph/agent/system_prompt.md` and framework wiring.

## Current handoff model

For now, do not assume Redis-backed shared memory or any other shared agent state
layer.

- Every agent call must include the context needed for that specific task.
- Every subagent overlay and supervisor prompt should define the input shape it
  accepts and the output shape it returns (supervisor:
  `applications/langgraph/agent/system_prompt.md`).
- Callers should read the target specialist doc and shape the call to match that
  documented schema.
- Parent agents should use subagent output schemas to decide the next call, the
  next tool action, or the final user response.
- Subagent outputs must return to the parent agent before any further specialist
  call; subagent-to-subagent handoff is only a recommendation in the output, not
  a direct transfer.
- Every agent should check the relevant `docs/` material before falling back to
  broad repo search.

## Runtime routing expectations

- The `agent` graph is the coordinating supervisor for runtime orchestration.
- The supervisor delegates to local named specialists through the runtime's
  native subagent surface instead of a repo-specific remote call wrapper.
- The default app exposes `agent` as the supported graph. Specialist runnables
  are private implementation details of that supervisor unless a future task
  explicitly creates a separate deployment boundary.
- `Code`, `GitHub`, `Jira`, and `Tech Lead` remain reusable specialist capabilities
  for their respective domains.
- If runtime routing changes materially, update Python under
  `applications/langgraph/` and the matching prompt sources (`agent/system_prompt.md`
  and `docs/subagents/*` as applicable).

## Architecture rule

Parent agents may use any compatible subagent. Subagents must be designed so they
can be mixed and matched across different parent agents without rewriting their
core instructions.

---

## Standard flow (when changing contracts or wiring)

This section applies when you are changing LangGraph agent behavior under
`applications/langgraph/` or updating the contract index above.

1. Reread this document (design principles, file map, routing expectations).
2. Decide whether the change affects:
   - a parent agent contract
   - an internal subagent contract
   - MCP wiring
   - runtime routing behavior
3. Update the concrete Python instantiation under `applications/langgraph/`, any
   reusable builder class under `applications/langgraph/framework/agents/`, and
   the matching Markdown prompt sources in the same change.
4. Update **this document** if the runtime set, file map, or routing expectations
   changed. If the change removes an internal subagent, fold any durable
   instructions into the owning agent contract and delete the obsolete subagent
   contract.
5. Update `docs/workflows/langgraph.md` if the stable operating pattern changed.
6. Validate the affected LangGraph app or shared module.

## Creation rule

When the work creates a new parent graph or subagent, treat the repo-managed
Python file and the Markdown contract doc as one unit of work.

Required steps:

1. Create the concrete Python instantiation under the active runtime path in
   `applications/langgraph/`.
2. For a **parent graph**, add or extend `applications/langgraph/<app>/system_prompt.md`
   (or the app’s wired prompt file). For a **subagent**, add
   `docs/subagents/<runtime-name>/*.md` overlays.
3. Update **this document** so the new agent is part of the documented runtime set
   and file map.
4. If the implementation should be shared, add or reuse a class-based builder
   under `applications/langgraph/framework/agents/`.
5. Only then treat the new agent or subagent as part of the supported runtime.

## Routing rule

- Parent agents own behavior, prioritization, and final decisions.
- Subagents own narrow reusable capabilities.
- Subagents should not depend on a specific parent unless a human explicitly asks
  for a parent-specific variant.
- In the default Homelab runtime, expose only the top-level `agent` graph to users
  and clients.
- Prefer runtime-local named subagents and the runtime's native delegation surface
  over repo-specific remote `call_*_agent` wrappers.
- When one agent delegates work to another, shape the input to match the callee's
  documented input schema and consume the callee's documented output schema.
- Treat every specialist result as returning to the parent. If a specialist
  identifies follow-up work for a different specialist, the specialist reports that
  recommendation and the parent makes the next call.
- In the default runtime, route source code, config, repository structure, file
  paths, filesystem state, MCP workspace visibility, and implementation work to the
  `Code` specialist when it is wired into the runtime.
- In the default runtime, route **local git** (branch, fetch, pull, commit, push) to
  the `Code` specialist when **mcp-code** exposes git tools. Route **GitHub** pull
  request / check / review / Actions API work to the `GitHub` specialist when it is
  wired into the runtime.
- In the default runtime, route technical soundness review, architecture review,
  code impact review, workflow impact review, and pre-development implementation
  guidance to the `Tech Lead` specialist when it is wired into the runtime.
- Route only to specialists that are currently wired into the runtime. If no
  matching specialist exists for a requested domain, return that limitation to the
  caller.
