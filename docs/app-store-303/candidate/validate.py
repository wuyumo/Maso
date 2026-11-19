#!/usr/bin/env python3
"""Offline read-only verifier. Self-tests mutate only in-memory byte mappings."""
import copy
import hashlib
import json
from pathlib import Path
import sys

APPROVED = {
    "en-US": {
        "name": "Masso — Workout Tracker",
        "subtitle": "AI Plans & 3D Muscle Recovery",
        "keywords": "strength,training,gym,log,planner,weightlifting,sets,reps,routine,progress,dumbbell,barbell,watch",
        "promotional_text": "Log every set, build strength plans with AI, and explore training-based muscle recovery estimates in 3D.",
        "opening": "Log your strength workouts and see your training in context. Record weight and reps, review progress, and explore training-based muscle recovery estimates in 3D. Build a plan with AI around your goals and equipment.",
    },
    "zh-Hans": {
        "name": "Masso - AI健身计划",
        "subtitle": "力量训练记录与肌群恢复估算",
        "keywords": "增肌,举铁,健美,哑铃,杠铃,组数,次数,健身房,器械,居家,日志",
        "promotional_text": "用 AI 按目标与器械生成训练计划，记录每组重量和次数，在 3D 肌群图中查看基于训练记录的恢复估算。",
        "opening": "按目标和可用器械，用 AI 制定力量训练计划。记录每组重量与次数，回顾训练进步，并通过 3D 肌群图查看基于训练记录的恢复估算。",
    },
}
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}
MARKERS = {"en-US": "• AI Coach that listens.", "zh-Hans": "• 听懂你的 AI Coach："}

def verify(files, manifest):
    errors = []
    def check(ok, message):
        if not ok:
            errors.append(message)
    def read(path):
        return files.get(path, b"").decode("utf-8", errors="strict")
    for path, record in manifest["files"].items():
        check(path in files, "missing file: " + path)
        data = files.get(path, b"")
        check(hashlib.sha256(data).hexdigest() == record["sha256"], "hash mismatch: " + path)
        check(len(data) == record["bytes"], "byte size mismatch: " + path)
    check(manifest["status"] == "PREPARED_ONLY_NOT_APPLIED_TO_ASC", "incorrect application status")
    source = read("snapshots/asc-metadata-2026-11-19.txt")
    check(hashlib.sha256(files["snapshots/asc-metadata-2026-11-19.txt"]).hexdigest() == manifest["source"]["sha256"], "source hash mismatch")
    descs = {
        "en-US": source.split("3.0.2 PRODUCT PAGE METADATA — ENGLISH (U.S.)\n", 1)[1].split("\n\n3.0.2 PRODUCT PAGE METADATA — CHINESE", 1)[0].split("Description:\n", 1)[1],
        "zh-Hans": source.split("3.0.2 PRODUCT PAGE METADATA — CHINESE (SIMPLIFIED / zh-Hans)\n", 1)[1].split("\n\nCHINA / ICP PROMPT", 1)[0].split("Description:\n", 1)[1],
    }
    expected_after = {"after/" + loc + "/" + field + ".txt" for loc in APPROVED for field in LIMITS}
    check({x for x in files if x.startswith("after/")} == expected_after, "after scope includes missing/unapproved field or locale")
    check(len(manifest["fields"]) == 10, "unexpected field count")
    counts = {}
    for record in manifest["fields"]:
        loc, field = record["locale"], record["field"]
        before, after, rollback = [read(record[x + "_path"]) for x in ("before", "after", "rollback")]
        check(before == rollback, "rollback differs: " + loc + "/" + field)
        check(len(after) <= LIMITS[field], "character limit exceeded: " + loc + "/" + field)
        check(not after.startswith("\ufeff"), "UTF-8 BOM: " + loc + "/" + field)
        for phase, value in (("before", before), ("after", after)):
            check(record[phase] == {"characters": len(value), "utf8_bytes": len(value.encode("utf-8"))}, "manifest length mismatch: " + loc + "/" + field)
        check(record["changed"] == (before != after), "change flag mismatch: " + loc + "/" + field)
        if field == "keywords":
            check(len(after.encode("utf-8")) <= 100, "keyword byte limit exceeded: " + loc)
            check(not any(c.isspace() for c in after), "keyword whitespace: " + loc)
            terms = after.lower().split(",")
            check(all(terms) and len(set(terms)) == len(terms), "empty/duplicate keyword: " + loc)
        if field == "description":
            check(before == descs[loc], "before description is not captured ASC value: " + loc)
            marker = MARKERS[loc]
            check(before.count(marker) == 1 and after.count(marker) == 1, "tail marker count: " + loc)
            if marker in before and marker in after:
                tail = before[before.index(marker):]
                check(after[after.index(marker):] == tail, "description tail changed: " + loc)
                check(after == APPROVED[loc]["opening"] + "\n\n" + tail, "description opening/scope mismatch: " + loc)
                check(hashlib.sha256(tail.encode()).hexdigest() == record["description_tail_sha256"], "tail hash mismatch: " + loc)
        else:
            check(after == APPROVED[loc][field], "approved wording mismatch: " + loc + "/" + field)
        counts[loc + "/" + field] = {"characters": len(after), "utf8_bytes": len(after.encode())}
    for loc in APPROVED:
        check(read("before/" + loc + "/promotional_text.txt") == "", "blank live promo not preserved: " + loc)
        check(read("before/" + loc + "/whats_new.txt") == read("rollback/" + loc + "/whats_new.txt"), "What is New rollback differs: " + loc)
    return errors, counts

def self_test(files, manifest):
    errors, _ = verify(files, manifest)
    if errors:
        raise ValueError("Baseline failed: " + repr(errors))
    tests = [
        ("hash tamper", "after/en-US/name.txt", b"Wrong", "hash mismatch"),
        ("keyword overflow", "after/en-US/keywords.txt", b"x" * 101, "limit exceeded"),
        ("tail tamper", "after/zh-Hans/description.txt", files["after/zh-Hans/description.txt"].replace("不支持自动解析视频或音频".encode(), "支持自动解析视频或音频".encode()), "tail changed"),
        ("rollback tamper", "rollback/en-US/description.txt", b"lost", "rollback differs"),
        ("scope creep", "after/fr-FR/name.txt", b"unapproved", "after scope"),
    ]
    for name, path, value, expected in tests:
        modified = dict(files)
        modified[path] = value
        found, _ = verify(modified, manifest)
        if not any(expected in e for e in found):
            raise ValueError("Mutation was not detected: " + name)
    altered = copy.deepcopy(manifest)
    altered["fields"][0]["after"]["characters"] = 999
    if not any("manifest length mismatch" in e for e in verify(files, altered)[0]):
        raise ValueError("Manifest length mutation was not detected")
    return {"status": "PASS", "tests": 7, "details": "baseline plus six in-memory negative tests; no files written"}

def main():
    root = Path(__file__).resolve().parent
    files = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
    manifest = json.loads(files["manifest.json"])
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        print(json.dumps(self_test(files, manifest), ensure_ascii=False, indent=2))
        return 0
    if len(sys.argv) != 1:
        raise ValueError("Use no arguments or --self-test")
    errors, counts = verify(files, manifest)
    print(json.dumps({"status": "FAIL" if errors else "PASS", "errors": errors, "field_counts": counts, "description_tail": "byte-identical to captured ASC source" if not errors else "see errors", "network": "none", "writes": "none"}, ensure_ascii=False, indent=2))
    return int(bool(errors))

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, ensure_ascii=False))
        sys.exit(1)
