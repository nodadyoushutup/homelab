FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app/langgraph

COPY . /app/langgraph

RUN pip install --upgrade pip && \
    pip install -r /app/langgraph/requirements.txt && \
    pip install -e .

WORKDIR /app/langgraph/apps/controller-agent

EXPOSE 2024

CMD ["langgraph", "dev", "--host", "0.0.0.0", "--port", "2024", "--no-browser", "--no-reload"]
