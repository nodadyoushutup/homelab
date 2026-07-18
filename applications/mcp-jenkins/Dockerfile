FROM ghcr.io/lanbaoshen/mcp-jenkins:3.1.1@sha256:0a647e292d32230bbcd90c1c1f217f058a2d6f6b282db84e403a23c828b85bbf

COPY --chmod=0755 entrypoint.sh /usr/local/bin/mcp-jenkins-entrypoint

EXPOSE 9887
ENTRYPOINT ["/usr/local/bin/mcp-jenkins-entrypoint"]
