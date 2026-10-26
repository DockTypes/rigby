#!/usr/bin/env python3
"""Re-extract schedule (orar) PDFs using Gemini multimodal and replace the
orar entries in assets/rag/chunks.json.

Why: pypdf's text extraction destroys the day-column structure of the orar
tables (cells get merged in reading order, which mixes Luni/Marți/etc.).
Gemini 2.5-flash with the PDF as inline_data parses the table reliably and
outputs structured JSON that we can format into one clean chunk per day.

Output: one chunk per (specialization, year, group, day) instead of the previous
3-page-by-page chunks. Chunk text is human-readable bullet lines that Gemini
can easily reason over at query time.

Cache: per-PDF JSON in scripts/.cache/ to avoid re-calling Gemini on iterations.

Run:
    GEMINI_KEY=... python scripts/rebuild_schedules.py
"""
import base64
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path
from typing import List, Dict, Any, Optional

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "assets" / "data"
CHUNKS_FILE = ROOT / "assets" / "rag" / "chunks.json"
CACHE_DIR = ROOT / "scripts" / ".cache"

GEMINI_KEY = os.environ.get("GEMINI_KEY", "")
if not GEMINI_KEY:
    print("ERROR: GEMINI_KEY environment variable is required to run rebuild_schedules.py", file=sys.stderr)
    print("Usage: GEMINI_KEY=your_key python scripts/rebuild_schedules.py", file=sys.stderr)
    sys.exit(1)

PARSE_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    f"?key={GEMINI_KEY}"
)
EMBED_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent"
    f"?key={GEMINI_KEY}"
)
EMBED_DIMS = 768

SCHEDULE_FOLDER_TO_SPEC = {
    "Informatica": "informatica",
    "computer-sience": "computer-science",
    "matematica-informatica": "matematica-informatica",
}

PARSE_PROMPT = (
    "This is the weekly class schedule (orar) for a group of students at a "
    "Romanian university (FMI Ovidius). Read the timetable table and extract "
    "EVERY class slot. Output STRICT JSON with this exact schema, no prose, no "
    "markdown fences:\n"
    "{\n"
    '  "academic_year": "2025-2026",\n'
    '  "semester": 2,\n'
    '  "specialization": "...",\n'
    '  "year": 1,\n'
    '  "group": 1,\n'
    '  "days": [\n'
    '    {"day": "Luni", "slots": ['
    '{"start":"08:00","end":"10:00","course":"...","type":"Curs|Seminar|Laborator",'
    '"group_target":"info1 / info1 gr1 / etc","professor":"...","room":"...",'
    '"parity":"PARA|IMPARA|null"}'
    "]},\n"
    '    {"day": "Marți", "slots": [...]},\n'
    '    {"day": "Miercuri", "slots": [...]},\n'
    '    {"day": "Joi", "slots": [...]},\n'
    '    {"day": "Vineri", "slots": [...]}\n'
    "  ]\n"
    "}\n\n"
    "Rules:\n"
    "- Include every day Luni–Vineri even if empty (slots: []).\n"
    "- type = 'Curs' if marker is C, 'Seminar' if S, 'Laborator' if L.\n"
    "- Preserve diacritics in Romanian text (ș, ț, ă, â, î).\n"
    "- If a slot says PARA → parity 'PARA' (even weeks); IMPARA → 'IMPARA' (odd weeks).\n"
    "- Trim trailing '//' separators from values.\n"
    "- Return ONLY the JSON object, nothing else."
)


def parse_schedule_filename(stem: str) -> Optional[Dict[str, int]]:
    m = re.match(r"^[a-z]+(\d+)(?:gr(\d+))?$", stem.lower())
    if not m:
        return None
    return {"year": int(m.group(1)), "group": int(m.group(2)) if m.group(2) else 1}


def http_post_json(url: str, payload: dict, timeout: int = 90) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def call_gemini_parse(pdf_bytes: bytes) -> Dict[str, Any]:
    payload = {
        "contents": [{
            "parts": [
                {"inline_data": {
                    "mime_type": "application/pdf",
                    "data": base64.b64encode(pdf_bytes).decode("ascii"),
                }},
                {"text": PARSE_PROMPT},
            ]
        }],
        "generationConfig": {
            "temperature": 0,
            "responseMimeType": "application/json",
        },
    }
    for attempt in range(3):
        try:
            resp = http_post_json(PARSE_URL, payload)
            text = resp["candidates"][0]["content"]["parts"][0]["text"]
            return json.loads(text)
        except (urllib.error.HTTPError, KeyError, json.JSONDecodeError) as e:
            print(f"  ! parse attempt {attempt+1} failed: {e}")
            if attempt < 2:
                time.sleep(2 ** attempt)
                continue
            raise


