#!/usr/bin/env python3
"""
Strip video_url fields whose targets are dead (per video_url_audit.json).

Operates on:
  - Maso/Resources/exercises.json (runtime)
  - Maso/Resources/new-exercise-db/exercises-new.json (source)
  - Maso/Resources/new-exercise-db/exercises-matched.json (source)

Keeps file formatting consistent with the originals (UTF-8, 2-space indent,
trailing newline). Removing instead of nulling so Swift `Codable` doesn't
even see the key.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REPORT = os.path.join(HERE, "video_url_audit.json")

TARGETS = [
    "Maso/Resources/exercises.json",
    "Maso/Resources/new-exercise-db/exercises-new.json",
    "Maso/Resources/new-exercise-db/exercises-matched.json",
]


def main():
    with open(REPORT) as f:
        audit = json.load(f)
    # Any non-200 oEmbed status = dead (verified via playabilityStatus cross-check)
    dead_urls = {u for u, r in audit["results"].items() if r["status"] != 200}
    print(f"Dead URL set: {len(dead_urls)} entries")

    for rel in TARGETS:
        fp = os.path.join(ROOT, rel)
        with open(fp) as f:
            data = json.load(f)
        removed = 0
        kept = 0
        for e in data:
            u = e.get("video_url")
            if u is None:
                continue
            if u in dead_urls:
                del e["video_url"]
                removed += 1
            else:
                kept += 1
        with open(fp, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"  {rel}: removed {removed}, kept {kept}")


if __name__ == "__main__":
    main()
