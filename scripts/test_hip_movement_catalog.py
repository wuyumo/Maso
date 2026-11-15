#!/usr/bin/env python3
"""Catalog contract for hip extension search vs the two hip-abduction variants.

Mirrors the bundled exercises.json + exercise-selection.json facts that
Exercise.matchesSearch / ExerciseSelectionPolicy tests lock in XCTest.
This script does not compile or launch the iOS app.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXERCISES = ROOT / "Maso" / "Resources" / "exercises.json"
SELECTION = ROOT / "Maso" / "Resources" / "exercise-selection.json"


def words(query: str) -> list[str]:
    return re.findall(r"[0-9A-Za-z]+|[\u4e00-\u9fff]+", query.lower())


def token_matches(token: str, word: str) -> bool:
    """Same exception as Exercise.searchToken: Spanish/Portuguese hiper ≠ hip."""
    start = token.find(word)
    if start < 0:
        return False
    if word == "hip" and token[start + len(word):].startswith("er"):
        return False
    return True


def tokens_of(exercise: dict) -> set[str]:
    parts = [exercise["name"].get("en", "")]
    parts.extend(exercise.get("aliases") or [])
    parts.extend(exercise.get("equipment") or [])
    for muscle in exercise["muscles"]["primary"]:
        parts.append(muscle["sub"])
        parts.append(muscle["major"])
    blob = " ".join(parts)
    found = set(re.findall(r"[0-9A-Za-z]+|[\u4e00-\u9fff]+", blob.lower()))
    # Movement facet is derived from the English name. "extension" is the
    # substring the app stores for any name containing that verb.
    english = exercise["name"].get("en", "").lower()
    if "extension" in english:
        found.add("extension")
    return found


def old_substring_match(exercise: dict, query: str) -> bool:
    """Pre-fix behavior: every query word is a substring of some token."""
    toks = tokens_of(exercise)
    return all(any(word in token for token in toks) for word in words(query))


def pattern_match(exercise: dict, pattern: str, query: str) -> bool:
    """Post-fix hip-extension phrase, plus the hiper guard on the token path."""
    if pattern == "hip_extension":
        query_words = words(query)
        if ("hip" in query_words and "extension" in query_words) or any(
            "髋伸展" in word or "髖伸展" in word for word in query_words
        ):
            remaining = []
            for word in query_words:
                if word in {"hip", "extension"}:
                    continue
                if "髋伸展" in word or "髖伸展" in word:
                    rest = word.replace("髋伸展", "").replace("髖伸展", "")
                    if rest:
                        remaining.append(rest)
                    continue
                remaining.append(word)
            toks = tokens_of(exercise)
            if all(any(token_matches(token, word) for token in toks) for word in remaining):
                return True
    toks = tokens_of(exercise)
    return all(any(token_matches(token, word) for token in toks) for word in words(query))


def main() -> int:
    exercises = json.loads(EXERCISES.read_text(encoding="utf-8"))
    selection = json.loads(SELECTION.read_text(encoding="utf-8"))
    by_id = {item["id"]: item for item in exercises}
    meta = {item["exerciseID"]: item for item in selection["entries"]}
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    check(len(by_id) == len(exercises), f"duplicate exercise ids: {len(exercises) - len(by_id)}")
    check(set(by_id) == set(meta), "exercise ids and selection ids diverged")

    machine = by_id["abductor_machine"]
    cable = by_id["abduction_cable"]
    check(machine["name"]["en"] == "Hip Abduction (Machine)", machine["name"]["en"])
    check(cable["name"]["en"] == "Hip Abduction (Cable)", cable["name"]["en"])
    check(machine["name"]["zh-Hans"] == "髋外展（器械）", machine["name"]["zh-Hans"])
    check(cable["name"]["zh-Hans"] == "髋外展（绳索）", cable["name"]["zh-Hans"])
    check(machine["name"]["zh-Hans"] != cable["name"]["zh-Hans"], "abduction names collapsed")
    check(machine["equipment"] == ["abductor_machine"], str(machine["equipment"]))
    check(cable["equipment"] == ["cable"], str(cable["equipment"]))
    check(any("outward" in line.lower() for line in machine["instructions"]["en"]), "machine cue")
    check(any("out" in line.lower() for line in cable["instructions"]["en"]), "cable cue")
    check(meta["abductor_machine"]["pattern"] == "hip_abduction", "machine pattern")
    check(meta["abduction_cable"]["pattern"] == "hip_abduction", "cable pattern")
    check(meta["abductor_machine"]["tier"] == "core", "machine tier")
    check(meta["abduction_cable"]["tier"] == "supporting", "cable tier")
    check(machine["imageFolder"] == "Thigh_Abductor", machine.get("imageFolder"))
    first_legacy = next(item["id"] for item in exercises if item.get("imageFolder") == "Thigh_Abductor")
    check(first_legacy == "abductor_machine", f"legacy folder owner is {first_legacy}")

    adduction = by_id["adductor_machine"]
    check(adduction["name"]["en"] == "Hip Adduction (Machine)", adduction["name"]["en"])
    check(adduction["name"]["zh-Hans"] == "髋内收（器械）", adduction["name"]["zh-Hans"])
    check(meta["adductor_machine"]["pattern"] == "hip_adduction", "adductor pattern")
    check(meta["adduction_cable"]["pattern"] == "hip_adduction", "cable adduction pattern")

    extension_ids = {item_id for item_id, item in meta.items() if item["pattern"] == "hip_extension"}
    check("hip_thrust_barbell" in extension_ids, "missing hip thrust")
    check("glute_bridge" in extension_ids, "missing glute bridge")
    check("cable_kickback" in extension_ids, "missing cable kickback")
    for excluded in ("abductor_machine", "abduction_cable", "adductor_machine", "adduction_cable", "reverse_hyperextension"):
        check(excluded not in extension_ids, f"{excluded} must not be hip_extension")
    check(meta["reverse_hyperextension"]["role"] == "hip_hinge", "reverse hyper role")
    check(meta["reverse_hyperextension"]["pattern"] == "hinge", "reverse hyper pattern")
    check(not any(item["name"]["en"] == "Hip Extension" or item["name"].get("zh-Hans") == "髋伸展" for item in exercises),
          "catalog gained an invented Hip Extension title")

    visible_named = [
        item["id"] for item in exercises
        if item["name"]["en"].startswith("Hip Abduction") and meta[item["id"]]["tier"] != "specialist"
    ]
    check(set(visible_named) == {"abductor_machine", "abduction_cable"}, str(visible_named))

    before = {item["id"] for item in exercises if old_substring_match(item, "hip extension")}
    after = {item["id"] for item in exercises if pattern_match(item, meta[item["id"]]["pattern"], "hip extension")}
    after_zh = {item["id"] for item in exercises if pattern_match(item, meta[item["id"]]["pattern"], "髋伸展")}
    after_hant = {item["id"] for item in exercises if pattern_match(item, meta[item["id"]]["pattern"], "髖伸展")}
    check(before == {"reverse_hyperextension"}, f"before hip extension hits: {sorted(before)}")
    check(after == extension_ids, f"after hip extension drifted: missing {sorted(extension_ids - after)[:8]} extra {sorted(after - extension_ids)[:8]}")
    check(after_zh == extension_ids, "zh search drifted")
    check(after_hant == extension_ids, "zh-Hant search drifted")
    cable_hits = {item["id"] for item in exercises if pattern_match(item, meta[item["id"]]["pattern"], "cable hip extension")}
    check("cable_kickback" in cable_hits and "hip_thrust_barbell" not in cable_hits and "abduction_cable" not in cable_hits,
          str(sorted(cable_hits)))
    abduction_hits = {item["id"] for item in exercises if pattern_match(item, meta[item["id"]]["pattern"], "hip abduction")}
    adduction_hits = {item["id"] for item in exercises if pattern_match(item, meta[item["id"]]["pattern"], "hip adduction")}
    check({"abductor_machine", "abduction_cable"} <= abduction_hits, str(sorted(abduction_hits)))
    check(all(meta[item_id]["pattern"] == "hip_abduction" for item_id in abduction_hits), "abduction search mixed")
    check({"adductor_machine", "adduction_cable"} <= adduction_hits, str(sorted(adduction_hits)))
    check(all(meta[item_id]["pattern"] == "hip_adduction" for item_id in adduction_hits), "adduction search mixed")
    check("abductor_machine" not in adduction_hits and "adductor_machine" not in abduction_hits, "abd/add crossed")
    check("reverse_hyperextension" not in after, "reverse hyper still matches hip extension")
    check(not pattern_match(by_id["hip_thrust_barbell"], "hip_extension", "extension"), "bare extension swallowed hip thrust")
    check(pattern_match(by_id["leg_extension_machine"], meta["leg_extension_machine"]["pattern"], "extension"), "leg extension lost")

    def prefix(name: str) -> str:
        for mark in ("(", "（"):
            if mark in name:
                name = name.split(mark, 1)[0]
        return name.strip().lower()

    check(meta["abductor_machine"]["programmingGroupID"] == "hip_abduction", "machine group")
    check(meta["abduction_cable"]["programmingGroupID"] == "hip_abduction", "cable group")
    check(meta["abductor_machine"]["displayFamilyID"] == meta["abduction_cable"]["displayFamilyID"] == "hip_abduction", "family")
    check(prefix(machine["name"]["en"]) == prefix(cable["name"]["en"]) == "hip abduction", "english group name")
    check(prefix(machine["name"]["zh-Hans"]) == prefix(cable["name"]["zh-Hans"]) == "髋外展", "chinese group name")
    check(meta["side_leg_raise"]["programmingGroupID"] != "hip_abduction", "side leg raise stays separate")
    check(meta["side_leg_raise_cable"]["programmingGroupID"] == meta["side_leg_raise"]["programmingGroupID"], "side leg cable family")
    check(meta["adductor_machine"]["programmingGroupID"] == "hip_adduction", "adduction group")

    def menu_rows(default_id: str, candidate_ids: list[str], current_id: str) -> list[str]:
        seen: set[str] = set()
        rows: list[str] = []
        for item_id in [default_id, *candidate_ids, current_id]:
            if item_id not in seen:
                seen.add(item_id)
                rows.append(item_id)
        return rows

    visible = ["abductor_machine", "abduction_cable"]
    check(menu_rows("abductor_machine", visible, "abductor_machine") == ["abductor_machine", "abduction_cable"], "default once")
    check(menu_rows("abductor_machine", visible, "abduction_cable") == ["abductor_machine", "abduction_cable"], "current cable once")
    check(menu_rows("abductor_machine", visible, "abductor_machine_lean_forward") == ["abductor_machine", "abduction_cable", "abductor_machine_lean_forward"], "filtered current kept once")
    check(menu_rows("abductor_machine", ["abductor_machine"], "abductor_machine") == ["abductor_machine"], "single variant")

    print(f"exercises {len(exercises)} unique {len(by_id)}")
    print(f"hip_extension ids {len(extension_ids)}")
    print("before 'hip extension':", sorted(before))
    print("after 'hip extension':", len(after), "ids, includes",
          ", ".join(item for item in ("hip_thrust_barbell", "glute_bridge", "cable_kickback") if item in after))
    print("visible non-specialist Hip Abduction:", visible_named)
    print("group entry en/zh: Hip Abduction / 髋外展")
    print("equipment variants:", machine["id"], machine["name"]["en"], cable["id"], cable["name"]["en"])
    print("variant menu:", menu_rows("abductor_machine", visible, "abductor_machine"))
    if failures:
        print("FAILED")
        for failure in failures:
            print(" -", failure)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
