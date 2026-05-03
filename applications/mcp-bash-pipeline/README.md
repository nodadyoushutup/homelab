# MCP Bash Pipeline

Native Streamable HTTP MCP server for repo-managed bash pipeline entrypoints.

Why this exists:

- provides a narrow operator surface for running the repo's existing pipeline
  scripts without exposing arbitrary shell execution
- reuses the workspace-header pattern from the repo's other workspace-mounted
  MCP servers
- keeps deployment behavior centered on the repo's documented pipeline
  contract under `pipelines/terraform/**/*.sh`, with legacy
  `terraform/**/pipeline/*.sh` wrappers accepted as compatibility aliases

Current scope:

- lists pipeline entrypoints under the selected workspace root
- inspects pipeline files with support-status metadata
- runs supported pipeline entrypoints synchronously and returns bounded output

Current exclusions:

- arbitrary command execution
- non-pipeline shell scripts outside `pipelines/terraform/**/*.sh`
- a few known host-dependent pipelines that rely on operator-local bootstrap
  behavior outside this container's current runtime contract
