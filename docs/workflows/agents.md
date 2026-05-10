# LangGraph Agent Contract Workflow

This document defines how to update the repo-managed LangGraph agent contracts
and their runtime wiring.

Use [`docs/agents/README.md`](./../agents/README.md) for the current runtime
set and role definitions. Use the relevant agent and subagent docs for their
native input/output schemas.

This is not a repo-wide contributor startup workflow. It applies when you are
changing LangGraph agent behavior under `applications/langgraph/` or updating
the contract docs under `docs/agents/`.

## Standard Flow

1. read `docs/agents/README.md`
2. decide whether the change affects:
   - a parent agent contract
   - an internal subagent contract
   - MCP wiring
   - runtime routing behavior
3. update the concrete Python instantiation under `applications/langgraph/`,
   any reusable builder class under `applications/langgraph/framework/agents/`,
   and the matching Markdown contract docs in the same change
4. update `docs/agents/README.md` if the runtime set, file map, or routing
   expectations changed
   - if the change removes an internal subagent, fold any durable instructions
     into the owning agent contract and delete the obsolete subagent contract
5. update `docs/workflows/langgraph.md` if the stable operating pattern changed
6. validate the affected LangGraph app or shared module

## Creation Rule

When the work creates a new parent agent or subagent, treat the repo-managed
Python file and the Markdown contract doc as one unit of work.

Required steps:

1. create the concrete Python instantiation under the active runtime path in
   `applications/langgraph/`
2. create the matching Markdown instructions/schema file in `docs/agents/` or
   `docs/subagents/<runtime-name>/`
3. update `docs/agents/README.md` so the new agent is part of the documented
   runtime set, file map, and runtime prompt source
4. add concrete object-level runtime prompt docs under
   `docs/subagents/<runtime-name>/`
5. if the implementation should be shared, add or reuse a class-based builder
   under `applications/langgraph/framework/agents/`
6. only then treat the new agent or subagent as part of the supported runtime

Do not create a doc-only agent or a Python-only agent.
Do not treat a reusable `framework/agents/` builder class as a runtime agent
unless a concrete app or subagent directory exports it.

## Routing Rule

- Parent agents own behavior, prioritization, and final decisions.
- Subagents own narrow reusable capabilities.
- Subagents should not depend on a specific parent unless a human explicitly
  asks for a parent-specific variant.
- In the default Homelab runtime, expose only the top-level `agent` graph to
  users and clients.
- Prefer runtime-local named subagents and the runtime's native delegation
  surface over repo-specific remote `call_*_agent` wrappers.
- When one agent delegates work to another, shape the input to match the
  callee's documented input schema and consume the callee's documented output
  schema.
- Treat every specialist result as returning to the parent. If a specialist
  identifies follow-up work for a different specialist, the specialist reports
  that recommendation and the parent makes the next call.
- In the `Homelab` runtime, route source code, config, repository structure,
  file paths, filesystem state, MCP workspace visibility, and implementation
  work to the `Code` specialist when it is wired into the runtime.
- In the `Homelab` runtime, route local git workflows and GitHub pull request /
  check / review work to the `Git` specialist when it is wired into the runtime.
- In the `Homelab` runtime, route technical soundness review, architecture
  review, code impact review, workflow impact review, and pre-development
  implementation guidance to the `Tech Lead` specialist when it is wired into
  the runtime.
- Route only to specialists that are currently wired into the runtime. If no
  matching specialist exists for a requested domain, return that limitation to
  the caller.
