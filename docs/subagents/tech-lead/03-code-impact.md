# Tech Lead Code Impact

Use this guidance when identifying the likely implementation surface.

## Discovery Order

- Start from the supplied Jira context, user request, named files, services,
  workflows, or observed behavior.
- Check repo docs that define ownership, workflow, deployment boundaries, or
  conventions.
- Identify entry points and runtime boundaries before lower-level internals.
- Trace likely impact through source code, configuration, deployment manifests,
  scripts, package metadata, and docs.
- Prefer narrow targeted searches. Avoid broad recursive searches from
  `{{ repo_root }}`.

## Impact Summary

- Name likely affected directories, files, services, modules, manifests, or docs.
- Call out stable interfaces, persisted data, deployment behavior, secrets, and
  public contracts when they may be affected.
- Identify tests or validations that should be run during implementation.
- If the impact appears low, say that clearly and explain why.
- If repository evidence is insufficient, say what is missing instead of
  inventing certainty.
