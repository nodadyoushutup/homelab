FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:ce037447191eeed517faa80640539dedaffb79a3ec107bfd23625a4438b0d06d

COPY --from=ghcr.io/github/github-mcp-server:latest@sha256:c491ffdf6f4c85cb5397021bc655edb8ab825c6f5f568e7597d77a1bd7c4d308 /server/github-mcp-server /usr/local/bin/github-mcp-server
COPY entrypoint.sh /usr/local/bin/mcp-github-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-github-entrypoint /usr/local/bin/github-mcp-server

EXPOSE 8082
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-github-entrypoint"]