def embed(text: str, retries: int = 4) -> List[float]:
    payload = {
        "content": {"parts": [{"text": text}]},
        "outputDimensionality": EMBED_DIMS,
        "taskType": "RETRIEVAL_DOCUMENT",
    }
    for attempt in range(retries):
        try:
            resp = http_post_json(EMBED_URL, payload, timeout=30)
            return resp["embedding"]["values"]
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 503) and attempt < retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise
    raise RuntimeError("embed failed")


def format_day_chunk(spec: str, year: int, group: int, day: Dict[str, Any]) -> Optional[str]:
    slots = day.get("slots") or []
    if not slots:
        return None
    lines = [f"Orar {spec} anul {year} grupa {group} — {day['day']}:"]
    for s in slots:
        start = s.get("start", "?")
        end = s.get("end", "?")
        course = (s.get("course") or "?").strip()
        ctype = s.get("type") or ""
        prof = (s.get("professor") or "").strip().rstrip("/").strip()
        room = (s.get("room") or "").strip().rstrip("/").strip()
        parity = s.get("parity")
        gt = (s.get("group_target") or "").strip()
        line = f"• {start}-{end} — {course}"
        extras = []
        if ctype: extras.append(ctype.lower())
        if gt: extras.append(gt)
        if prof: extras.append(prof)
        if room: extras.append(f"sala {room}")
        if parity and parity.lower() not in ("null", "none", ""):
            extras.append(f"săpt. {parity.lower()}")
        if extras:
            line += " (" + ", ".join(extras) + ")"
        lines.append(line)
    return "\n".join(lines)


def main() -> int:
    if not CHUNKS_FILE.exists():
        print(f"ERROR: {CHUNKS_FILE} doesn't exist — run build_rag.py first", file=sys.stderr)
        return 1

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    schedule_pdfs = []
    for folder, spec in SCHEDULE_FOLDER_TO_SPEC.items():
        sub = DATA_DIR / folder
        if not sub.exists(): continue
        for p in sorted(sub.glob("*.pdf")):
            sched = parse_schedule_filename(p.stem)
            if sched is None:
                print(f"  ! couldn't parse year/group from {p.name}, skipping")
                continue
            schedule_pdfs.append((p, spec, sched["year"], sched["group"]))

    print(f"Found {len(schedule_pdfs)} schedule PDFs")

    new_chunks: List[Dict[str, Any]] = []
    for i, (pdf, spec, year, group) in enumerate(schedule_pdfs):
        rel = pdf.relative_to(DATA_DIR).as_posix()
        cache_file = CACHE_DIR / f"{spec}_y{year}_g{group}.json"
        print(f"[{i+1}/{len(schedule_pdfs)}] {rel} (spec={spec} y={year} g={group})")

        if cache_file.exists():
            data = json.loads(cache_file.read_text(encoding="utf-8"))
            print("  ✓ loaded from cache")
        else:
            try:
                data = call_gemini_parse(pdf.read_bytes())
            except Exception as e:
                print(f"  ! parse failed: {e}")
                continue
            cache_file.write_text(json.dumps(data, ensure_ascii=False, indent=2),
                                  encoding="utf-8")
            print(f"  ✓ parsed & cached ({sum(len(d.get('slots',[])) for d in data.get('days',[]))} slots)")

        for day in data.get("days", []):
            text = format_day_chunk(spec, year, group, day)
            if not text: continue
            try:
                emb = embed(text)
            except Exception as e:
                print(f"  ! embed failed for {day.get('day')}: {e}")
                continue
            new_chunks.append({
                "id": f"{rel}#{day['day'].lower()}",
                "source": rel,
                "category": "orar",
                "specialization": spec,
                "year": year,
                "group": group,
                "day": day["day"],
                "text": text,
                "embedding": emb,
            })
            time.sleep(0.04)

    # Merge: drop existing orar chunks, append new ones.
    existing = json.loads(CHUNKS_FILE.read_text(encoding="utf-8"))
    kept = [c for c in existing if c.get("category") != "orar"]
    final = kept + new_chunks

    CHUNKS_FILE.write_text(
        json.dumps(final, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    size_kb = CHUNKS_FILE.stat().st_size / 1024
    print(f"\n✅ Replaced orar chunks: {len(existing) - len(kept)} old → "
          f"{len(new_chunks)} new. Total {len(final)} chunks ({size_kb:.1f} KB).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
