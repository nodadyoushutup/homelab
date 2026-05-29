"""YAML config loader tests."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from torrent_manager.config_loader import load_config, resolve_config_path  # noqa: E402
from torrent_manager.qbittorrent_settings import normalize_base_url  # noqa: E402


class ConfigLoaderTests(unittest.TestCase):
    def test_normalize_base_url_adds_scheme(self) -> None:
        self.assertEqual(normalize_base_url("192.168.1.100:8080"), "http://192.168.1.100:8080")

    def test_load_config_from_yaml_file(self) -> None:
        yaml_text = """
app:
  secret_key: test-secret
  database_url: "sqlite:///:memory:"
  debug: true
qbittorrent:
  defaults:
    username: admin
    password: shared-secret
  clients:
    - id: movie_0
      base_url: http://movie-0:8080
    - id: television_1
      base_url: http://tv-1:8080
      password: override
"""
        with tempfile.TemporaryDirectory() as tmp:
            config_path = Path(tmp) / "config.yaml"
            config_path.write_text(yaml_text, encoding="utf-8")
            settings = load_config(path=config_path)

        self.assertEqual(settings.secret_key, "test-secret")
        self.assertTrue(settings.debug)
        self.assertEqual(len(settings.qbittorrent_clients), 2)
        self.assertEqual(settings.qbittorrent_clients[0].password, "shared-secret")
        self.assertEqual(settings.qbittorrent_clients[1].password, "override")

    def test_resolve_bundled_default(self) -> None:
        path = resolve_config_path()
        self.assertTrue(path.is_file())
        settings = load_config(path=path)
        self.assertEqual(settings.database_url, "sqlite:////data/torrent-manager.db")


if __name__ == "__main__":
    unittest.main()
