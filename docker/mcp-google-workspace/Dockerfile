FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/opt/workspace-mcp-patch

RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "workspace-mcp==1.14.2"

RUN useradd --create-home --shell /bin/sh workspace-mcp \
  && mkdir -p /tmp/workspace-mcp/credentials /run/workspace-mcp /opt/workspace-mcp-patch \
  && chown -R workspace-mcp:workspace-mcp /tmp/workspace-mcp /run/workspace-mcp /opt/workspace-mcp-patch

COPY sitecustomize.py /opt/workspace-mcp-patch/sitecustomize.py
COPY entrypoint.sh /usr/local/bin/mcp-google-workspace-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-google-workspace-entrypoint /opt/workspace-mcp-patch/sitecustomize.py

USER workspace-mcp

EXPOSE 8086
ENTRYPOINT ["/usr/local/bin/mcp-google-workspace-entrypoint"]
