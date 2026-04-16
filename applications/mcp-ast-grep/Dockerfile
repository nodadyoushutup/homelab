FROM node:22-trixie-slim AS node-runtime

ARG AST_GREP_CLI_VERSION=0.40.5
RUN npm install --global "@ast-grep/cli@${AST_GREP_CLI_VERSION}" tree-sitter-cli

FROM node-runtime AS parser-build

ARG TREE_SITTER_DOCKERFILE_REF=971acdd908568b4531b0ba28a445bf0bb720aba5

RUN apt-get update \
  && apt-get install --yes --no-install-recommends build-essential ca-certificates git \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/ast-grep-parsers \
  && git clone https://github.com/camdencheek/tree-sitter-dockerfile.git /tmp/tree-sitter-dockerfile \
  && cd /tmp/tree-sitter-dockerfile \
  && git checkout "${TREE_SITTER_DOCKERFILE_REF}" \
  && tree-sitter build --output /opt/ast-grep-parsers/dockerfile.so \
  && rm -rf /tmp/tree-sitter-dockerfile

FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

ARG MCP_PYTHON_SDK_VERSION=1.26.0

RUN apt-get update \
  && apt-get install --yes --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=node-runtime /usr/local/ /usr/local/
COPY --from=parser-build /opt/ast-grep-parsers /opt/ast-grep-parsers

RUN pip install --no-cache-dir \
  "mcp[cli]==${MCP_PYTHON_SDK_VERSION}" \
  "pyyaml==6.0.3"

RUN useradd --create-home --shell /bin/sh ast-grep

COPY sgconfig.yml /opt/ast-grep-config/sgconfig.yml
COPY server.py /usr/local/bin/ast-grep-mcp-server.py
COPY entrypoint.sh /usr/local/bin/mcp-ast-grep-entrypoint

RUN chmod 0755 /usr/local/bin/ast-grep-mcp-server.py /usr/local/bin/mcp-ast-grep-entrypoint

USER ast-grep

EXPOSE 8096
ENTRYPOINT ["/usr/local/bin/mcp-ast-grep-entrypoint"]
