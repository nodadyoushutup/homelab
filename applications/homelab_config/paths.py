"""Filesystem paths for the homelab-config application."""

from __future__ import annotations

from pathlib import Path

# applications/homelab_config/paths.py -> applications/homelab_config
#   -> applications -> repo root
APP_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = APP_DIR.parents[1]

CONFIG_DIR = PROJECT_ROOT / ".config"
# Live Docker Swarm topology (config-id: docker/swarm) generated from the UI.
SWARM_YAML = CONFIG_DIR / "docker" / "swarm.yaml"

# Runtime state lives under data/ (git-ignored) so it never pollutes the tree.
DATA_DIR = PROJECT_ROOT / "data" / "homelab-config"
DATABASE_PATH = DATA_DIR / "homelab_config.sqlite3"

REQUIREMENTS = APP_DIR / "requirements.txt"

DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8770
