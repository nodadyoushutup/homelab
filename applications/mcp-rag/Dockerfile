FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY applications/mcp-rag/requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY applications/mcp-rag/src /app/src

EXPOSE 8080

RUN printf '%s\n' '#!/usr/bin/env bash' 'exec python /app/src/core/server.py "$@"' > /usr/local/bin/mcp-rag \
    && chmod +x /usr/local/bin/mcp-rag

CMD ["mcp-rag", "serve"]
