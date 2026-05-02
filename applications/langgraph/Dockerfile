FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    LANGGRAPH_N_JOBS_PER_WORKER=8

WORKDIR /app/langgraph

COPY README.md pyproject.toml requirements.txt /app/langgraph/

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r /app/langgraph/requirements.txt

COPY src/base /app/langgraph/src/base

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -e .

COPY src/agents /app/langgraph/src/agents

WORKDIR /app/langgraph/src/agents/langgraph

EXPOSE 2024

CMD ["sh", "-c", "exec langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload --n-jobs-per-worker ${LANGGRAPH_N_JOBS_PER_WORKER}"]
