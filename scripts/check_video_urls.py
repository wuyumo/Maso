#!/usr/bin/env python3
from __future__ import annotations
"""
Check YouTube video URLs in exercises.json for dead links.

Uses YouTube's oEmbed endpoint — returns 200 for live videos, 401/404 for
removed/private/unavailable ones. Cheap, no API key needed.

Writes a JSON report next to this script: video_url_audit.json
Run with no args. Concurrent HTTP via threads.
"""
import json
import re
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXERCISES_JSON = os.path.join(ROOT, "Maso/Resources/exercises.json")
REPORT_PATH = os.path.join(HERE, "video_url_audit.json")

OEMBED = "https://www.youtube.com/oembed?url={}&format=json"

ID_RE = re.compile(r"(?:v=|youtu\.be/|embed/|shorts/)([A-Za-z0-9_-]{11})")


def extract_id(url):
    m = ID_RE.search(url)
    return m.group(1) if m else None


def check(url):
    """Return (url, http_status, note)."""
    api = OEMBED.format(url)
    req = Request(api, headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"})
    try:
        with urlopen(req, timeout=15) as r:
            return url, r.status, "ok"
    except HTTPError as e:
        # 401 = unauthorized/private, 403 = embed disabled, 404 = removed
        return url, e.code, e.reason or ""
    except URLError as e:
        return url, -1, str(e.reason)
    except Exception as e:
        return url, -2, str(e)


def main():
    with open(EXERCISES_JSON) as f:
        data = json.load(f)

    urls = set()
    for e in data:
        u = e.get("video_url")
        if u:
            urls.add(u)
    urls = sorted(urls)
    print(f"Checking {len(urls)} unique URLs via oEmbed...", flush=True)

    results = {}
    done = 0
    with ThreadPoolExecutor(max_workers=20) as pool:
        futures = {pool.submit(check, u): u for u in urls}
        for fut in as_completed(futures):
            url, status, note = fut.result()
            results[url] = {"status": status, "note": note}
            done += 1
            if done % 50 == 0:
                print(f"  {done}/{len(urls)}...", flush=True)

    dead = {u: r for u, r in results.items() if r["status"] not in (200,)}

    report = {
        "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total": len(urls),
        "alive": sum(1 for r in results.values() if r["status"] == 200),
        "dead_count": len(dead),
        "results": results,
    }
    with open(REPORT_PATH, "w") as f:
        json.dump(report, f, indent=2, sort_keys=True)

    print(f"\nDone. {report['alive']} alive, {report['dead_count']} dead/inaccessible.")
    print(f"Status breakdown:")
    breakdown = {}
    for r in results.values():
        breakdown[r["status"]] = breakdown.get(r["status"], 0) + 1
    for s, c in sorted(breakdown.items()):
        print(f"  HTTP {s}: {c}")
    print(f"\nReport written to {REPORT_PATH}")


if __name__ == "__main__":
    main()
