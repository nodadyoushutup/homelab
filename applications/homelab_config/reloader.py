"""Lightweight file-watching hot reloader for development.

When a watched source file changes, the process restarts itself in place with
``os.execv`` (re-running ``python -m homelab_config``). Restarting in place
preserves the PID and avoids the parent/child process split (and orphaned port)
that werkzeug's subprocess reloader would introduce. Polling-based watching works
over container bind mounts where inotify may not propagate host edits.
"""

from __future__ import annotations

import fcntl
import logging
import os
import sys
import threading
import time
from collections.abc import Iterable
from pathlib import Path

logger = logging.getLogger(__name__)

_WATCH_SUFFIXES = (".py", ".html", ".js", ".css")
_POLL_INTERVAL_SECONDS = 0.5


def _iter_files(roots: list[Path]) -> Iterable[Path]:
    """Yield watchable source files under the given roots."""
    for root in roots:
        if root.is_file():
            if root.suffix in _WATCH_SUFFIXES:
                yield root
            continue
        for path in root.rglob("*"):
            if path.suffix in _WATCH_SUFFIXES and path.is_file():
                yield path


def _snapshot(roots: list[Path]) -> dict[Path, float]:
    """Return a mapping of watched file paths to their modification times."""
    snapshot: dict[Path, float] = {}
    for path in _iter_files(roots):
        try:
            snapshot[path] = path.stat().st_mtime
        except OSError:
            continue
    return snapshot


def _mark_open_fds_cloexec() -> None:
    """Mark all non-stdio fds close-on-exec so ``execv`` releases them.

    The werkzeug listening socket is inheritable, so without this the bound
    socket would survive ``execv`` and the reloaded process would fail to
    rebind with "Address already in use". Setting ``FD_CLOEXEC`` lets the kernel
    close these fds atomically during ``execve`` (no race with the still-running
    server thread), while stdin/stdout/stderr are preserved for logging.
    """
    try:
        fd_names = os.listdir("/proc/self/fd")
    except OSError:
        return
    for name in fd_names:
        try:
            fd = int(name)
        except ValueError:
            continue
        if fd <= 2:
            continue
        try:
            flags = fcntl.fcntl(fd, fcntl.F_GETFD)
            fcntl.fcntl(fd, fcntl.F_SETFD, flags | fcntl.FD_CLOEXEC)
        except OSError:
            continue


def _restart() -> None:
    """Restart the current process in place, preserving the PID."""
    sys.stdout.flush()
    sys.stderr.flush()
    _mark_open_fds_cloexec()
    os.execv(sys.executable, [sys.executable, *sys.argv])


def _watch(roots: list[Path]) -> None:
    """Poll watched files and restart the process when any changes."""
    known = _snapshot(roots)
    while True:
        time.sleep(_POLL_INTERVAL_SECONDS)
        current = _snapshot(roots)
        changed = [path for path, mtime in current.items() if known.get(path) != mtime]
        removed = [path for path in known if path not in current]
        if changed or removed:
            trigger = (changed or removed)[0]
            logger.info(
                "Change detected (%s); reloading homelab-config", trigger.name
            )
            _restart()
        known = current


def start_reloader(roots: Iterable[Path]) -> None:
    """Start the background hot-reload watcher.

    Args:
        roots: Files and directories to watch for changes.
    """
    watched = [Path(root) for root in roots]
    thread = threading.Thread(
        target=_watch,
        args=(watched,),
        name="homelab-config-reloader",
        daemon=True,
    )
    thread.start()
    logger.info(
        "Hot reload enabled; watching %d path(s) for changes", len(watched)
    )


__all__ = ["start_reloader"]
