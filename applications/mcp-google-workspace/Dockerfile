FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "workspace-mcp==1.21.0"

RUN useradd --create-home --shell /bin/sh workspace-mcp \
  && mkdir -p /tmp/workspace-mcp/credentials /run/workspace-mcp \
  && chown -R workspace-mcp:workspace-mcp /tmp/workspace-mcp /run/workspace-mcp

COPY entrypoint.sh /usr/local/bin/mcp-google-workspace-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-google-workspace-entrypoint

USER workspace-mcp

EXPOSE 8086
ENTRYPOINT ["/usr/local/bin/mcp-google-workspace-entrypoint"]
