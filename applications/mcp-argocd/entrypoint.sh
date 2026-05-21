#!/bin/sh
set -eu

if [ "${ARGOCD_INSECURE_SKIP_VERIFY:-false}" = "true" ]; then
  export NODE_TLS_REJECT_UNAUTHORIZED=0
fi

exec node dist/index.js http --port 3000 --stateless
