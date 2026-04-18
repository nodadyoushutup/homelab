# LangGraph Runtime Image

This directory contains the repo-owned container wrapper for the homelab
LangGraph runtime. The image packages the source tree under
[`langgraph/`](../../langgraph) and runs:

- `langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload`

The runtime currently serves these graphs from the bundled codebase:

- `controller_agent`
- `code_analysis_agent`
- `jira_agent`

Build context:

- `langgraph/`

Dockerfile path:

- `applications/langgraph/Dockerfile`

Published image:

- `harbor.nodadyoushutup.com/controller-agent/controller-agent:<tag>`

The image name remains `controller-agent` for now because the Kubernetes app,
Harbor project, and pull-secret wiring already target that published path.
