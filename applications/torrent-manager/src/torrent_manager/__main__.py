"""CLI entrypoints for local development and container healthchecks."""

from __future__ import annotations

import sys
import urllib.error
import urllib.request

from torrent_manager.app import create_app
from torrent_manager.config import load_config


def _healthcheck(url: str) -> int:
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status != 200:
                print(f"unexpected status: {response.status}", file=sys.stderr)
                return 1
    except urllib.error.URLError as exc:
        print(f"healthcheck failed: {exc}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    """Run the development server or a healthcheck."""
    args = list(argv or sys.argv[1:])
    if not args:
        args = ["serve"]

    command = args[0]
    if command == "healthcheck":
        host = "127.0.0.1"
        port = "8080"
        for arg in args[1:]:
            if arg.startswith("--host="):
                host = arg.split("=", 1)[1]
            elif arg.startswith("--port="):
                port = arg.split("=", 1)[1]
        return _healthcheck(f"http://{host}:{port}/healthz")

    if command == "serve":
        settings = load_config()
        app = create_app(settings)
        app.run(
            host="0.0.0.0",
            port=int(__import__("os").getenv("PORT", "8080")),
            debug=settings.debug,
        )
        return 0

    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
