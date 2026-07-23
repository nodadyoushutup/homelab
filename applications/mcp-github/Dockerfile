FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:ce037447191eeed517faa80640539dedaffb79a3ec107bfd23625a4438b0d06d

COPY --from=ghcr.io/github/github-mcp-server:latest@sha256:2763823c63bcca718ce53850a1d7fcf2f501ec84028394f1b63ce7e9f4f9be28 /server/github-mcp-server /usr/local/bin/github-mcp-server
COPY entrypoint.sh /usr/local/bin/mcp-github-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-github-entrypoint /usr/local/bin/github-mcp-server

EXPOSE 8082
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-github-entrypoint"]
