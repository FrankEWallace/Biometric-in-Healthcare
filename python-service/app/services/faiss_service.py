"""
FAISS in-memory face embedding index for patient identification.

Index type: IndexFlatIP (exact inner product search).
            All vectors are L2-normalised before insert/search, so inner
            product equals cosine similarity.  FlatIP is exact (no
            approximation) and handles up to ~100 000 vectors comfortably
            on a single CPU core.

Persistence:
    The index and its metadata are saved to FAISS_INDEX_DIR (default:
    ./face_index/) after every mutation.  On startup the service loads the
    saved state automatically; if no saved state exists it starts empty and
    waits for a /face/rebuild call from Laravel.

Deletion:
    FAISS FlatIndex does not support in-place removal.  Deleted vectors are
    tracked in a _deleted set and filtered out of search results.  The set is
    compacted (index rebuilt without deleted rows) whenever deleted vectors
    exceed 20 % of total, or explicitly via /face/rebuild.

Thread safety:
    All mutations are protected by a threading.Lock.  Reads (identify) are
    lock-free because FAISS FlatIP search is read-only on the index object.
"""
from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from threading import Lock

import numpy as np

logger = logging.getLogger(__name__)

# ── Configuration ─────────────────────────────────────────────────────────────

EMBEDDING_DIM  = 512
_INDEX_DIR     = Path(os.getenv("FAISS_INDEX_DIR", "./face_index"))
_INDEX_FILE    = _INDEX_DIR / "face.index"
_META_FILE     = _INDEX_DIR / "face_metadata.json"
_COMPACT_RATIO = 0.20   # auto-compact when deleted/total exceeds this

# ── Module-level state ────────────────────────────────────────────────────────

_index                   = None
_id_map: list[dict]      = []   # position → {patient_id, template_id, active}
_deleted: set[int]       = set()
_lock                    = Lock()


# ── Private helpers ───────────────────────────────────────────────────────────

def _faiss():
    import faiss  # deferred — fails fast if not installed
    return faiss


def _normalise(vec: np.ndarray) -> np.ndarray:
    f = _faiss()
    v = vec.astype(np.float32).reshape(1, -1).copy()
    f.normalize_L2(v)
    return v


def _save() -> None:
    f = _faiss()
    _INDEX_DIR.mkdir(parents=True, exist_ok=True)
    f.write_index(_index, str(_INDEX_FILE))
    with open(_META_FILE, "w") as fh:
        json.dump({"id_map": _id_map, "deleted": list(_deleted)}, fh)


def _load_or_create() -> None:
    global _index, _id_map, _deleted
    f = _faiss()
    _INDEX_DIR.mkdir(parents=True, exist_ok=True)

    if _INDEX_FILE.exists() and _META_FILE.exists():
        try:
            _index = f.read_index(str(_INDEX_FILE))
            with open(_META_FILE) as fh:
                data = json.load(fh)
            _id_map  = data.get("id_map", [])
            _deleted = set(data.get("deleted", []))
            logger.info(
                "FAISS index loaded: %d vectors (%d deleted).",
                _index.ntotal, len(_deleted),
            )
            return
        except Exception as exc:
            logger.warning("Could not load saved FAISS index (%s). Starting fresh.", exc)

    _index   = f.IndexFlatIP(EMBEDDING_DIM)
    _id_map  = []
    _deleted = set()
    logger.info("FAISS index created fresh.")


def _maybe_compact() -> None:
    """Rebuild without deleted rows if fragmentation exceeds threshold."""
    total = _index.ntotal
    if total == 0:
        return
    if len(_deleted) / total < _COMPACT_RATIO:
        return

    logger.info("Compacting FAISS index (%d/%d deleted).", len(_deleted), total)
    active = [
        (i, m) for i, m in enumerate(_id_map)
        if i not in _deleted
    ]
    _do_rebuild([
        {"patient_id": m["patient_id"], "template_id": m["template_id"],
         "embedding": _index.reconstruct(i).tolist()}
        for i, m in active
    ])


