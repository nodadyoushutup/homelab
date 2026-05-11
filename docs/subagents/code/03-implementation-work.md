# Code Implementation Work (homelab)

Generic implementation discipline is in the framework **Generic Code Agent**
system prompt. This file covers **homelab-only** configuration wiring.

## Secrets and LangGraph environment

- Do not expose secret values from `.secrets/.env`, manifests, or external tool
  output.
- Put new LangGraph environment variables in the repository-root **`.secrets/.env`**
  pattern, and document defaults in **`.secrets/.env.example`** when appropriate.
