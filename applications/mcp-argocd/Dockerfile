ARG MCP_ARGOCD_UPSTREAM_IMAGE=ghcr.io/argoproj-labs/mcp-for-argocd:latest@sha256:da44010c0e08e80b020ddb1cc73af6534a4bb27428a0803eae3453276d588601
FROM ${MCP_ARGOCD_UPSTREAM_IMAGE}

USER root

COPY entrypoint.sh /usr/local/bin/mcp-argocd-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-argocd-entrypoint

USER 1000

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/mcp-argocd-entrypoint"]
