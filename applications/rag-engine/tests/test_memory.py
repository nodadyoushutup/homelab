"""Logic-level smoke tests for the ``memory`` package.

Uses stdlib ``unittest`` (no new deps) and mocks the Chroma collection + Gemini client so
tests run without external services. Real cross-stack integration is covered by Phase 6
golden scenarios.

Run from ``applications/rag-engine/``::

    ./.venv/bin/python -m unittest discover -s tests -v
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import memory  # noqa: E402


class _FakeGenAIClient:
    """Stand-in embedding client; ``embed_batch`` is patched directly so this
    class only exists so the type hint passes when constructed."""


def _fake_embed(_client, _model, texts, **_kwargs):
    return [[float(len(t)), 1.0, 2.0] for t in texts]


class _FakeCollection:
    """In-memory stand-in for the Chroma collection surface ``memory.py`` uses."""

    def __init__(self) -> None:
        self.rows: dict[str, dict[str, Any]] = {}
        self.next_query_distance: float = 0.5

    def add(self, *, ids, embeddings, documents, metadatas):
        for i, rid in enumerate(ids):
            self.rows[rid] = {
                "embedding": embeddings[i],
                "document": documents[i],
                "metadata": dict(metadatas[i]),
            }

    def update(self, *, ids, metadatas=None, documents=None, embeddings=None):
        for i, rid in enumerate(ids):
            if rid not in self.rows:
                continue
            row = self.rows[rid]
            if metadatas is not None:
                row["metadata"] = dict(metadatas[i])
            if documents is not None:
                row["document"] = documents[i]
            if embeddings is not None:
                row["embedding"] = embeddings[i]

    def delete(self, *, ids=None, where=None):
        if ids:
            for rid in ids:
                self.rows.pop(rid, None)
            return
        if where:
            to_delete = [rid for rid, row in self.rows.items() if _matches_where(row["metadata"], where)]
            for rid in to_delete:
                self.rows.pop(rid, None)

    def get(self, *, ids=None, where=None, include=None, limit=None, offset=None):
        if ids:
            present = [rid for rid in ids if rid in self.rows]
            rids = present
        elif where:
            rids = [rid for rid, row in self.rows.items() if _matches_where(row["metadata"], where)]
        else:
            rids = list(self.rows.keys())
        if isinstance(limit, int) and limit >= 0:
            rids = rids[:limit]
        return {
            "ids": rids,
            "metadatas": [self.rows[rid]["metadata"] for rid in rids],
            "documents": [self.rows[rid]["document"] for rid in rids],
        }

    def query(self, *, query_embeddings, n_results, where=None, include=None):
        rids = list(self.rows.keys())
        if where is not None:
            rids = [rid for rid in rids if _matches_where(self.rows[rid]["metadata"], where)]
        if not rids:
            return {"ids": [[]], "documents": [[]], "metadatas": [[]], "distances": [[]]}
        first = rids[0]
        return {
            "ids": [[first]],
            "documents": [[self.rows[first]["document"]]],
            "metadatas": [[self.rows[first]["metadata"]]],
            "distances": [[self.next_query_distance]],
        }


def _matches_where(meta: dict[str, Any], where: dict[str, Any]) -> bool:
    """Tiny subset of Chroma where syntax used by memory.py."""
    if "$and" in where:
        return all(_matches_where(meta, sub) for sub in where["$and"])
    if "$or" in where:
        return any(_matches_where(meta, sub) for sub in where["$or"])
    for key, expected in where.items():
        actual = meta.get(key)
        if isinstance(expected, dict):
            if "$eq" in expected and actual != expected["$eq"]:
                return False
            if "$ne" in expected and actual == expected["$ne"]:
                return False
            if "$in" in expected and actual not in expected["$in"]:
                return False
            if "$nin" in expected and actual in expected["$nin"]:
                return False
            if "$gt" in expected and not (isinstance(actual, (int, float)) and actual > expected["$gt"]):
                return False
            if "$gte" in expected and not (isinstance(actual, (int, float)) and actual >= expected["$gte"]):
                return False
            if "$lt" in expected and not (isinstance(actual, (int, float)) and actual < expected["$lt"]):
                return False
            if "$lte" in expected and not (isinstance(actual, (int, float)) and actual <= expected["$lte"]):
                return False
        else:
            if actual != expected:
                return False
    return True


class PureLogicTests(unittest.TestCase):
    """Tests that do not touch Chroma or genai."""

    def test_id_format_and_uniqueness(self) -> None:
        a = memory._new_memory_id(memory.KIND_EPISODIC)
        b = memory._new_memory_id(memory.KIND_EPISODIC)
        self.assertNotEqual(a, b)
        self.assertTrue(a.startswith(f"memory:{memory.KIND_EPISODIC}:"))
        parts = a.split(":")
        self.assertEqual(len(parts), 4)
        self.assertEqual(len(parts[2]), 13)

    def test_normalize_cited_paths_dedup_and_strip(self) -> None:
        out = memory._normalize_cited_paths(["/a/b.py", "a/b.py", "  c.py  ", "", None, "c.py"])
        self.assertEqual(out, ["a/b.py", "c.py"])
        self.assertEqual(memory._normalize_cited_paths("a, /a, b"), ["a", "b"])
        self.assertEqual(memory._normalize_cited_paths(None), [])

    def test_iso_to_ts_roundtrip(self) -> None:
        iso = memory._ts_to_iso(1_700_000_000)
        ts = memory._parse_iso_to_ts(iso)
        self.assertEqual(ts, 1_700_000_000)
        self.assertEqual(memory._parse_iso_to_ts(""), 0)
        self.assertEqual(memory._parse_iso_to_ts("not a date"), 0)

    def test_validate_save_episodic_requires_failure_class(self) -> None:
        err = memory._validate_save(
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="t",
            body="b",
            cited_paths=["a/b.py"],
            failure_class="",
            failure_signature="",
            scope="",
        )
        self.assertIsNotNone(err)
        self.assertIn("failure_class", err or "")

    def test_validate_save_episodic_accepts_signature_without_paths(self) -> None:
        err = memory._validate_save(
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="t",
            body="b",
            cited_paths=[],
            failure_class="test",
            failure_signature="AssertionError: expected 1 got 2",
            scope="",
        )
        self.assertIsNone(err)

    def test_validate_save_kind_source_mismatch(self) -> None:
        err = memory._validate_save(
            kind=memory.KIND_DECLARATIVE,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="t",
            body="b",
            cited_paths=[],
            failure_class="",
            failure_signature="",
            scope="",
        )
        self.assertIsNotNone(err)
        self.assertIn("source=", err or "")

    def test_validate_save_declarative_scope_enum(self) -> None:
        err = memory._validate_save(
            kind=memory.KIND_DECLARATIVE,
            source=memory.SOURCE_USER_ASSERTION,
            title="t",
            body="b",
            cited_paths=[],
            failure_class="",
            failure_signature="",
            scope="bogus",
        )
        self.assertIsNotNone(err)

    def test_truncate_body(self) -> None:
        text = "a" * 100
        truncated, was_truncated = memory._truncate_body(text, 50)
        self.assertTrue(was_truncated)
        self.assertEqual(len(truncated), 50)
        same, no_trunc = memory._truncate_body("short", 50)
        self.assertEqual(same, "short")
        self.assertFalse(no_trunc)


class CollectionInteractionTests(unittest.TestCase):
    """Tests that mock the Chroma collection surface."""

    def setUp(self) -> None:
        self.epi = _FakeCollection()
        self.dec = _FakeCollection()
        self._patches = [
            mock.patch.object(memory, "chroma_memory_episodic_collection", return_value=self.epi),
            mock.patch.object(memory, "chroma_memory_declarative_collection", return_value=self.dec),
            mock.patch.object(memory, "embed_batch", side_effect=_fake_embed),
        ]
        for p in self._patches:
            p.start()
        self.addCleanup(self._stop_patches)
        os.environ["RAG_MEMORY_DEDUP_DISTANCE_MAX"] = "0.05"
        os.environ["RAG_MEMORY_RECALL_MAX_K"] = "3"
        os.environ["RAG_MEMORY_EPISODIC_TTL_DAYS"] = "30"

    def _stop_patches(self) -> None:
        for p in self._patches:
            p.stop()

    def test_save_episodic_creates_new_when_no_dedup_match(self) -> None:
        self.epi.next_query_distance = 0.9  # far from any neighbor
        result = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="auth header missing",
            body="Set x-odoo-user before MCP call.",
            cited_paths=["applications/mcp-odoo/foo.py"],
            failure_class="mcp_call",
            failure_signature="401 Unauthorized",
            author="agent.code",
            commit="deadbeef",
        )
        self.assertEqual(result["dedup"]["action"], "created")
        self.assertEqual(result["kind"], memory.KIND_EPISODIC)
        self.assertEqual(len(self.epi.rows), 1)
        meta = next(iter(self.epi.rows.values()))["metadata"]
        self.assertEqual(meta["source"], memory.SOURCE_FAILURE_RESOLUTION)
        self.assertEqual(meta["author"], "agent.code")
        self.assertEqual(meta["commit_at_write"], "deadbeef")
        self.assertGreater(meta["expires_at_ts"], 0)

    def test_save_episodic_merges_when_dedup_match(self) -> None:
        self.epi.next_query_distance = 0.9
        first = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="auth header missing",
            body="Set x-odoo-user.",
            cited_paths=["a.py"],
            failure_class="mcp_call",
            failure_signature="401",
        )
        self.assertEqual(first["dedup"]["action"], "created")
        self.epi.next_query_distance = 0.01  # within dedup threshold
        second = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="auth header missing again",
            body="Set x-odoo-user before MCP call. Longer body.",
            cited_paths=["b.py"],
            failure_class="mcp_call",
            failure_signature="401",
        )
        self.assertEqual(second["dedup"]["action"], "merged")
        self.assertEqual(second["id"], first["id"])
        self.assertEqual(len(self.epi.rows), 1)
        meta = self.epi.rows[first["id"]]["metadata"]
        self.assertEqual(meta["recall_count"], 1)
        self.assertEqual(set(meta["cited_paths"].split(",")), {"a.py", "b.py"})

    def test_save_user_assertion_into_declarative(self) -> None:
        self.dec.next_query_distance = 0.9
        result = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_DECLARATIVE,
            source=memory.SOURCE_USER_ASSERTION,
            title="QA on August 4th",
            body="Plan QA day.",
            scope="schedule",
            expires_at="2026-08-05T00:00:00Z",
            author="user.jh",
        )
        self.assertEqual(result["dedup"]["action"], "created")
        self.assertEqual(len(self.dec.rows), 1)
        self.assertEqual(len(self.epi.rows), 0)
        meta = next(iter(self.dec.rows.values()))["metadata"]
        self.assertTrue(meta["verified"])  # user-assertion → verified by default
        self.assertEqual(meta["scope"], "schedule")
        self.assertEqual(meta["expires_at"], "2026-08-05T00:00:00Z")

    def test_recall_increments_count_and_returns_payload_shape(self) -> None:
        self.epi.next_query_distance = 0.9
        save = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="auth header missing",
            body="Set x-odoo-user.",
            cited_paths=["a.py"],
            failure_class="mcp_call",
            failure_signature="401",
        )
        before = self.epi.rows[save["id"]]["metadata"]["recall_count"]
        self.epi.next_query_distance = 0.2
        result = memory.recall_memory(
            genai_client=_FakeGenAIClient(),
            query_text="MCP returned 401",
            k=2,
            kind=memory.KIND_EPISODIC,
        )
        self.assertGreaterEqual(result["top_k"], 1)
        hit = result["results"][0]
        for required in ("id", "kind", "source", "title", "body", "score", "age_days", "recall_count", "verified", "cited_paths"):
            self.assertIn(required, hit)
        after = self.epi.rows[save["id"]]["metadata"]["recall_count"]
        self.assertEqual(after, before + 1)

    def test_forget_by_id(self) -> None:
        self.epi.next_query_distance = 0.9
        save = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="t",
            body="b",
            cited_paths=["a.py"],
            failure_class="test",
            failure_signature="x",
        )
        self.assertEqual(len(self.epi.rows), 1)
        result = memory.forget_memory(ids=[save["id"]])
        self.assertEqual(result["deleted"], 1)
        self.assertEqual(len(self.epi.rows), 0)

    def test_sweep_removes_only_expired(self) -> None:
        self.epi.next_query_distance = 0.9
        save = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="t",
            body="b",
            cited_paths=["a.py"],
            failure_class="test",
            failure_signature="x",
        )
        self.epi.rows[save["id"]]["metadata"]["expires_at_ts"] = memory._now_ts() - 1
        result = memory.sweep_expired(dry_run=False, kinds=[memory.KIND_EPISODIC])
        self.assertEqual(result["deleted_total"], 1)
        self.assertEqual(len(self.epi.rows), 0)

    def test_mark_stale_flags_only_matching_cited_paths(self) -> None:
        self.epi.next_query_distance = 0.9
        cites_a = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="cites a",
            body="b",
            cited_paths=["addons/cfs_addons/foo/models/bar.py"],
            failure_class="code",
            failure_signature="AttributeError",
        )
        self.epi.next_query_distance = 0.9
        cites_b = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="cites b",
            body="b",
            cited_paths=["addons/cfs_addons/other/file.py"],
            failure_class="code",
            failure_signature="ValueError",
        )
        result = memory.mark_memories_stale_for_paths(
            paths=["addons/cfs_addons/foo/models/bar.py"],
            commit_sha="cafebabe",
            kinds=[memory.KIND_EPISODIC],
        )
        self.assertEqual(result["updated_total"], 1)
        self.assertEqual(result["by_kind"][memory.KIND_EPISODIC]["updated"], 1)
        self.assertIn(cites_a["id"], result["by_kind"][memory.KIND_EPISODIC]["ids"])
        self.assertEqual(self.epi.rows[cites_a["id"]]["metadata"]["stale_since_commit"], "cafebabe")
        self.assertEqual(self.epi.rows[cites_b["id"]]["metadata"]["stale_since_commit"], "")

    def test_mark_stale_is_idempotent_for_same_commit(self) -> None:
        self.epi.next_query_distance = 0.9
        save = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="cites a",
            body="b",
            cited_paths=["a/b.py"],
            failure_class="code",
            failure_signature="x",
        )
        first = memory.mark_memories_stale_for_paths(
            paths=["a/b.py"], commit_sha="abc123", kinds=[memory.KIND_EPISODIC]
        )
        second = memory.mark_memories_stale_for_paths(
            paths=["a/b.py"], commit_sha="abc123", kinds=[memory.KIND_EPISODIC]
        )
        self.assertEqual(first["updated_total"], 1)
        self.assertEqual(second["updated_total"], 0)
        self.assertEqual(self.epi.rows[save["id"]]["metadata"]["stale_since_commit"], "abc123")

    def test_mark_stale_no_paths_returns_noop_summary(self) -> None:
        result = memory.mark_memories_stale_for_paths(paths=[], commit_sha="zzz")
        self.assertEqual(result["updated_total"], 0)
        self.assertEqual(result["by_kind"][memory.KIND_EPISODIC]["scanned"], 0)
        self.assertEqual(result["by_kind"][memory.KIND_DECLARATIVE]["scanned"], 0)

    def test_dedup_merge_clears_stale_since_commit(self) -> None:
        self.epi.next_query_distance = 0.9
        first = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="auth header missing",
            body="Set x-odoo-user.",
            cited_paths=["a.py"],
            failure_class="mcp_call",
            failure_signature="401",
        )
        self.epi.rows[first["id"]]["metadata"]["stale_since_commit"] = "deadbeef"
        self.epi.next_query_distance = 0.01  # within dedup distance
        second = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="auth header missing again",
            body="Set x-odoo-user before MCP call (re-validated).",
            cited_paths=["a.py"],
            failure_class="mcp_call",
            failure_signature="401",
        )
        self.assertEqual(second["dedup"]["action"], "merged")
        self.assertEqual(second["id"], first["id"])
        self.assertEqual(self.epi.rows[first["id"]]["metadata"]["stale_since_commit"], "")

    def test_list_stale_returns_only_flagged_rows(self) -> None:
        self.epi.next_query_distance = 0.9
        flagged = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="flagged",
            body="b",
            cited_paths=["a.py"],
            failure_class="code",
            failure_signature="x",
        )
        self.epi.next_query_distance = 0.9
        clean = memory.save_memory(
            genai_client=_FakeGenAIClient(),
            kind=memory.KIND_EPISODIC,
            source=memory.SOURCE_FAILURE_RESOLUTION,
            title="clean",
            body="b",
            cited_paths=["b.py"],
            failure_class="code",
            failure_signature="y",
        )
        self.epi.rows[flagged["id"]]["metadata"]["stale_since_commit"] = "cafebabe"
        result = memory.list_stale_memories(kinds=[memory.KIND_EPISODIC], limit=10)
        ids = [row["id"] for row in result["by_kind"][memory.KIND_EPISODIC]]
        self.assertIn(flagged["id"], ids)
        self.assertNotIn(clean["id"], ids)
        self.assertEqual(result["total"], 1)


if __name__ == "__main__":  # pragma: no cover - manual runner
    unittest.main()
