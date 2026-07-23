FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

RUN pip install --no-cache-dir "workspace-mcp==1.21.0"

RUN useradd --uid 1000 --create-home appuser \
  && mkdir -p /tmp/workspace-mcp/credentials /run/workspace-mcp \
  && chown -R appuser:appuser /tmp/workspace-mcp /run/workspace-mcp

COPY entrypoint.sh /usr/local/bin/mcp-google-workspace-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-google-workspace-entrypoint

USER appuser
WORKDIR /app

EXPOSE 8086
ENTRYPOINT ["/usr/local/bin/mcp-google-workspace-entrypoint"]
