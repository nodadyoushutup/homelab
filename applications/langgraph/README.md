# LangGraph Project

This directory is now the source-of-truth home for the homelab LangGraph
project and its repo-owned container wrapper.

It contains the LangGraph and Deep Agents implementation we have been
workshopping:

- `controller-agent`: user-facing coordinator
- `code-analysis-agent`: repository analysis specialist
- `jira-agent`: Jira specialist with internal Deep Agents subagents for create
  and edit flows

## Layout

```text
applications/langgraph/
├── apps/
│   ├── controller-agent/
│   ├── code-analysis-agent/
│   └── jira-agent/
├── src/
│   └── homelab_langgraph/
├── Dockerfile
├── pyproject.toml
├── requirements.txt
└── run.sh
```

Each deployable agent app has its own:

- `langgraph.json`
- `.env` or `.env.example`
- optional `mcp.json`
- app-local skills

The Jira app also has subagent-local:

- `.env` files loaded as config by the Jira app
- `mcp.json` files loaded as config by the Jira app
- skills directories referenced only by that internal subagent

## Current Intent

The primary local development path is one LangGraph development server that
hosts multiple graphs from the `controller-agent` app boundary.

What is already in place:

- a single-deployment `langgraph.json` in `apps/controller-agent` that
  exports the supervisor, code-analysis, and Jira graphs from one server
- shared Python package for reusable helpers
- supervisor-local delegation to compiled specialist graphs in the same
  deployment
- Jira internal subagents with distinct tools, skills, and config surfaces
- MCP loading support from app-local and subagent-local `mcp.json` files
- a repo-owned Docker wrapper in `Dockerfile` that packages this project and
  runs `langgraph dev`

What is still expected before real deployment:

- replace `.env.example` files with real `.env` files or deployment secrets
- replace `.mcp.json.example`-style placeholders with real `mcp.json` configs
- install dependencies
- run `langgraph dev` from an app directory or deploy with your target platform

## Model And API Key Defaults

The scaffold now defaults all LangGraph apps to `openai:gpt-5.4`.

Set `OPENAI_API_KEY` in each deployable app's `.env` file, or inject it through
your deployment environment. The app-local `langgraph.json` files already point
the runtime at each app's `.env`, so adding the key there is the simplest local
setup path.

## Local Development

Use the repo-root virtualenv and the helper launcher:

```bash
applications/langgraph/.venv/bin/pip install -r applications/langgraph/requirements.txt
./applications/langgraph/run.sh up
```

This starts one local server on port `2024` and defaults to a loopback
bring-up. The homelab hostname `https://langsmith.nodadyoushutup.com`
is intended to front the Kubernetes `controller-agent` deployment, which now
runs the same `langgraph dev` runtime inside the cluster.

The deployment serves:

- `controller_agent`
- `code_analysis_agent`
- `jira_agent`

The supervisor delegates to the code-analysis and Jira specialists as
co-deployed compiled subagents, so local development no longer depends on
multiple servers or loopback A2A wiring.

If you want a local-only bring-up instead of the homelab hostname, clear the
public base URL and bind back to loopback:

```bash
PUBLIC_BASE_URL= LANGGRAPH_BIND_HOST=127.0.0.1 ./applications/langgraph/run.sh up
```

If you intentionally want to route the local helper through a reverse-proxied
public hostname for testing, set the base URL explicitly:

```bash
PUBLIC_BASE_URL=https://your-temp-hostname ./applications/langgraph/run.sh up
```

If Studio is opened in Brave before the domain route is available, use the
native LangGraph tunnel mode instead:

```bash
PUBLIC_BASE_URL= LANGGRAPH_TUNNEL=1 ./applications/langgraph/run.sh up
```

If you later move the endpoint to a different reverse-proxied hostname, set
`PUBLIC_BASE_URL=https://your-hostname` before starting the helper. The
launcher will then print Studio and Agent Chat links that target that hostname.

The split specialist app directories still exist as the source of truth for
their local skills, MCP config, and env defaults, but the main local bring-up
path is now a single deployment.

## Container And Publish Notes

Build context:

- `applications/langgraph/`

Dockerfile path:

- `applications/langgraph/Dockerfile`

Published image:

- `harbor.nodadyoushutup.com/controller-agent/controller-agent:<tag>`

The image name remains `controller-agent` for now because the Kubernetes app,
Harbor project, and pull-secret wiring already target that published path.
