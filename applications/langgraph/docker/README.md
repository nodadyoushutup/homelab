# LangGraph container and local entrypoints

This directory holds everything that wires the **homelab LangGraph** Python
tree into containers and local dev helpers.

Runtime secrets for all graphs live in the **homelab** file ``.config/.env``
(next to ``applications/``), not in per-agent ``.env`` files. ``agent_server.sh``
exports those values into the shell before starting ``langgraph dev``. The
Compose stack uses the same file via ``env_file`` on ``langgraph-dev``.

- **`Dockerfile`** — image build for the default `agent/` app boundary. Build
  context must stay **`applications/langgraph/`** (repository root of this
  app) so `COPY framework`, `COPY agent`, and `pip install -e .` resolve
  correctly. Example:

  `docker build -f docker/Dockerfile .`

- **`.dockerignore`** — lives here as the canonical copy. A symlink
  **`applications/langgraph/.dockerignore` → `docker/.dockerignore`** keeps
  Docker’s context-root ignore rules working when the context is the app root.

- **`agent_server.sh`** — runs `langgraph dev` against `../agent` (override with
  `LANGGRAPH_APP_DIR`).

- **`chat.sh`** — runs the paired LangChain Agent Chat dev server; defaults
  `LANGCHAIN_AGENT_CHAT_APP_DIR` to `../langchain-agent-chat` next to this app.
