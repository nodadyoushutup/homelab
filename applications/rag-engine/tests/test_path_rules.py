import os
import unittest

from ingest.path_rules import (
    DEFAULT_RAG_EXCLUDE_FILE_SUFFIXES,
    DEFAULT_RAG_EXCLUDE_PATH_SEGMENTS,
    file_has_excluded_suffix,
    load_exclude_segments,
    load_exclude_suffixes,
    path_has_excluded_segment,
)


class PathRulesDefaultsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._saved = {
            "RAG_EXCLUDE_PATH_SEGMENTS": os.environ.pop("RAG_EXCLUDE_PATH_SEGMENTS", None),
            "RAG_EXCLUDE_FILE_SUFFIXES": os.environ.pop("RAG_EXCLUDE_FILE_SUFFIXES", None),
        }

    def tearDown(self) -> None:
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_load_exclude_segments_defaults_when_unset(self) -> None:
        segments = load_exclude_segments()
        self.assertIn("node_modules", segments)
        self.assertIn("__pycache__", segments)
        self.assertEqual(
            ",".join(sorted(segments)),
            ",".join(
                sorted(
                    x.strip()
                    for x in DEFAULT_RAG_EXCLUDE_PATH_SEGMENTS.split(",")
                    if x.strip()
                )
            ),
        )

    def test_load_exclude_suffixes_defaults_when_unset(self) -> None:
        suffixes = load_exclude_suffixes()
        self.assertIn(".png", suffixes)
        self.assertIn(".tfstate", suffixes)
        self.assertEqual(
            suffixes,
            tuple(
                p.strip().lower() if p.strip().startswith(".") else f".{p.strip().lower()}"
                for p in DEFAULT_RAG_EXCLUDE_FILE_SUFFIXES.split(",")
                if p.strip()
            ),
        )

    def test_defaults_exclude_known_paths(self) -> None:
        self.assertTrue(path_has_excluded_segment("applications/foo/node_modules/bar.py"))
        self.assertTrue(file_has_excluded_suffix("docs/image.png"))


if __name__ == "__main__":
    unittest.main()
