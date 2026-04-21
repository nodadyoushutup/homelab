FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    LANGGRAPH_N_JOBS_PER_WORKER=8

WORKDIR /app/langgraph

COPY . /app/langgraph

RUN pip install --upgrade pip && \
    pip install -r /app/langgraph/requirements.txt && \
    pip install -e .

WORKDIR /app/langgraph/apps/langgraph

EXPOSE 2024

CMD ["sh", "-c", "exec langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload --n-jobs-per-worker ${LANGGRAPH_N_JOBS_PER_WORKER}"]
