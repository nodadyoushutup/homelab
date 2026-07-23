FROM ghcr.io/lanbaoshen/mcp-jenkins:3.4.0@sha256:fa258bea42564a5f284e55df82bb21024d493987676e6fb806d59c56da627aad

COPY --chmod=0755 entrypoint.sh /usr/local/bin/mcp-jenkins-entrypoint

EXPOSE 9887
ENTRYPOINT ["/usr/local/bin/mcp-jenkins-entrypoint"]
