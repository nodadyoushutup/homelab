FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:644ae2eec70fccba8a1b49d75172bd6b298860aa8bbeae708ab2ab0b3bf88da8

COPY --from=ghcr.io/github/github-mcp-server:latest@sha256:2b0c48b070f61e9d3969269ead600f62d00fb237b60ac849ef3d166ee7de9ad3 /server/github-mcp-server /usr/local/bin/github-mcp-server
COPY entrypoint.sh /usr/local/bin/mcp-github-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-github-entrypoint /usr/local/bin/github-mcp-server

EXPOSE 8082
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-github-entrypoint"]
