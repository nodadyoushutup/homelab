ARG MCP_ATLASSIAN_UPSTREAM_IMAGE=ghcr.io/sooperset/mcp-atlassian:latest@sha256:6c4f96725b0e775a014a0b3016d358efdab58efd57c37ad7c2050136545b0e00
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
