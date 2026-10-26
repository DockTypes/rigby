#!/usr/bin/env python3
"""Build the RAG corpus from PDFs in assets/data/.

Walks `assets/data/` recursively, extracts text from each PDF, splits into
~600-char chunks, calls Gemini text-embedding-004 for each, and writes
`assets/rag/chunks.json` with metadata per chunk.

Schedule PDFs (in folders Informatica/, computer-sience/, matematica-informatica/)
get extra metadata fields: specialization, year, group. Other PDFs get just
`category` (folder name like "regulamente", "burse", etc.).

Run:
    GEMINI_KEY=... python scripts/build_rag.py
"""
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path
from typing import List, Dict, Any, Optional

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "assets" / "data"
OUT_FILE = ROOT / "assets" / "rag" / "chunks.json"

GEMINI_KEY = os.environ.get("GEMINI_KEY", "")
if not GEMINI_KEY:
    print("ERROR: GEMINI_KEY environment variable is required to run build_rag.py", file=sys.stderr)
    print("Usage: GEMINI_KEY=your_key python scripts/build_rag.py", file=sys.stderr)
    sys.exit(1)

EMBED_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent"
    f"?key={GEMINI_KEY}"
)
EMBED_DIMS = 768  

CHUNK_SIZE = 600
CHUNK_OVERLAP = 80

# Folder-name → canonical specialization key (matches what UserProfile stores).
SCHEDULE_FOLDER_TO_SPEC = {
    "Informatica": "informatica",
    "computer-sience": "computer-science",
    "matematica-informatica": "matematica-informatica",
}

# ── Helpers ────────────────────────────────────────────────────────────────

def extract_text(pdf_path: Path) -> str:
    reader = PdfReader(str(pdf_path))
    parts = []
    for page in reader.pages:
        try:
            parts.append(page.extract_text() or "")
        except Exception as e:
            print(f"  ! page extract error in {pdf_path.name}: {e}")
    return "\n\n".join(parts)


def normalize(text: str) -> str:
    text = re.sub(r"\r\n", "\n", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def chunk(text: str, size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> List[str]:
    """Greedy paragraph chunking with sentence-level fallback for huge paras."""
    text = normalize(text)
    if not text:
        return []
    paras = re.split(r"\n{2,}", text)
    chunks: List[str] = []
    cur = ""
    for p in paras:
        p = p.strip()
        if not p:
            continue
        if len(cur) + len(p) + 2 <= size:
            cur = (cur + "\n\n" + p).strip()
            continue
        if cur:
            chunks.append(cur)
            cur = ""
        if len(p) > size:
            sentences = re.split(r"(?<=[.!?])\s+", p)
            buf = ""
            for s in sentences:
                if len(buf) + len(s) + 1 <= size:
                    buf = (buf + " " + s).strip()
                else:
                    if buf:
                        chunks.append(buf)
                    if len(s) > size:
                        for i in range(0, len(s), size):
                            chunks.append(s[i:i + size])
                        buf = ""
                    else:
                        buf = s
            if buf:
                cur = buf
        else:
            cur = p
    if cur:
        chunks.append(cur)

    if overlap > 0 and len(chunks) > 1:
        out = [chunks[0]]
        for i in range(1, len(chunks)):
            tail = out[-1][-overlap:]
            out.append((tail + " " + chunks[i]).strip())
        return out
    return chunks


def parse_schedule_filename(stem: str) -> Optional[Dict[str, int]]:
    """Parse names like 'info1gr1', 'cs2gr3', 'mi1', 'cs1' → {year, group}."""
    m = re.match(r"^[a-z]+(\d+)(?:gr(\d+))?$", stem.lower())
    if not m:
        return None
    year = int(m.group(1))
    group = int(m.group(2)) if m.group(2) else 1
    return {"year": year, "group": group}


def metadata_for(pdf_path: Path) -> Dict[str, Any]:
    rel = pdf_path.relative_to(DATA_DIR)
    parts = rel.parts
    md: Dict[str, Any] = {"source": rel.as_posix()}
    if not parts:
        md["category"] = "general"
        return md
    folder = parts[0]
    if folder in SCHEDULE_FOLDER_TO_SPEC:
        md["category"] = "orar"
        md["specialization"] = SCHEDULE_FOLDER_TO_SPEC[folder]
        sched = parse_schedule_filename(pdf_path.stem)
        if sched:
            md.update(sched)
    else:
        md["category"] = folder
    return md


def embed(text: str, retries: int = 4) -> List[float]:
    body = json.dumps({
        "content": {"parts": [{"text": text}]},
        "outputDimensionality": EMBED_DIMS,
        "taskType": "RETRIEVAL_DOCUMENT",
    }).encode("utf-8")
    req = urllib.request.Request(
        EMBED_URL, data=body, headers={"Content-Type": "application/json"}
    )
    last_err: Optional[Exception] = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data["embedding"]["values"]
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (429, 500, 503) and attempt < retries - 1:
                wait = 2 ** attempt
                print(f"  ! HTTP {e.code}, sleeping {wait}s")
                time.sleep(wait)
                continue
            raise
        except Exception as e:
            last_err = e
            if attempt < retries - 1:
                time.sleep(1 + attempt)
                continue
            raise
    raise RuntimeError(f"embed: max retries reached ({last_err})")


# ── Main ───────────────────────────────────────────────────────────────────

def main() -> int:
    if not DATA_DIR.exists():
        print(f"ERROR: {DATA_DIR} doesn't exist", file=sys.stderr)
        return 1

    pdfs = sorted(DATA_DIR.rglob("*.pdf"))
    print(f"Found {len(pdfs)} PDFs under {DATA_DIR}")

    out: List[Dict[str, Any]] = []
    failed: List[str] = []

    for i, pdf in enumerate(pdfs):
        rel = pdf.relative_to(DATA_DIR).as_posix()
        meta = metadata_for(pdf)
        print(f"[{i+1}/{len(pdfs)}] {rel} → {meta.get('category')}"
              + (f" y{meta.get('year')} g{meta.get('group')}"
                 if 'year' in meta else ""))
        try:
            text = extract_text(pdf)
        except Exception as e:
            print(f"  ! extract failed: {e}")
            failed.append(rel)
            continue
        chs = chunk(text)
        if not chs:
            print("  ! no text extracted")
            failed.append(rel)
            continue
        print(f"  → {len(chs)} chunks")
        for ci, c in enumerate(chs):
            try:
                emb = embed(c)
            except Exception as e:
                print(f"  ! embed chunk {ci}: {e}")
                continue
            out.append({
                "id": f"{rel}#{ci}",
                **meta,
                "text": c,
                "embedding": emb,
            })
            time.sleep(0.04)

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    size_kb = OUT_FILE.stat().st_size / 1024
    print(f"\n✅ Wrote {len(out)} chunks to {OUT_FILE} ({size_kb:.1f} KB)")
    if failed:
        print(f"⚠️  {len(failed)} PDFs failed: {failed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
