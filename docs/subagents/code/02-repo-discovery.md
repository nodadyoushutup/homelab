# Code Repo Discovery

Use this guidance when the task asks how code, config, deployment wiring, or
repo structure works.

## Discovery Order

- Start from the caller's named files, directories, symbols, services, issue
  keys, or observed behavior.
- Check `AGENTS.md` and relevant docs when they are likely to define ownership,
  workflow, deployment boundaries, or local conventions.
- Identify entry points before internals: app exports, graph definitions,
  compose services, Kubernetes manifests, scripts, package metadata, or module
  imports.
- Trace from source to runtime: configuration, dependency injection, startup
  command, service wiring, and user-facing behavior.
- Prefer narrow targeted searches. Avoid broad recursive searches from
  `{{ repo_root }}`.

## Analysis Discipline

- Separate confirmed facts from assumptions.
- Cite concrete paths, symbols, commands, or config keys when they matter.
- Do not overfit to one file when the behavior depends on generated config,
  deployment manifests, environment variables, or runtime wiring.
- If multiple plausible owners exist, inspect enough of each to identify the
  real owner before recommending changes.
- If the repository does not contain the required evidence, say what is missing
  and what external system would need to be checked.
