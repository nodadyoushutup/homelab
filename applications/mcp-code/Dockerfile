# Build from repository root (same pattern as applications/gha-runner) so we can
# COPY shared install scripts and ast-grep assets.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/opt/mcp-code \
    PATH=/opt/mcp-proxy-venv/bin:/opt/mcp-code-venv/bin:/opt/npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Node 22 (NodeSource), MCP filesystem server, ast-grep CLI, tree-sitter-cli, and
# /opt/ast-grep-parsers/dockerfile.so (required by sgconfig customLanguages).
COPY scripts/install/mcp_code_tooling.sh /tmp/mcp_code_tooling.sh
ARG MCP_FILESYSTEM_VERSION=2026.1.14
ARG AST_GREP_CLI_VERSION=0.40.5
ENV MCP_FILESYSTEM_VERSION=${MCP_FILESYSTEM_VERSION} \
    AST_GREP_CLI_VERSION=${AST_GREP_CLI_VERSION}
RUN chmod 0755 /tmp/mcp_code_tooling.sh \
  && /tmp/mcp_code_tooling.sh \
  && rm -f /tmp/mcp_code_tooling.sh

RUN python3 -m venv /opt/mcp-code-venv \
  && /opt/mcp-code-venv/bin/pip install --upgrade pip setuptools wheel

RUN python3 -m venv /opt/mcp-proxy-venv \
  && /opt/mcp-proxy-venv/bin/pip install --upgrade pip \
  && /opt/mcp-proxy-venv/bin/pip install --no-cache-dir "mcp-proxy>=0.11.0"

COPY applications/mcp-code/requirements.txt /tmp/mcp-code-requirements.txt
RUN /opt/mcp-code-venv/bin/pip install --no-cache-dir -r /tmp/mcp-code-requirements.txt \
  && rm -f /tmp/mcp-code-requirements.txt

RUN mkdir -p /opt/ast-grep-config \
  && if ! getent passwd 1000 >/dev/null; then \
       useradd --create-home --shell /bin/bash --uid 1000 mcpcode; \
     fi

COPY applications/mcp-code/ast-grep-bundled/sgconfig.yml /opt/ast-grep-config/sgconfig.yml
COPY applications/mcp-code/ast-grep-bundled/server.py /opt/mcp-code/ast-grep-server.py

COPY applications/mcp-code/src/mcp_code /opt/mcp-code/mcp_code
COPY applications/mcp-code/entrypoint.sh /usr/local/bin/mcp-code-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-code-entrypoint /opt/mcp-code/ast-grep-server.py \
  && mkdir -p /home/mcpcode \
  && chown -R 1000:1000 /opt/mcp-proxy-venv /opt/mcp-code-venv /opt/mcp-code /opt/ast-grep-config /opt/ast-grep-parsers /opt/npm-global /home/mcpcode

USER 1000:1000
WORKDIR /home/mcpcode

EXPOSE 8100
ENTRYPOINT ["/usr/local/bin/mcp-code-entrypoint"]
