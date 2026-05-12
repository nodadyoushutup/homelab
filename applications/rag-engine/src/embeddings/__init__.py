"""Embedding provider configuration and batch embedding calls."""

from embeddings.providers import (
    SUPPORTED_EMBEDDING_PROVIDERS,
    build_embedding_client,
    build_genai_client,
    default_embedding_model,
    embed_batch,
    embedding_dimensions_label,
    embedding_model,
    embedding_provider,
)

__all__ = [
    "SUPPORTED_EMBEDDING_PROVIDERS",
    "build_embedding_client",
    "build_genai_client",
    "default_embedding_model",
    "embed_batch",
    "embedding_dimensions_label",
    "embedding_model",
    "embedding_provider",
]
