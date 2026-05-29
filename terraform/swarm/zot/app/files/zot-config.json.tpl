{
  "distSpecVersion": "1.1.0-dev",
  "storage": {
    "rootDirectory": "/var/lib/registry",
    "commit": true,
    "gc": true,
    "gcDelay": "1h",
    "gcInterval": "24h"
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000",
    "realm": "zot",
    "compat": ["docker2s2"]%{ if auth_enabled ~},
    "auth": {
      "htpasswd": {
        "path": "/etc/zot/htpasswd"
      },
      "failDelay": 2
    },
    "accessControl": {
      "repositories": {
        "**": {
          "defaultPolicy": ["read", "create", "update", "delete"]
        }
      }
    }%{ endif ~}
  },
  "log": {
    "level": "info"
  },
  "extensions": {
    "ui": {
      "enable": true
    },
    "search": {
      "enable": true
    },
    "mgmt": {
      "enable": true
    }
  }
}
