FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    LANGGRAPH_N_JOBS_PER_WORKER=8 \
    HOMELAB_REPO_ROOT=/app

WORKDIR /app/langgraph

COPY applications/langgraph/README.md applications/langgraph/pyproject.toml applications/langgraph/requirements.txt /app/langgraph/

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r /app/langgraph/requirements.txt

COPY applications/langgraph/framework /app/langgraph/framework

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -e .

COPY applications/langgraph/agent /app/langgraph/agent

COPY applications/langgraph/subagents /app/langgraph/subagents

COPY docs/subagents /app/docs/subagents

COPY docs/workflows /app/docs/workflows

COPY applications/langgraph/docker/langgraph_compose_healthcheck.py /usr/local/bin/langgraph_compose_healthcheck.py

WORKDIR /app/langgraph/agent

EXPOSE 2024

CMD ["sh", "-c", "exec langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload --n-jobs-per-worker ${LANGGRAPH_N_JOBS_PER_WORKER}"]
