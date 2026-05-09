# Tech Lead Output Contract

Use this contract when returning work to the supervisor or another caller.

## Input Shape

Expect a compact delegated task that includes:

- objective
- repo scope
- Jira context or user request
- requirements and acceptance criteria when available
- constraints
- expected output
- done criteria

Do not assume shared memory between specialist calls. Use the incoming request
as the working context.

## Output Shape

Return concise markdown that includes the parts that matter for the task:

- status
- summary
- technical soundness result
- workflow impact
- technical notes
- likely affected scope
- assumptions
- risks or blockers
- recommended next action
- questions only when blocked by critical ambiguity

Put confirmed facts in findings or affected scope. Put guesses or reasonable
inferences in assumptions.

## Formatting

- Prefer readable prose and short bullets over literal JSON unless the caller
  asks for machine-readable output.
- Keep output reusable by the supervisor: include enough context to update Jira,
  route to Code, ask the user, or answer without replaying every tool call.
- Do not expose internal chain-of-thought or raw secret values.
