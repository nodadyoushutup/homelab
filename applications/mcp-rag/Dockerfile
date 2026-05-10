FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt /tmp/requirements.txt

RUN pip install --upgrade pip \
    && pip install \
        --retries 10 \
        --default-timeout 120 \
        --no-cache-dir \
        -r /tmp/requirements.txt

COPY src /app/src

EXPOSE 8080

RUN printf '%s\n' '#!/usr/bin/env bash' 'exec python /app/src/core/server.py "$@"' > /usr/local/bin/mcp-rag \
    && chmod +x /usr/local/bin/mcp-rag

CMD ["mcp-rag", "serve"]
