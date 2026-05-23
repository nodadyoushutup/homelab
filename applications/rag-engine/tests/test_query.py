from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from retrieve.query import run_query, top_k


class _FakeCollection:
    def __init__(self) -> None:
        self.last_n_results: int | None = None

    def query(self, **kwargs):
        self.last_n_results = kwargs.get("n_results")
        n = self.last_n_results or 0
        return {
            "ids": [["id-1"]],
            "documents": [["doc"]],
            "metadatas": [[{"path": "docs/x.md"}]],
            "distances": [[0.1]],
        }


class TopKTests(unittest.TestCase):
    def test_top_k_default(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(top_k(), 20)

    def test_top_k_from_env(self) -> None:
        with patch.dict(os.environ, {"RAG_TOP_K": "12"}, clear=True):
            self.assertEqual(top_k(), 12)

    @patch("retrieve.query.embed_batch", return_value=[[0.1, 0.2]])
    @patch("retrieve.query.embedding_provider", return_value="openai")
    def test_run_query_uses_rag_top_k(self, _provider, _embed) -> None:
        coll = _FakeCollection()
        with patch.dict(os.environ, {"RAG_TOP_K": "7"}, clear=True):
            result = run_query(
                coll,
                object(),
                query_text="hello",
                embedding_model="text-embedding-3-small",
            )
        self.assertEqual(coll.last_n_results, 7)
        self.assertEqual(result["top_k"], 1)


if __name__ == "__main__":
    unittest.main()
