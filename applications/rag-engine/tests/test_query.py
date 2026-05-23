from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from retrieve.query import (
    merge_where,
    path_prefix_where,
    resolve_query_k,
    run_query,
    top_k,
)


class _FakeCollection:
    def __init__(self) -> None:
        self.last_n_results: int | None = None
        self.last_where: dict | None = None

    def query(self, **kwargs):
        self.last_n_results = kwargs.get("n_results")
        self.last_where = kwargs.get("where")
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

    def test_resolve_query_k_defaults_and_caps(self) -> None:
        with patch.dict(os.environ, {"RAG_TOP_K": "20", "RAG_QUERY_K_MAX": "50"}, clear=True):
            self.assertEqual(resolve_query_k(None), 20)
            self.assertEqual(resolve_query_k(30), 30)
            self.assertEqual(resolve_query_k(100), 50)
            self.assertEqual(resolve_query_k(0), 20)

    def test_path_prefix_where_normalizes(self) -> None:
        self.assertEqual(
            path_prefix_where("/docs/subagents/code/"),
            {"path": {"$contains": "docs/subagents/code/"}},
        )
        self.assertIsNone(path_prefix_where("   "))

    def test_merge_where_combines_prefix_with_existing_filter(self) -> None:
        merged = merge_where({"language": "python"}, "applications/rag-engine/")
        self.assertEqual(
            merged,
            {
                "$and": [
                    {"language": "python"},
                    {"path": {"$contains": "applications/rag-engine/"}},
                ]
            },
        )

    @patch("retrieve.query.embed_batch", return_value=[[0.1, 0.2]])
    @patch("retrieve.query.embedding_provider", return_value="openai")
    def test_run_query_applies_path_prefix_and_k(self, _provider, _embed) -> None:
        coll = _FakeCollection()
        with patch.dict(os.environ, {"RAG_TOP_K": "20", "RAG_QUERY_K_MAX": "50"}, clear=True):
            run_query(
                coll,
                object(),
                query_text="hello",
                embedding_model="text-embedding-3-small",
                path_prefix="docs/workflows/",
                k=35,
            )
        self.assertEqual(coll.last_n_results, 35)
        self.assertEqual(
            coll.last_where,
            {"path": {"$contains": "docs/workflows/"}},
        )


if __name__ == "__main__":
    unittest.main()
