ARG MCP_ATLASSIAN_UPSTREAM_IMAGE=ghcr.io/sooperset/mcp-atlassian:latest@sha256:d2bb29af785bc44bbb16eee4e577eceabe208cdbe1bcac80c4be9915864de45d
FROM ${MCP_ATLASSIAN_UPSTREAM_IMAGE}

USER root

RUN apk add --no-cache git

COPY patches/ /tmp/mcp-atlassian-patches/

RUN set -eux; \
    site_packages="$(python -c 'import site; print(site.getsitepackages()[0])')"; \
    for patch_file in /tmp/mcp-atlassian-patches/*.patch; do \
      [ -e "${patch_file}" ] || continue; \
      (cd "${site_packages}" && git apply --recount "${patch_file}"); \
    done; \
    rm -rf /tmp/mcp-atlassian-patches

USER app

ENTRYPOINT ["mcp-atlassian"]
CMD ["--transport", "streamable-http", "--host", "0.0.0.0", "--port", "8000", "--path", "/mcp", "--toolsets", "all"]
