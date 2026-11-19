#!/usr/bin/env python3
"""Static checks for the isolated 3.0.3 candidate.

Reads the checkout and the approved ASO bundle. It does not compile, sign,
resolve packages, contact App Store Connect, or write files.
"""
from __future__ import annotations

import hashlib
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDIDATE = ROOT / "docs" / "app-store-303" / "candidate"

EXPECTED_SHORT = "3.0.3"
EXPECTED_BUILD = "55"
BUILD_STATUS = "PENDING_LIVE_ASC_CONFIRMATION"
DISPLAY_NAMES = {
    "Maso/Info.plist": "Masso",
    "MasoWidgets/Info.plist": "Masso Widgets",
    "MasoWatch/Info.plist": "Masso",
}
BUNDLE_IDS = {
    "app": "com.yumowu.maso",
    "widgets": "com.yumowu.maso.widgets",
    "watch": "com.yumowu.maso.watchkitapp",
    "tests": "com.yumowu.maso.tests",
    "uitests": "com.yumowu.maso.uitests",
}
TEAM = "TW8ZVVX529"
LOCK_SHA = "da7cc237d2f4afcbd74ecdb944b6f35681dfb2c8f51f39305f85f5ea61142e72"
MUSCLEMAP_REVISION = "7dc03071e03052e8bd4f6351e9176994cd28aa7d"
FILE_HASHES = {
    "Maso/Maso.entitlements": "7d1439fdf94035413a8a2d1f0cc8077920212469866545921f997b2baae8c0a5",
    "MasoWidgets/MasoWidgets.entitlements": "5378ed482e1f79abd2c3dbad2cde7ad6a423bcff65a9f704ecc900381066294d",
    "MasoWatch/MasoWatch.entitlements": "e82a7f6e130b0fe65a40214c15b4116c5245125329c63954d9ccdd9cc80f039e",
    "project.yml": "717d3312d6494416162a4dfbf97c4446964756d68aa45b17270f3e5e824625ea",
    "Maso.xcodeproj/project.pbxproj": "f03346d3a1955862743ebfc33e672f304d0b7d2d35f2d89e83ba4dbee7f994a8",
}
WHATS_NEW = {
    "en-US": "Updated App Store information to clarify workout logging, AI plans and muscle recovery estimates.",
    "zh-Hans": "更新 App Store 信息，更清楚地介绍训练记录、AI 计划与肌群恢复估算。",
}
EN_KEYWORDS = "strength,training,gym,log,planner,weightlifting,sets,reps,routine,progress,dumbbell,barbell,watch"
ZH_SUBTITLE = "力量训练记录与肌群恢复估算"
STORE_NAMES = {
    "en-US": "Masso — Workout Tracker",
    "zh-Hans": "Masso - AI健身计划",
}
LOCK_RELATIVE = "Maso.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_plist(path: Path) -> dict:
    return plistlib.loads(path.read_bytes())


def strings_value(path: Path, key: str) -> str | None:
    text = path.read_text(encoding="utf-8")
    match = re.search(r'^"%s" = "(.*)";$' % re.escape(key), text, re.M)
    return match.group(1) if match else None


def restore_labels_from_uitest(source: str) -> dict[str, str]:
    match = re.search(
        r"func testRestorePurchaseIsTheOnlyTrailingStoreKitAction.*?let labels = \[(.*?)\]\s*let webLabels",
        source,
        re.S,
    )
    if not match:
        return {}
    return dict(re.findall(r'"([^"]+)": "([^"]*)"', match.group(1)))


