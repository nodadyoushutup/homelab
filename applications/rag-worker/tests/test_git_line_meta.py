"""Tests for ``rag_worker.git_line_meta``."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from rag_worker import git_line_meta  # noqa: E402


class TestLineRangeApplicable(unittest.TestCase):
    def test_code_languages(self) -> None:
        for lang in ("python", "xml", "markdown", "json", "go", "rust"):
            with self.subTest(lang=lang):
                self.assertTrue(git_line_meta.line_range_git_applicable(lang))

    def test_skipped_languages(self) -> None:
        for lang in ("pdf", "docx", "pptx", "odt", "csv", "xlsx"):
            with self.subTest(lang=lang):
                self.assertFalse(git_line_meta.line_range_git_applicable(lang))


class TestParseFormatOutput(unittest.TestCase):
    def test_parses_null_separated(self) -> None:
        sha = "a" * 40
        raw = f"{sha}\x00Jane Doe\x002026-01-02T03:04:05+00:00"
        out = git_line_meta._parse_format_output(raw)
        self.assertIsNotNone(out)
        assert out is not None
        self.assertEqual(out["git_last_commit"], sha)
        self.assertEqual(out["git_last_author"], "Jane Doe")
        self.assertEqual(out["git_last_timestamp"], "2026-01-02T03:04:05+00:00")

    def test_empty(self) -> None:
        self.assertIsNone(git_line_meta._parse_format_output(""))
        self.assertIsNone(git_line_meta._parse_format_output("not\x00enough"))


class TestEnrichChunkGitMetadata(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path("/workspace")

    @mock.patch.object(git_line_meta, "path_tracked_in_git", return_value=False)
    def test_untracked_noop(self, _m: mock.MagicMock) -> None:
        rows = [{}]
        git_line_meta.enrich_chunk_git_metadata(
            self.repo, "foo.py", None, rows, eff_strategy="char"
        )
        self.assertEqual(rows, [{}])

    @mock.patch.object(git_line_meta, "path_tracked_in_git", return_value=True)
    @mock.patch.object(git_line_meta, "last_commit_touching_file")
    def test_char_uses_file_level(self, m_file: mock.MagicMock, _t: mock.MagicMock) -> None:
        m_file.return_value = {
            "git_last_commit": "b" * 40,
            "git_last_author": "A",
            "git_last_timestamp": "2026-01-01T00:00:00Z",
        }
        rows = [{}, {}]
        git_line_meta.enrich_chunk_git_metadata(
            self.repo, "x.txt", None, rows, eff_strategy="char"
        )
        self.assertEqual(rows[0], m_file.return_value)
        self.assertEqual(rows[1], m_file.return_value)
        m_file.assert_called_once()

    @mock.patch.object(git_line_meta, "path_tracked_in_git", return_value=True)
    @mock.patch.object(git_line_meta, "last_commit_touching_line_range")
    @mock.patch.object(git_line_meta, "last_commit_touching_file")
    def test_python_chunk_uses_line_range(
        self, m_file: mock.MagicMock, m_range: mock.MagicMock, _t: mock.MagicMock
    ) -> None:
        span = {"git_last_commit": "c" * 40, "git_last_author": "B", "git_last_timestamp": "2026-02-02T00:00:00Z"}
        m_range.return_value = span
        chunk = mock.Mock(language="python", start_line=10, end_line=20)
        rows: list[dict] = [{}]
        git_line_meta.enrich_chunk_git_metadata(
            self.repo, "m.py", [chunk], rows, eff_strategy="ast_py"
        )
        self.assertEqual(rows[0], span)
        m_range.assert_called_once_with(mock.ANY, "m.py", 10, 20)
        m_file.assert_not_called()

    @mock.patch.object(git_line_meta, "path_tracked_in_git", return_value=True)
    @mock.patch.object(git_line_meta, "last_commit_touching_line_range", return_value=None)
    @mock.patch.object(git_line_meta, "last_commit_touching_file")
    def test_line_range_fallback_file(
        self, m_file: mock.MagicMock, _r: mock.MagicMock, _t: mock.MagicMock
    ) -> None:
        fl = {"git_last_commit": "d" * 40, "git_last_author": "C", "git_last_timestamp": "2026-03-03T00:00:00Z"}
        m_file.return_value = fl
        chunk = mock.Mock(language="python", start_line=1, end_line=5)
        rows = [{}]
        git_line_meta.enrich_chunk_git_metadata(
            self.repo, "m.py", [chunk], rows, eff_strategy="ast_py"
        )
        self.assertEqual(rows[0], fl)

    @mock.patch.object(git_line_meta, "path_tracked_in_git", return_value=True)
    @mock.patch.object(git_line_meta, "last_commit_touching_file")
    def test_pdf_language_uses_file_only(self, m_file: mock.MagicMock, _t: mock.MagicMock) -> None:
        fl = {"git_last_commit": "e" * 40, "git_last_author": "D", "git_last_timestamp": "2026-04-04T00:00:00Z"}
        m_file.return_value = fl
        chunk = mock.Mock(language="pdf", start_line=3, end_line=3)
        rows = [{}]
        git_line_meta.enrich_chunk_git_metadata(
            self.repo, "x.pdf", [chunk], rows, eff_strategy="pdf_hybrid"
        )
        self.assertEqual(rows[0], fl)


if __name__ == "__main__":
    unittest.main()
