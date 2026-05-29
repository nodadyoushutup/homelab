"""Runtime configuration entrypoints."""

from __future__ import annotations

from torrent_manager.config_loader import Config, load_config, resolve_config_path

__all__ = ["Config", "load_config", "resolve_config_path"]
