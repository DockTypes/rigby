#!/usr/bin/env python3
"""Bundle parsed schedules from scripts/.cache/ into a single
assets/rag/schedules.json — used by the Flutter side to render the
schedule UI (no embeddings, just structured data).

Cache filenames are `{spec}_y{year}_g{group}.json`; we trust those (canonical)
values over what Gemini wrote in the JSON body.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "scripts" / ".cache"
OUT = ROOT / "assets" / "rag" / "schedules.json"

CACHE_NAME_RE = re.compile(r"^(?P<spec>[a-z\-]+)_y(?P<year>\d+)_g(?P<group>\d+)\.json$")

def main() -> int:
    if not CACHE.exists():
        print(f"ERROR: {CACHE} doesn't exist — run rebuild_schedules.py first",
              file=sys.stderr)
        return 1

    out = []
    for f in sorted(CACHE.glob("*.json")):
        m = CACHE_NAME_RE.match(f.name)
        if not m:
            continue
        spec = m.group("spec")
        year = int(m.group("year"))
        group = int(m.group("group"))
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"  ! parse {f.name}: {e}")
            continue
        # Keep only the fields needed by the UI; trust filename metadata.
        days = []
        for d in data.get("days", []):
            slots = []
            for s in (d.get("slots") or []):
                slots.append({
                    "start": s.get("start"),
                    "end": s.get("end"),
                    "course": (s.get("course") or "").strip(),
                    "type": s.get("type"),
                    "group_target": (s.get("group_target") or "").strip(),
                    "professor": (s.get("professor") or "").strip().rstrip("/").strip(),
                    "room": (s.get("room") or "").strip().rstrip("/").strip(),
                    "parity": s.get("parity"),
                })
            days.append({"day": d.get("day"), "slots": slots})
        out.append({
            "specialization": spec,
            "year": year,
            "group": group,
            "academic_year": data.get("academic_year"),
            "semester": data.get("semester"),
            "days": days,
        })

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")),
                   encoding="utf-8")
    print(f"✅ Wrote {len(out)} schedules to {OUT} ({OUT.stat().st_size/1024:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
