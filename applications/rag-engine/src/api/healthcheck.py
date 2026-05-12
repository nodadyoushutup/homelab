from __future__ import annotations

import sys
import urllib.error
import urllib.request


def main() -> None:
    try:
        urllib.request.urlopen("http://127.0.0.1:8080/healthz", timeout=5)
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            sys.exit(0)
        raise
    except OSError:
        raise


if __name__ == "__main__":
    main()
