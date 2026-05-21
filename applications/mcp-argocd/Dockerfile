ARG MCP_ARGOCD_UPSTREAM_IMAGE=ghcr.io/argoproj-labs/mcp-for-argocd:latest@sha256:ef703dc15d0534c5368f835ae4948ac212055a3486481a56b05e9eb042a4ea6f
FROM ${MCP_ARGOCD_UPSTREAM_IMAGE}

USER root

COPY entrypoint.sh /usr/local/bin/mcp-argocd-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-argocd-entrypoint

USER 1000

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/mcp-argocd-entrypoint"]
