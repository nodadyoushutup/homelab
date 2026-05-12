from __future__ import annotations

import os
from typing import Any

SUPPORTED_EMBEDDING_PROVIDERS = ("google", "openai", "anthropic")


def embedding_provider() -> str:
    provider = (os.getenv("RAG_EMBEDDING_PROVIDER") or "google").strip().lower()
    if provider not in SUPPORTED_EMBEDDING_PROVIDERS:
        raise RuntimeError(
            "RAG_EMBEDDING_PROVIDER must be one of "
            f"{', '.join(SUPPORTED_EMBEDDING_PROVIDERS)}"
        )
    return provider


def default_embedding_model(provider: str | None = None) -> str:
    selected = (provider or embedding_provider()).strip().lower()
    if selected == "google":
        return "gemini-embedding-001"
    if selected == "openai":
        return "text-embedding-3-small"
    if selected == "anthropic":
        return "voyage-3.5"
    raise RuntimeError(f"unsupported embedding provider: {selected}")


def embedding_model(provider: str | None = None) -> str:
    selected = (provider or embedding_provider()).strip().lower()
    configured = (os.getenv("RAG_EMBEDDING_MODEL") or "").strip()
    return configured or default_embedding_model(selected)


def embedding_dimensions_label(provider: str | None = None) -> str:
    selected = (provider or embedding_provider()).strip().lower()
    if selected == "openai":
        return (os.getenv("RAG_OPENAI_EMBEDDING_DIMENSIONS") or "").strip()
    if selected == "anthropic":
        return (os.getenv("RAG_ANTHROPIC_EMBEDDING_DIMENSIONS") or "").strip()
    return ""


def build_embedding_client(provider: str | None = None) -> Any:
    selected = (provider or embedding_provider()).strip().lower()
    if selected == "google":
        from embeddings import google_genai as embed_google

        return embed_google.build_genai_client()
    if selected == "openai":
        from embeddings import openai_client as embed_openai

        return embed_openai.build_openai_client()
    if selected == "anthropic":
        from embeddings import anthropic_client as embed_anthropic

        return embed_anthropic.build_anthropic_client()
    raise RuntimeError(f"unsupported embedding provider: {selected}")


def embed_batch(
    client: Any,
    model: str,
    texts: list[str],
    *,
    provider: str | None = None,
    input_type: str | None = None,
) -> list[list[float]]:
    selected = (provider or embedding_provider()).strip().lower()
    if selected == "google":
        from embeddings import google_genai as embed_google

        return embed_google.embed_batch(client, model, texts)
    if selected == "openai":
        from embeddings import openai_client as embed_openai

        return embed_openai.embed_batch(client, model, texts)
    if selected == "anthropic":
        from embeddings import anthropic_client as embed_anthropic

        return embed_anthropic.embed_batch(client, model, texts, input_type=input_type)
    raise RuntimeError(f"unsupported embedding provider: {selected}")


def build_genai_client() -> Any:
    """Backward-compatible alias for older callers."""
    return build_embedding_client()
