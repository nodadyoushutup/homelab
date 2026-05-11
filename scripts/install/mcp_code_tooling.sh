#!/usr/bin/env bash
# NOTE: applications/mcp-code/Dockerfile may skip this script for fast rebuilds; restore the
# COPY/RUN there when you need ast-grep CLI, tree-sitter Dockerfile parser, and pinned Node 22.
# Installs Node.js, @modelcontextprotocol/server-filesystem, ast-grep CLI,
# tree-sitter + Dockerfile parser, and Python packages used by mcp-code
# (aggregate MCP) and its stdio children. Intended for the mcp-code image;
# Toolchain versions align with the historical standalone MCP images (now folded
# into mcp-code).
set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

MCP_FILESYSTEM_VERSION="${MCP_FILESYSTEM_VERSION:-2026.1.14}"
AST_GREP_CLI_VERSION="${AST_GREP_CLI_VERSION:-0.40.5}"
TREE_SITTER_DOCKERFILE_REF="${TREE_SITTER_DOCKERFILE_REF:-971acdd908568b4531b0ba28a445bf0bb720aba5}"
log "Installing base packages"
apt-get update -y
apt-get install "${APT_OPTS[@]}" \
  ca-certificates \
  curl \
  gnupg \
  git \
  build-essential \
  python3 \
  python3-pip \
  python3-venv

log "Installing Node.js 22.x (NodeSource)"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install "${APT_OPTS[@]}" nodejs

# Use a dedicated prefix so @ast-grep/cli can install its `sg` shim without
# clashing with the system `sg` from login(1) under /usr/bin.
NPM_GLOBAL="${NPM_GLOBAL:-/opt/npm-global}"
mkdir -p "${NPM_GLOBAL}"

log "Installing global npm MCP filesystem server @ ${MCP_FILESYSTEM_VERSION} (prefix ${NPM_GLOBAL})"
npm install --global --prefix "${NPM_GLOBAL}" --omit=dev \
  "@modelcontextprotocol/server-filesystem@${MCP_FILESYSTEM_VERSION}"
npm cache clean --force

log "Installing ast-grep CLI @ ${AST_GREP_CLI_VERSION} and tree-sitter-cli (prefix ${NPM_GLOBAL})"
npm install --global --prefix "${NPM_GLOBAL}" --omit=dev \
  "@ast-grep/cli@${AST_GREP_CLI_VERSION}" tree-sitter-cli
npm cache clean --force

log "Building tree-sitter Dockerfile parser for ast-grep"
mkdir -p /opt/ast-grep-parsers
rm -rf /tmp/tree-sitter-dockerfile
git clone https://github.com/camdencheek/tree-sitter-dockerfile.git /tmp/tree-sitter-dockerfile
git -C /tmp/tree-sitter-dockerfile checkout "${TREE_SITTER_DOCKERFILE_REF}"
(
  cd /tmp/tree-sitter-dockerfile
  tree-sitter build --output /opt/ast-grep-parsers/dockerfile.so
)
rm -rf /tmp/tree-sitter-dockerfile

rm -rf /var/lib/apt/lists/*
log "mcp-code tooling install complete."
