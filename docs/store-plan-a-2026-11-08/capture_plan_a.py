#!/usr/bin/env python3
"""Plan A captures: the merged training page (player + 160 bpm card) and the progress page.

Writes straight into the Studio asset folder, next to the existing captures:
  public/screenshots/localized/iphone/<locale>/player-heart-warning.png
  public/screenshots/localized/iphone/<locale>/insights-progress.png

Synthetic fixture data only — same DEBUG launch mode the published captures use.
Nothing is installed in Release, nothing is uploaded.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import shutil
import uuid
from pathlib import Path

from PIL import Image, ImageStat

SIM = os.environ["SIM"]
FAMILY = os.environ.get("CAPTURE_FAMILY", "iphone")
PUBLIC = Path("design/app-store-studio-2026-10-29/public/screenshots/localized")
APP = "build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app"
LANGS = [lang for lang in os.environ.get("CAPTURE_LANGS", "zh-Hans zh-Hant en ja").split() if lang]
SCENES = [scene for scene in os.environ.get("CAPTURE_SCENES", "player-heart-warning insights-progress").split() if scene]
UNKNOWN = sorted(set(SCENES) - {"player-heart-warning", "insights-progress"})
if UNKNOWN:
    raise SystemExit(f"unknown CAPTURE_SCENES: {UNKNOWN}")
EXPECTED = (1206, 2622)


def call(*args, env=None):
    return subprocess.check_output(["xcrun", "simctl", *args], env=env, text=True).strip()


def capture(lang, scene, env_extra, out_path, wait_ready=True, settle=1.0, attempts=12):
    nonce = str(uuid.uuid4())
    env = dict(os.environ)
    env.update(
        {
            "SIMCTL_CHILD_MASO_SCREENSHOT_CAPTURE": "1",
            "SIMCTL_CHILD_MASO_CAPTURE_NONCE": nonce,
            "SIMCTL_CHILD_MASO_SHOWCASE_SEED": "1",
        }
    )
    env.update({k: v for k, v in env_extra.items()})
    call(
        "launch",
        "--terminate-running-process",
        SIM,
        "com.yumowu.maso",
        "-maso.selectedLanguage",
        lang,
        "-AppleLanguages",
        "(" + lang + ")",
        "-AppleLocale",
        lang,
        env=env,
    )
    deadline = time.monotonic() + 180
    if wait_ready:
        ready = documents / ("capture-ready-" + nonce + ".json")
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(0.25)
        if not ready.exists():
            raise RuntimeError(("destination did not mount", lang, scene))
        signal = json.loads(ready.read_text())
        if signal.get("nonce") != nonce or signal.get("language") != lang:
            raise RuntimeError(("readiness mismatch", signal, lang))
        ready.unlink()
    time.sleep(settle)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(attempts):
        call("io", SIM, "screenshot", str(out_path))
        im = Image.open(out_path).convert("RGB")
        if im.size != EXPECTED:
            raise RuntimeError(("wrong size", im.size, lang, scene))
        stat = ImageStat.Stat(im.crop((im.width * 0.1, im.height * 0.16, im.width * 0.9, im.height * 0.88)).resize((100, 100)))
        if sum(stat.stddev) >= 25 and sum(stat.mean) >= 15:
            break
        time.sleep(1)
    else:
        raise RuntimeError(("blank capture", lang, scene))
    print("CAPTURED", lang, scene, out_path, flush=True)


call("install", SIM, APP)
container = Path(call("get_app_container", SIM, "com.yumowu.maso", "data"))
documents = container / "Documents"
prefs = container / "Library/Preferences/com.yumowu.maso.plist"
backup = Path(tempfile.mkdtemp(prefix="masso-plan-a-"))
shutil.copytree(documents, backup / "Documents")
if prefs.exists():
    shutil.copy2(prefs, backup / "preferences.plist")

try:
    call(
        "status_bar",
        SIM,
        "override",
        "--time",
        "9:41",
        "--dataNetwork",
        "wifi",
        "--wifiMode",
        "active",
        "--wifiBars",
        "3",
        "--batteryState",
        "charged",
        "--batteryLevel",
        "100",
    )
    for lang in LANGS:
        web = "zh" if lang == "zh-Hans" else lang
        # Marketing fixture, not a sensor or model result: player with the heart card
        # at 185 bpm against the 155 personal reminder limit, bench press machine.
        if "player-heart-warning" in SCENES:
            capture(
                lang,
                "player-heart-warning",
                {
                    "SIMCTL_CHILD_MASO_EXERCISE_UI_TEST_SCENE": "stable-player",
                    "SIMCTL_CHILD_MASO_WORKOUT_HEART_FIXTURE": "1",
                    "SIMCTL_CHILD_MASO_MARKETING_EXERCISE_ID": "bench_press_machine",
                    "SIMCTL_CHILD_MASO_TEST_HEART_BPM": "185",
                    "SIMCTL_CHILD_MASO_TEST_HEART_LIMIT": "155",
                    "SIMCTL_CHILD_MASO_WORKOUT_HEART_CARD": "1",
                },
                PUBLIC / "iphone" / web / "player-heart-warning.png",
                wait_ready=False,
                settle=6.0,
            )
        # Progress page: a full synthetic week so every muscle group has recorded sets.
        if "insights-progress" in SCENES:
            capture(
                lang,
                "insights-progress",
                {
                    "SIMCTL_CHILD_MASO_SHOWCASE": "insights",
                    "SIMCTL_CHILD_MASO_MARKETING_PROGRESS": "1",
                    "SIMCTL_CHILD_MASO_MARKETING_INSIGHTS_RANGE": "fourWeeks",
                },
                PUBLIC / "iphone" / web / "insights-progress.png",
            )
finally:
    try:
        call("terminate", SIM, "com.yumowu.maso")
    except Exception:
        pass
    shutil.rmtree(documents, ignore_errors=True)
    shutil.copytree(backup / "Documents", documents)
    if (backup / "preferences.plist").exists():
        shutil.copy2(backup / "preferences.plist", prefs)
    shutil.rmtree(backup, ignore_errors=True)
