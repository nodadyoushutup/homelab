"""Module entrypoint: ``python -m homelab_config``.

Used as the container command and re-run in place by the hot reloader's
``os.execv`` of the same argv.
"""

from __future__ import annotations

from homelab_config.launcher import main

if __name__ == "__main__":
    raise SystemExit(main())