def _do_rebuild(templates: list[dict]) -> int:
    """Inner rebuild — caller must hold _lock."""
    global _index, _id_map, _deleted
    f = _faiss()

    new_index   = f.IndexFlatIP(EMBEDDING_DIM)
    new_id_map: list[dict] = []
    rows: list[np.ndarray] = []

    for t in templates:
        vec = np.array(t["embedding"], dtype=np.float32)
        f.normalize_L2(vec.reshape(1, -1))
        rows.append(vec)
        new_id_map.append({
            "patient_id":  t["patient_id"],
            "template_id": t["template_id"],
            "active":      True,
        })

    if rows:
        new_index.add(np.vstack(rows).astype(np.float32))

    _index   = new_index
    _id_map  = new_id_map
    _deleted = set()
    _save()
    return new_index.ntotal


# ── Public API ────────────────────────────────────────────────────────────────

def initialise() -> None:
    """Load or create the index.  Call once at service startup."""
    global _index
    if _index is None:
        _load_or_create()


def enroll(patient_id: int, template_id: int, embedding: list[float]) -> int:
    """
    Add one embedding to the index.

    Returns the FAISS position assigned to this vector.
    Thread-safe.
    """
    initialise()
    vec = _normalise(np.array(embedding, dtype=np.float32))

    with _lock:
        pos = _index.ntotal
        _index.add(vec)
        _id_map.append({"patient_id": patient_id, "template_id": template_id, "active": True})
        _save()

    return pos


def remove_patient(patient_id: int) -> int:
    """
    Logically delete all vectors for a patient.

    Returns the number of vectors marked deleted.
    Thread-safe.
    """
    initialise()
    removed = 0
    with _lock:
        for pos, meta in enumerate(_id_map):
            if meta["patient_id"] == patient_id and pos not in _deleted:
                _deleted.add(pos)
                meta["active"] = False
                removed += 1
        if removed:
            _save()
            _maybe_compact()
    return removed


def identify(embedding: list[float], top_k: int = 10) -> list[dict]:
    """
    Search for the closest patients using cosine similarity.

    Args:
        embedding: 512-dim ArcFace embedding (will be L2-normalised internally).
        top_k:     Number of distinct patients to return.

    Returns:
        List of {patient_id, template_id, score} sorted by score descending.
        score is cosine similarity in [-1, 1]; higher = more similar.
        Returns [] if the index is empty.
    """
    initialise()

    active = _index.ntotal - len(_deleted)
    if active == 0:
        return []

    vec = _normalise(np.array(embedding, dtype=np.float32))

    # Over-fetch to account for deleted vectors
    k = min(top_k * 4 + len(_deleted), _index.ntotal)
    D, I = _index.search(vec, int(k))

    best: dict[int, dict] = {}
    for score, pos in zip(D[0].tolist(), I[0].tolist()):
        if pos < 0 or pos in _deleted:
            continue
        meta = _id_map[pos]
        pid  = meta["patient_id"]
        if pid not in best or score > best[pid]["score"]:
            best[pid] = {
                "patient_id":  pid,
                "template_id": meta["template_id"],
                "score":       round(float(score), 4),
            }

    return sorted(best.values(), key=lambda r: r["score"], reverse=True)[:top_k]


def rebuild(templates: list[dict]) -> int:
    """
    Discard the current index and rebuild from a full template list.

    Each item in templates must have {patient_id, template_id, embedding}.
    Called by Laravel after bulk migrations or when the on-disk index is lost.
    Thread-safe.
    """
    initialise()
    with _lock:
        return _do_rebuild(templates)


def stats() -> dict:
    initialise()
    patient_ids = {
        m["patient_id"]
        for i, m in enumerate(_id_map)
        if i not in _deleted
    }
    return {
        "total_vectors":  _index.ntotal,
        "deleted_vectors": len(_deleted),
        "active_vectors": _index.ntotal - len(_deleted),
        "patient_count":  len(patient_ids),
        "index_persisted": _INDEX_FILE.exists(),
    }
