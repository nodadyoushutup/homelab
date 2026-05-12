from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from embeddings import openai_client as embed_openai  # noqa: E402
from embeddings import providers as embeddings  # noqa: E402


class ProviderConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self._patch = mock.patch.dict(os.environ, {}, clear=False)
        self._patch.start()
        for key in (
            "RAG_EMBEDDING_PROVIDER",
            "RAG_EMBEDDING_MODEL",
            "RAG_OPENAI_EMBEDDING_DIMENSIONS",
        ):
            os.environ.pop(key, None)
        self.addCleanup(self._patch.stop)

    def test_default_provider_stays_google(self) -> None:
        self.assertEqual(embeddings.embedding_provider(), "google")
        self.assertEqual(embeddings.embedding_model(), "gemini-embedding-001")

    def test_openai_provider_default_model(self) -> None:
        os.environ["RAG_EMBEDDING_PROVIDER"] = "openai"
        self.assertEqual(embeddings.embedding_provider(), "openai")
        self.assertEqual(embeddings.embedding_model(), "text-embedding-3-small")


class _FakeEmbeddingItem:
    def __init__(self, index: int, embedding: list[float]) -> None:
        self.index = index
        self.embedding = embedding


class _FakeEmbeddings:
    def __init__(self) -> None:
        self.kwargs: dict | None = None

    def create(self, **kwargs):
        self.kwargs = kwargs
        return type(
            "Response",
            (),
            {
                "data": [
                    _FakeEmbeddingItem(1, [2.0, 2.1]),
                    _FakeEmbeddingItem(0, [1.0, 1.1]),
                ]
            },
        )()


class _FakeOpenAIClient:
    def __init__(self) -> None:
        self.embeddings = _FakeEmbeddings()


class OpenAIEmbedTests(unittest.TestCase):
    def test_openai_batch_preserves_input_order_from_indices(self) -> None:
        client = _FakeOpenAIClient()
        with mock.patch.dict(os.environ, {"RAG_OPENAI_EMBEDDING_DIMENSIONS": "512"}):
            vectors = embed_openai.embed_batch(client, "text-embedding-3-small", ["a", "b"])
        self.assertEqual(vectors, [[1.0, 1.1], [2.0, 2.1]])
        assert client.embeddings.kwargs is not None
        self.assertEqual(client.embeddings.kwargs["dimensions"], 512)
        self.assertEqual(client.embeddings.kwargs["encoding_format"], "float")


if __name__ == "__main__":
    unittest.main()
