#!/bin/sh
# Dev entry: run from bind-mounted upstream checkout when present; otherwise use image binary.
set -eu

if [ -f /src/Cargo.toml ]; then
  cd /src
  exec cargo run --release --locked
fi

exec qbittorrent-metrics-exporter "$@"
