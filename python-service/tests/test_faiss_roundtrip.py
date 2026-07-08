"""
Always-on FAISS round-trip tests (app/services/faiss_service.py).

Each test points the module's on-disk index at a pytest tmp_path and forces a
fresh in-memory state, so nothing here reads or writes the real ./face_index/.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from app.services import faiss_service  # noqa: E402


@pytest.fixture(autouse=True)
def isolated_index(tmp_path, monkeypatch):
    """Point the module's index/metadata files at tmp_path and start empty."""
    index_dir = tmp_path / "face_index"
    monkeypatch.setattr(faiss_service, "_INDEX_DIR", index_dir)
    monkeypatch.setattr(faiss_service, "_INDEX_FILE", index_dir / "face.index")
    monkeypatch.setattr(faiss_service, "_META_FILE", index_dir / "face_metadata.json")
    monkeypatch.setattr(faiss_service, "_index", None)
    monkeypatch.setattr(faiss_service, "_id_map", [])
    monkeypatch.setattr(faiss_service, "_deleted", set())
    faiss_service.rebuild([])
    yield


def _vector(hot_index: int) -> list[float]:
    """Deterministic one-hot EMBEDDING_DIM-dim vector."""
    v = [0.0] * faiss_service.EMBEDDING_DIM
    v[hot_index] = 1.0
    return v


def test_identify_on_empty_index_returns_no_candidates() -> None:
    results = faiss_service.identify(_vector(0), top_k=5)
    assert results == []


def test_enroll_and_identify_ranks_nearest_patient_first() -> None:
    faiss_service.enroll(patient_id=1, template_id=1, embedding=_vector(0))
    faiss_service.enroll(patient_id=2, template_id=2, embedding=_vector(1))

    results = faiss_service.identify(_vector(0), top_k=5)

    assert results[0]["patient_id"] == 1
    assert len(results) == 2
    assert results[0]["score"] > results[1]["score"]


def test_remove_patient_excludes_from_future_identify() -> None:
    faiss_service.enroll(patient_id=1, template_id=1, embedding=_vector(0))
    faiss_service.enroll(patient_id=2, template_id=2, embedding=_vector(1))

    removed = faiss_service.remove_patient(1)
    assert removed == 1

    results = faiss_service.identify(_vector(0), top_k=5)
    assert all(r["patient_id"] != 1 for r in results)
