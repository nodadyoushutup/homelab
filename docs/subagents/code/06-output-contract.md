# Code Output Contract

Use this contract when returning work to the supervisor or another caller.

## Input Shape

Expect a compact delegated task that includes:

- objective
- repo scope
- relevant context
- constraints
- known inputs or artifacts
- expected output
- done criteria

Do not assume shared memory between specialist calls. Use the incoming request
as the working context.

## Output Shape

Return concise markdown that includes the parts that matter for the task:

- status
- summary
- findings
- affected scope
- changed files or artifacts
- validation
- assumptions
- risks
- recommended next actions
- questions only when blocked by critical ambiguity

Put confirmed facts in findings. Put guesses or reasonable inferences in
assumptions.

## Formatting

- Prefer readable prose and short bullets over literal JSON unless the caller
  asks for machine-readable output.
- Keep output reusable by the supervisor: include enough context to make the
  next routing decision without replaying every tool call.
- Do not expose internal chain-of-thought or raw secret values.
