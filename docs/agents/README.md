# Agents

This directory defines agent roles, reusable subagents, and the message contract they use to collaborate.

## Design principles

- Always choose the agent intentionally at prompt time.
- Parent agents own role-specific behavior, prioritization, and decision-making.
- Subagents own narrow capabilities and should remain reusable across parent agents.
- Subagents should not assume who called them. They should rely on the incoming task contract, not parent-specific hidden context.
- Shared communication rules belong in one place so Langflow, MCP tools, and future orchestration layers can use the same contract.

## Current agent set

- Parent agent: `Developer`
- Subagent: `Code Analysis`

## File map

- `protocol.md`: shared request/response contract for agent-to-agent communication
- `developer-agent.md`: the current top-level supervisor/developer agent definition
- `subagents/code-analysis-subagent.md`: reusable code analysis capability definition

## Selection workflow

Before starting work, explicitly choose the agent that should own the task.

If the prompt does not name an agent, select one intentionally before execution rather than defaulting to an unnamed general agent.

Use [docs/workflows/agents.md](./../workflows/agents.md) for the operational
selection flow and lock-in rule.

Required behavior:

- choose the owning parent agent before implementation or investigation starts
- choose any needed subagents from the documented subagent set based on
  capability
- lock that agent set before proceeding
- if the task changes materially, explicitly re-evaluate and re-lock the agent set

Current default choices:

- Use `Developer` when the task needs implementation, debugging, code changes, repo navigation, or orchestration of technical subtasks.
- Use `Code Analysis` only as a delegated capability through a parent agent, or directly when the only goal is source-of-truth analysis without implementation.

## Architecture rule

Parent agents may use any compatible subagent. Subagents must be designed so they can be mixed and matched across different parent agents without rewriting their core instructions.
