# Code Validation And Rollout (homelab)

Generic validation depth and local-git posture are in the framework **Generic Code
Agent** system prompt. This file lists **homelab** commands and release routing.

## Validation

- For narrow Python LangGraph changes, a syntax check such as
  `python3 -m compileall applications/langgraph/agent applications/langgraph/subagents applications/langgraph/framework`
  is a reasonable baseline.
- For frontend, container, Kubernetes, Terraform, or CI changes, choose the
  narrowest meaningful validation from the relevant docs or local package
  metadata.

## Git, GitHub, and release (homelab)

- When implementation work must **pin a new container tag** (Terraform, Kubernetes,
  Compose, etc.) for a homelab image, **`code`** applies pin edits and performs
  **commit/push** when requested; **`github`** owns **Actions dispatch**, PR/check
  monitoring, and GitHub-side coordination per
  [docker-build-github-actions.md](../../workflows/docker-build-github-actions.md).
  A new image is **not** finished until that doc’s **live health** criteria are
  met.
