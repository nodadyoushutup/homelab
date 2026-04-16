# Agent Communication Protocol

This file defines the shared language agents use when delegating work to each other.

The goal is to keep subagents parent-agnostic while still letting results thread cleanly through a supervisor, Langflow tool call, or another orchestration layer.

## Core rules

- Every delegated task should include a clear objective, expected output, and constraints.
- Every subagent response should separate facts, assumptions, risks, and recommended next actions.
- Subagents should not assume hidden context from the caller. If context matters, it must be included in the request.
- Subagents should return structured results that another agent can reuse without re-parsing a long narrative.
- Parent agents remain responsible for final decisions, user-facing tradeoffs, and whether to call additional subagents.

## Request contract

Use this shape when one agent calls another:

```text
REQUEST
request_id: <unique-id>
from_agent: <caller-name>
to_agent: <target-name>
task_type: <short-capability-name>
objective: <what must be achieved>
repo_scope: <files/directories/services in scope>
context: <relevant background and known facts>
constraints: <rules, limits, and things to avoid>
inputs: <artifacts, snippets, file paths, prior findings>
expected_output: <what form the answer should take>
done_criteria: <how the caller knows the task is complete>
```

## Response contract

Use this shape when returning work:

```text
RESPONSE
request_id: <same-id>
from_agent: <responder-name>
status: <completed|partial|blocked>
summary: <short answer>
findings: <facts discovered from the work>
assumptions: <things inferred but not proven>
risks: <important caveats or failure modes>
artifacts: <files, commands, patches, references>
recommended_next_actions: <what the caller should do next>
questions: <only if blocked or critical ambiguity remains>
```

## Field guidance

- `request_id`: stable ID for threading related calls and responses.
- `task_type`: should describe capability, not org structure. Example: `code_analysis`, not `developer_helper`.
- `repo_scope`: keeps delegated work bounded.
- `expected_output`: avoids vague analysis and forces a usable handoff.
- `status`: use `partial` when useful work was done but not all criteria were met.
- `findings`: facts only. Put guesses in `assumptions`.
- `artifacts`: include file paths, functions, commands, or generated outputs another agent can inspect.

## Example

```text
REQUEST
request_id: dev-2026-04-16-001
from_agent: Developer
to_agent: Code Analysis
task_type: code_analysis
objective: Trace how qBittorrent ingress ports are defined and identify all files involved.
repo_scope: terraform/, kubernetes/
context: We need source-of-truth docs before changing ingress behavior.
constraints: Do not modify files. Ignore _old/.
inputs: User asked for architecture clarification.
expected_output: File-backed findings with affected paths and open risks.
done_criteria: Caller can decide what layer must change next.
```

```text
RESPONSE
request_id: dev-2026-04-16-001
from_agent: Code Analysis
status: completed
summary: Port exposure is split across Kubernetes Service manifests and FortiGate Terraform.
findings: ...
assumptions: ...
risks: ...
artifacts: kubernetes/... , terraform/... 
recommended_next_actions: Decide whether to change nodePort allocation or WAN forwarding first.
questions: none
```
