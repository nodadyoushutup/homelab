import os
import unittest

from ingest.path_rules import (
    DEFAULT_RAG_PATHS_DISALLOWED,
    file_has_excluded_suffix,
    load_disallowed_segments,
    load_ignored_extensions,
    path_has_disallowed_segment,
)


class PathRulesDefaultsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._saved = {
            "RAG_PATHS_DISALLOWED": os.environ.pop("RAG_PATHS_DISALLOWED", None),
            "RAG_EXTENSIONS_IGNORE": os.environ.pop("RAG_EXTENSIONS_IGNORE", None),
        }

    def tearDown(self) -> None:
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_load_disallowed_segments_defaults_when_unset(self) -> None:
        segments = load_disallowed_segments()
        self.assertIn("node_modules", segments)
        self.assertIn("__pycache__", segments)
        self.assertEqual(
            ",".join(sorted(segments)),
            ",".join(
                sorted(
                    x.strip()
                    for x in DEFAULT_RAG_PATHS_DISALLOWED.split(",")
                    if x.strip()
                )
            ),
        )

    def test_load_disallowed_segments_parses_env(self) -> None:
        os.environ["RAG_PATHS_DISALLOWED"] = "venv,custom-cache"
        self.assertEqual(load_disallowed_segments(), frozenset({"venv", "custom-cache"}))

    def test_load_ignored_extensions_empty_when_unset(self) -> None:
        self.assertEqual(load_ignored_extensions(), ())

    def test_load_ignored_extensions_parses_env(self) -> None:
        os.environ["RAG_EXTENSIONS_IGNORE"] = ".png,iso,.QCOW2"
        self.assertEqual(load_ignored_extensions(), (".png", ".iso", ".qcow2"))

    def test_defaults_exclude_known_paths(self) -> None:
        self.assertTrue(path_has_disallowed_segment("applications/foo/node_modules/bar.py"))
        self.assertTrue(path_has_disallowed_segment("applications/foo/.venv/lib/site.py"))
        self.assertTrue(path_has_disallowed_segment("applications/langgraph/.langgraph_api/checkpoints/x"))
        self.assertTrue(path_has_disallowed_segment(".config/docker/rag.env"))
        self.assertFalse(path_has_disallowed_segment("applications/foo/src/main.py"))
        os.environ["RAG_EXTENSIONS_IGNORE"] = ".png,.iso,.qcow2"
        self.assertTrue(file_has_excluded_suffix("docs/image.png"))
        self.assertTrue(file_has_excluded_suffix("packer/output/ubuntu.qcow2"))
        self.assertTrue(file_has_excluded_suffix("data/images/install.iso"))
        self.assertFalse(file_has_excluded_suffix("docs/readme.md"))


if __name__ == "__main__":
    unittest.main()
