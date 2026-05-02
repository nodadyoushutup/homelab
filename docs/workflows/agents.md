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

1. read `docs/rules/langgraph.md` and `docs/agents/README.md`
2. decide whether the change affects:
   - a parent agent contract
   - an internal subagent contract
   - MCP wiring
   - runtime routing behavior
3. update the Python implementation under `applications/langgraph/` and the
   matching Markdown contract docs in the same change
4. update `docs/agents/README.md` if the runtime set, file map, or routing
   expectations changed
   - if the change removes an internal subagent, fold any durable instructions
     into the owning agent contract and delete the obsolete subagent contract
5. update `docs/workflows/langgraph.md` or `docs/rules/langgraph.md` if the
   stable operating pattern changed
6. validate the affected LangGraph app or shared module

## Creation Rule

When the work creates a new parent agent or subagent, treat the repo-managed
Python file and the Markdown contract doc as one unit of work.

Required steps:

1. create the Python implementation under the active runtime path in
   `applications/langgraph/`
2. create the matching Markdown instructions/schema file in `docs/agents/` or
   `docs/agents/subagents/`
3. update `docs/agents/README.md` so the new agent is part of the documented
   runtime set, file map, and runtime prompt source
4. only then treat the new agent or subagent as part of the supported runtime

Do not create a doc-only agent or a Python-only agent.

## Routing Rule

- Parent agents own behavior, prioritization, and final decisions.
- Subagents own narrow reusable capabilities.
- Subagents should not depend on a specific parent unless a human explicitly
  asks for a parent-specific variant.
- Prefer runtime-local named subagents and the runtime's native delegation
  surface over repo-specific remote `call_*_agent` wrappers.
- When one agent delegates work to another, shape the input to match the
  callee's documented input schema and consume the callee's documented output
  schema.
- In the `Homelab` runtime, questions about source code, config, repository
  structure, file paths, filesystem state, or MCP workspace visibility should
  be routed through the `Code` specialist instead of being answered directly by
  the parent.