def git_tracked(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.splitlines()


def run_aso(argument: str | None = None) -> dict:
    command = [sys.executable, "validate.py"]
    if argument:
        command.append(argument)
    result = subprocess.run(
        command,
        cwd=CANDIDATE,
        capture_output=True,
        text=True,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        payload = {"status": "FAIL", "error": result.stdout[-500:] or result.stderr[-500:]}
    payload["exit_code"] = result.returncode
    return payload


def collect(root: Path = ROOT) -> dict:
    versions = {}
    for relative, display in DISPLAY_NAMES.items():
        plist = read_plist(root / relative)
        versions[relative] = {
            "short": plist.get("CFBundleShortVersionString"),
            "build": plist.get("CFBundleVersion"),
            "display": plist.get("CFBundleDisplayName"),
        }
    version_doc = json.loads((root / "docs/app-store-303/version-candidate.json").read_text(encoding="utf-8"))
    project_yml = (root / "project.yml").read_text(encoding="utf-8")
    pbx = (root / "Maso.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    tracked = git_tracked(root)
    lock_path = root / LOCK_RELATIVE
    if any(path.endswith("Package.resolved") for path in tracked):
        lock_state = "tracked"
    elif lock_path.exists():
        lock_state = sha256(lock_path)
    else:
        lock_state = "absent"
    labels = restore_labels_from_uitest((root / "MasoUITests" / "PaywallUITests.swift").read_text(encoding="utf-8"))
    locales = {
        "en": "en", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "de": "de", "fr": "fr",
        "es": "es", "it": "it", "pt-BR": "pt-BR", "ru": "ru", "ja": "ja", "ko": "ko", "ar": "ar",
    }
    restore_mismatches = []
    for language, expected in labels.items():
        folder = locales[language]
        actual = strings_value(root / "Maso" / "Resources" / f"{folder}.lproj" / "Localizable.strings", "Restore Purchase")
        if actual != expected:
            restore_mismatches.append({"language": language, "test": expected, "strings": actual})
    subscription_copy = {
        language: strings_value(root / "Maso" / "Resources" / f"{folder}.lproj" / "Localizable.strings", "No active subscription found")
        for language, folder in (("en", "en"), ("zh-Hans", "zh-Hans"))
    }
    focused_copy = {
        language: {
            key: strings_value(root / "Maso" / "Resources" / f"{folder}.lproj" / "Localizable.strings", key)
            for key in ("Share", "Workout report")
        }
        for language, folder in (("en", "en"), ("zh-Hans", "zh-Hans"))
    }
    whats_new = {
        locale: (CANDIDATE / "review-only" / locale / "whats_new.txt").read_text(encoding="utf-8")
        for locale in WHATS_NEW
    }
    store = {
        "en-US": {
            "name": (CANDIDATE / "after" / "en-US" / "name.txt").read_text(encoding="utf-8"),
            "subtitle": (CANDIDATE / "after" / "en-US" / "subtitle.txt").read_text(encoding="utf-8"),
            "keywords": (CANDIDATE / "after" / "en-US" / "keywords.txt").read_text(encoding="utf-8"),
        },
        "zh-Hans": {
            "name": (CANDIDATE / "after" / "zh-Hans" / "name.txt").read_text(encoding="utf-8"),
            "subtitle": (CANDIDATE / "after" / "zh-Hans" / "subtitle.txt").read_text(encoding="utf-8"),
        },
    }
    aso = run_aso()
    aso_self = run_aso("--self-test")
    ui_source = {
        name: (root / "MasoUITests" / name).read_text(encoding="utf-8")
        for name in ("PaywallUITests.swift", "SessionReportUITests.swift")
    }
    unit_source = (root / "MasoTests" / "SubscriptionTests.swift").read_text(encoding="utf-8")
    return {
        "versions": versions,
        "version_doc": version_doc,
        "project_yml": project_yml,
        "pbx": pbx,
        "file_hashes": {relative: sha256(root / relative) for relative in FILE_HASHES},
        "tracked_secret_configs": [path for path in tracked if path.endswith("Secrets.xcconfig")],
        "tracked_package_resolved": [path for path in tracked if path.endswith("Package.resolved")],
        "lock_state": lock_state,
        "restore_mismatches": restore_mismatches,
        "subscription_copy": subscription_copy,
        "focused_copy": focused_copy,
        "whats_new": whats_new,
        "store": store,
        "aso_status": aso.get("status"),
        "aso_errors": aso.get("errors", []),
        "aso_self_status": aso_self.get("status"),
        "aso_self_tests": aso_self.get("tests"),
        "paywall_storekit_sessions": ui_source["PaywallUITests.swift"].count("SKTestSession(contentsOf:"),
        "subscription_storekit_sessions": unit_source.count("SKTestSession(contentsOf:"),
        "session_report_storekit_sessions": ui_source["SessionReportUITests.swift"].count("SKTestSession("),
        "session_report_tests": re.findall(r"func (test\w+)", ui_source["SessionReportUITests.swift"]),
    }


def evaluate(model: dict) -> list[str]:
    errors = []

    def check(ok: bool, message: str) -> None:
        if not ok:
            errors.append(message)

    for relative, expected_display in DISPLAY_NAMES.items():
        found = model["versions"].get(relative, {})
        check(found.get("short") == EXPECTED_SHORT, f"{relative} short version is {found.get('short')}")
        check(found.get("build") == EXPECTED_BUILD, f"{relative} build is {found.get('build')}")
        check(found.get("display") == expected_display, f"{relative} display name changed")
        check(found.get("display") not in STORE_NAMES.values(), f"{relative} display name copied from the store name")
    document = model["version_doc"]
    check(document.get("marketing_version") == EXPECTED_SHORT, "version document marketing version")
    check(document.get("bundle_version_candidate") == EXPECTED_BUILD, "version document build")
    check(document.get("bundle_version_status") == BUILD_STATUS, "build 55 must stay pending live ASC confirmation")
    check(document.get("highest_known_uploaded_build") == "54", "highest known build drifted")
    for relative, expected in FILE_HASHES.items():
        check(model["file_hashes"].get(relative) == expected, f"identity file changed: {relative}")
    yml = model["project_yml"]
    pbx = model["pbx"]
    check(f"DEVELOPMENT_TEAM: {TEAM}" in yml, "project.yml team changed")
    check(pbx.count(f"DEVELOPMENT_TEAM = {TEAM};") == 2, "pbxproj team count changed")
    for bundle_id in BUNDLE_IDS.values():
        check(bundle_id in yml and bundle_id in pbx, f"bundle id missing: {bundle_id}")
    check("from: \"1.6.4\"" in yml, "project.yml no longer declares MuscleMap from 1.6.4")
    check("minimumVersion = 1.6.4;" in pbx, "pbxproj MuscleMap minimum changed")
    check("kind = upToNextMajorVersion;" in pbx, "pbxproj MuscleMap requirement kind changed")
    check(MUSCLEMAP_REVISION not in yml and MUSCLEMAP_REVISION not in pbx, "revision was copied into the project without the lockfile")
    check(model["tracked_secret_configs"] == [], "Secrets.xcconfig is tracked")
    check(model["tracked_package_resolved"] == [], "Package.resolved is tracked")
    check(model["lock_state"] in {"absent", LOCK_SHA}, "Package.resolved is present but is not the historical lock")
    check(model["restore_mismatches"] == [], "Restore Purchase localization does not match PaywallUITests")
    check(model["subscription_copy"].get("en") == "No active subscription found", "English empty-restore copy missing")
    check(model["subscription_copy"].get("zh-Hans") == "未找到有效订阅", "Chinese empty-restore copy missing")
    check(model["focused_copy"].get("en", {}).get("Share") == "Share", "English Share copy missing")
    check(model["focused_copy"].get("zh-Hans", {}).get("Share") == "分享", "Chinese Share copy missing")
    check(model["focused_copy"].get("en", {}).get("Workout report") == "Workout Summary", "English report title missing")
    check(model["focused_copy"].get("zh-Hans", {}).get("Workout report") == "训练总结", "Chinese report title missing")
    for locale, expected in WHATS_NEW.items():
        actual = model["whats_new"].get(locale, "")
        check(actual == expected, f"What's New changed: {locale}")
        lowered = actual.lower()
        check("修复" not in actual and "bug" not in lowered and "fixed" not in lowered, f"What's New claims a fix: {locale}")
    check(model["store"]["en-US"]["name"] == STORE_NAMES["en-US"], "en-US store name changed")
    check(model["store"]["en-US"]["subtitle"] == "AI Plans & 3D Muscle Recovery", "en-US subtitle changed")
    check(model["store"]["en-US"]["keywords"] == EN_KEYWORDS, "en-US keywords changed")
    check(len(EN_KEYWORDS) == 97 and EN_KEYWORDS.isascii(), "en-US keywords are not the 97-ASCII candidate")
    check(model["store"]["zh-Hans"]["name"] == STORE_NAMES["zh-Hans"], "zh-Hans store name changed")
    check(model["store"]["zh-Hans"]["subtitle"] == ZH_SUBTITLE, "zh-Hans subtitle changed")
    check(model["aso_status"] == "PASS" and model["aso_errors"] == [], "approved ASO bundle failed validation")
    check(model["aso_self_status"] == "PASS" and model["aso_self_tests"] == 7, "ASO self-test failed")
    check(model["paywall_storekit_sessions"] == 2, "PaywallUITests StoreKit session setup changed")
    check(model["subscription_storekit_sessions"] == 4, "SubscriptionTests StoreKit session count changed")
    check(model["session_report_storekit_sessions"] == 0, "SessionReportUITests unexpectedly depends on StoreKitTest")
    for name in (
        "testAggregateRowsAndNativeSharePreviewAcrossLanguages",
        "testFinishExitLeavesTheReportAndHistoryUsesBack",
        "testFinishedReportExitsThroughProductionRootAndCanStartAgain",
        "testHomeStartButtonOpensThePlayer",
    ):
        check(name in model["session_report_tests"], f"missing session-report gate {name}")
    return errors


def self_test() -> dict:
    model = collect()
    baseline = evaluate(model)
    if baseline:
        raise ValueError("Baseline failed: " + repr(baseline))
    mutations = []

    def mutated(**updates):
        copy = json.loads(json.dumps(model))
        copy.update(updates)
        return copy

    cases = [
        ("old version", mutated(versions={**model["versions"], "Maso/Info.plist": {**model["versions"]["Maso/Info.plist"], "short": "3.0.2"}}), "short version"),
        ("store display name", mutated(versions={**model["versions"], "Maso/Info.plist": {**model["versions"]["Maso/Info.plist"], "display": STORE_NAMES["en-US"]}}), "display name"),
        ("tracked secret", mutated(tracked_secret_configs=["Maso/Secrets.xcconfig"]), "Secrets.xcconfig is tracked"),
        ("wrong lock", mutated(lock_state="0" * 64), "historical lock"),
        ("tracked lock", mutated(tracked_package_resolved=[LOCK_RELATIVE]), "Package.resolved is tracked"),
        ("upgrade declaration", mutated(project_yml=model["project_yml"].replace("from: \"1.6.4\"", "from: \"1.9.0\"")), "from 1.6.4"),
        ("invented fix", mutated(whats_new={**model["whats_new"], "en-US": model["whats_new"]["en-US"] + " Fixed a crash."}), "claims a fix"),
        ("aso failure", mutated(aso_status="FAIL", aso_errors=["tail changed"]), "ASO bundle"),
    ]
    for name, changed, expected in cases:
        found = evaluate(changed)
        if not any(expected in error for error in found):
            raise ValueError(f"Mutation was not detected: {name}")
        mutations.append(name)
    return {"status": "PASS", "tests": 1 + len(mutations), "mutations": mutations}


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        print(json.dumps(self_test(), ensure_ascii=False, indent=2))
        return 0
    if len(sys.argv) != 1:
        print(json.dumps({"status": "FAIL", "error": "Use no arguments or --self-test"}, ensure_ascii=False))
        return 2
    model = collect()
    errors = evaluate(model)
    public = {
        "status": "FAIL" if errors else "PASS",
        "errors": errors,
        "marketing_version": EXPECTED_SHORT,
        "bundle_version_candidate": EXPECTED_BUILD,
        "bundle_version_status": BUILD_STATUS,
        "lock_state": model["lock_state"],
        "historical_lock_sha256": LOCK_SHA,
        "musclemap_revision_statement": MUSCLEMAP_REVISION,
        "musclemap_requirement": "from 1.6.4 / upToNextMajorVersion, unchanged",
        "aso_status": model["aso_status"],
        "aso_self_test": model["aso_self_status"],
        "paywall_storekit_session_constructors": model["paywall_storekit_sessions"],
        "subscription_storekit_session_constructors": model["subscription_storekit_sessions"],
        "session_report_storekit_constructors": model["session_report_storekit_sessions"],
        "session_report_tests": model["session_report_tests"],
        "native_compilation": "not run; this checker is static",
        "network": "none by this checker; ASO validator is offline",
        "writes": "none",
    }
    print(json.dumps(public, ensure_ascii=False, indent=2))
    return int(bool(errors))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, ensure_ascii=False))
        sys.exit(1)
