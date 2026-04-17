FROM hashicorp/terraform-mcp-server:0.5.1@sha256:0a9656fdc598d1ba3509752ff2a0ff6336a5238cf8bbf1f134805acefdf99762 AS upstream

FROM alpine:3.22

RUN apk add --no-cache ca-certificates catatonit \
  && addgroup -S app -g 65532 \
  && adduser -S -D -H -u 65532 -G app app

COPY --from=upstream /bin/terraform-mcp-server /bin/terraform-mcp-server

USER 65532:65532

EXPOSE 8080
ENTRYPOINT ["catatonit", "--", "/bin/terraform-mcp-server"]
