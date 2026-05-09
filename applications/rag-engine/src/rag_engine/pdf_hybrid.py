"""Hybrid PDF ingest: PyMuPDF text layer + rasterized Tesseract OCR, then per-page fusion and chunking."""
from __future__ import annotations

import io
import logging
import os
import re
from difflib import SequenceMatcher
from typing import Any

from rag_engine.chunking import chunk_text
from rag_engine.structured_chunks import StructuredChunk

log = logging.getLogger(__name__)


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def pdf_ingest_profile() -> str:
    """Stable string for Chroma fingerprinting when PDF ingest settings change."""
    dpi = _env_int("RAG_PDF_OCR_DPI", 200)
    sim = (os.getenv("RAG_PDF_FUSION_SIMILARITY") or "0.82").strip()
    psm = _env_int("RAG_TESSERACT_PSM", 6)
    lang = (os.getenv("RAG_TESSERACT_LANG") or "eng").strip() or "eng"
    return f"{dpi}|{sim}|{psm}|{lang}"


def _normalize_for_compare(s: str) -> str:
    s = s.lower()
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _text_layer_quality_ok(text: str) -> bool:
    t = (text or "").strip()
    if len(t) < 12:
        return False
    ctrl = sum(1 for c in t if ord(c) < 32 and c not in "\n\t\r")
    if ctrl / max(len(t), 1) > 0.03:
        return False
    letters = sum(1 for c in t if c.isalpha())
    if letters < 8 and "\n" not in t:
        return False
    return True


def _similarity(a: str, b: str) -> float:
    na = _normalize_for_compare(a)
    nb = _normalize_for_compare(b)
    if not na and not nb:
        return 1.0
    if not na or not nb:
        return 0.0
    return float(SequenceMatcher(None, na, nb).ratio())


def fuse_page_texts(text_layer: str, ocr_text: str, *, threshold: float) -> tuple[str, str]:
    """Return (body_for_embedding, fusion_mode)."""
    tl = (text_layer or "").strip()
    oc = (ocr_text or "").strip()
    t_ok = _text_layer_quality_ok(tl)
    o_ok = bool(oc)

    if t_ok and not o_ok:
        return tl, "text_only"
    if not t_ok and o_ok:
        return oc, "ocr_only"
    if not t_ok and not o_ok:
        return "", "empty"
    sim = _similarity(tl, oc)
    if sim >= threshold:
        return tl, "aligned_text"
    body = (
        "[pdf_text_layer]\n"
        + tl
        + "\n\n---\n[ocr]\n"
        + oc
    )
    return body, "dual_merge"


def _ocr_pixmap(pix: Any) -> str:
    import pytesseract
    from PIL import Image

    img = Image.open(io.BytesIO(pix.tobytes("png")))
    lang = (os.getenv("RAG_TESSERACT_LANG") or "eng").strip() or "eng"
    psm = _env_int("RAG_TESSERACT_PSM", 6)
    cfg = f"--oem 3 --psm {psm}"
    try:
        return (pytesseract.image_to_string(img, lang=lang, config=cfg) or "").strip()
    except pytesseract.TesseractNotFoundError:
        log.error("tesseract binary not found; install tesseract-ocr in the image")
        raise


def build_pdf_hybrid_chunks(rel_path: str, raw_pdf: bytes) -> list[StructuredChunk]:
    try:
        import fitz  # PyMuPDF
    except ImportError:
        log.warning("PyMuPDF missing; PDF indexing disabled for %s", rel_path)
        return []

    if not raw_pdf:
        return []

    dpi = max(72, min(400, _env_int("RAG_PDF_OCR_DPI", 200)))
    max_pages = max(1, _env_int("RAG_PDF_MAX_PAGES", 150))
    threshold = max(0.5, min(1.0, _env_float("RAG_PDF_FUSION_SIMILARITY", 0.82)))
    chunk_chars = max(256, _env_int("RAG_CHUNK_CHARS", 1500))
    overlap = max(0, _env_int("RAG_CHUNK_OVERLAP", 200))
    profile = pdf_ingest_profile()

    doc = None
    try:
        doc = fitz.open(stream=raw_pdf, filetype="pdf")
    except Exception as exc:
        log.warning("open pdf failed %s: %s", rel_path, exc)
        return []

    try:
        n = min(len(doc), max_pages)
        if len(doc) > max_pages:
            log.info("pdf %s: capping pages %s -> %s", rel_path, len(doc), max_pages)
        mat = fitz.Matrix(dpi / 72.0, dpi / 72.0)
        out: list[StructuredChunk] = []
        for i in range(n):
            page = doc[i]
            page_num = i + 1
            try:
                text_layer = (page.get_text("text") or "").strip()
            except Exception:
                text_layer = ""
            ocr_text = ""
            pix = None
            try:
                pix = page.get_pixmap(matrix=mat, alpha=False)
                ocr_text = _ocr_pixmap(pix)
            except Exception as exc:
                log.warning("pdf page %s ocr failed %s: %s", page_num, rel_path, exc)
            finally:
                if pix is not None:
                    del pix

            body, fusion = fuse_page_texts(text_layer, ocr_text, threshold=threshold)
            if not body.strip() or fusion == "empty":
                continue
            pieces = chunk_text(body, chunk_chars, overlap)
            if not pieces:
                continue
            for j, piece in enumerate(pieces):
                hdr = (
                    f"[path:{rel_path}]"
                    f"[lang:pdf]"
                    f"[kind:pdf_page]"
                    f"[page:{page_num}]"
                    f"[fusion:{fusion}]"
                )
                if len(pieces) > 1:
                    hdr += f"[part:{j + 1}/{len(pieces)}]"
                doc_text = hdr + "\n" + piece
                sym = f"page{page_num}" + (f"#{j}" if len(pieces) > 1 else "")
                out.append(
                    StructuredChunk(
                        document=doc_text,
                        start_line=page_num,
                        end_line=page_num,
                        language="pdf",
                        chunk_kind="pdf_page",
                        symbol=sym,
                        pdf_page=page_num,
                        pdf_fusion=fusion,
                        pdf_ingest_profile=profile,
                    )
                )
        return out
    finally:
        if doc is not None:
            doc.close()
