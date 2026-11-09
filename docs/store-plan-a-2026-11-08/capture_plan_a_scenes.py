#!/usr/bin/env python3
"""Re-capture the *shared* App scenes that the Plan A pages reuse, for one locale.

Pages 01/02/04/05 do not have their own capture step: they reuse the App screenshots
already sitting in the Studio asset folder (`today`, `muscle-selected`, `plans`, `diet`,
`sleep`, plus the `insights` screen the device-lineup page draws on the iPad). Those
files came from the 2026-11-06 batch, i.e. from the *old* machine-translated zh-Hant
bundle, so after the zh-Hant rebuild they still showed 「添加加餐」 / 「食用 1」 / 「胖子」.
This script re-takes exactly those scenes with the current bundle, using the same DEBUG
marketing fixture as `docs/store-all-refresh-2026-11-06/capture_ready.py`, and writes
them back into the Studio folder.

  SIM=<udid> [CAPTURE_FAMILY=iphone|ipad|duo] [CAPTURE_SCENES=diet,insights] \
    python3 docs/store-plan-a-2026-11-08/capture_plan_a_scenes.py [locale ...]

Synthetic fixture data only; nothing is installed in Release and nothing is uploaded.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

from PIL import Image, ImageStat

SIM = os.environ["SIM"]
FAMILY = os.environ.get("CAPTURE_FAMILY", "iphone")
PUBLIC = Path("design/app-store-studio-2026-10-29/public/screenshots/localized")
APP = "build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app"
EXPECTED = {"iphone": (1206, 2622), "ipad": (2064, 2752), "duo": (2007, 2853)}[FAMILY]
ROOT = Path("docs/store-all-refresh-2026-11-06")
REPORT_COPY = json.loads((ROOT / "report-copy.json").read_text())

# scene -> (studio filename, showcase route, extra fixture env)
SCENES = {
    "today": ("today.png", "", {}),
    "muscle-selected": ("muscle-selected.png", "muscle_status",
                        {"SIMCTL_CHILD_MASO_MARKETING_SELECTED_MUSCLE": "shoulders"}),
    "plans": ("plans.png", "coach_chat",
              {"SIMCTL_CHILD_MASO_MARKETING_COACH_NAVIGATION": "plans"}),
    # The device-lineup iPad shows the insights screen; the four-week seed fills the
    # muscle bars and the bench-press climb instead of an almost empty current week.
    "insights": ("insights.png", "insights",
                 {"SIMCTL_CHILD_MASO_MARKETING_PROGRESS": "1",
                  "SIMCTL_CHILD_MASO_MARKETING_INSIGHTS_RANGE": "fourWeeks"}),
    "diet": ("diet.png", "diet", {}),
    "sleep": ("sleep.png", "sleep", {}),
}
WANTED = [s for s in os.environ.get("CAPTURE_SCENES", "").split(",") if s] or list(SCENES)
LANGS = sys.argv[1:] or ["zh-Hant"]


def call(*args, env=None):
    return subprocess.check_output(["xcrun", "simctl", *args], env=env, text=True).strip()


call("install", SIM, APP)
container = Path(call("get_app_container", SIM, "com.yumowu.maso", "data"))
documents = container / "Documents"
prefs = container / "Library/Preferences/com.yumowu.maso.plist"
backup = Path(tempfile.mkdtemp(prefix="masso-plan-a-scenes-"))
shutil.copytree(documents, backup / "Documents")
if prefs.exists():
    shutil.copy2(prefs, backup / "preferences.plist")

# The Coach thread page needs a body photo in the fixture container.
photo = PUBLIC.parent / "apple/iphone/coach-body-front-back.png"
if photo.exists():
    shutil.copy2(photo, documents / "marketing-body-photo.jpg")
    print("fixture photo", photo.name, flush=True)

# A foldable's inner display is a separate IO port; screenshots must target it.
port = None
if FAMILY == "duo":
    ports = call("io", SIM, "enumerate").split("Port:")
    inner = [b for b in ports
             if "Default width: 2007" in b and "Default height: 2853" in b]
    if len(inner) != 1:
        raise RuntimeError(("unique native inner display required", len(inner)))
    port = re.search(r"UUID: ([A-F0-9-]+)", inner[0]).group(1)
    print("inner display port", port, flush=True)

try:
    call("status_bar", SIM, "override", "--time", "9:41", "--dataNetwork", "wifi",
         "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged",
         "--batteryLevel", "100")
    for lang in LANGS:
        web = "zh" if lang == "zh-Hans" else lang
        for scene in WANTED:
            filename, route, extra = SCENES[scene]
            nonce = str(uuid.uuid4())
            env = dict(os.environ)
            env.update({
                "SIMCTL_CHILD_MASO_SCREENSHOT_CAPTURE": "1",
                "SIMCTL_CHILD_MASO_CAPTURE_NONCE": nonce,
                "SIMCTL_CHILD_MASO_SHOWCASE_SEED": "1",
                "SIMCTL_CHILD_MASO_MARKETING_MORNING": "1",
                "SIMCTL_CHILD_MASO_MARKETING_GYM": "1",
                "SIMCTL_CHILD_MASO_MARKETING_MUSCLE": "1",
                "SIMCTL_CHILD_MASO_MARKETING_REAL_SCREENS": "1",
                "SIMCTL_CHILD_MASO_MARKETING_REPORT_TEXT": REPORT_COPY[lang],
                "SIMCTL_CHILD_MASO_SHOWCASE": route,
            })
            env.update(extra)
            call("launch", "--terminate-running-process", SIM, "com.yumowu.maso",
                 "-maso.selectedLanguage", lang,
                 "-AppleLanguages", "(" + lang + ")",
                 "-AppleLocale", lang, env=env)
            ready = documents / ("capture-ready-" + nonce + ".json")
            deadline = time.monotonic() + 180
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.25)
            if not ready.exists():
                raise RuntimeError(("destination did not mount", lang, scene))
            signal = json.loads(ready.read_text())
            if signal.get("nonce") != nonce or signal.get("language") != lang:
                raise RuntimeError(("readiness mismatch", signal, lang))
            if signal.get("scene") != (route or "today"):
                raise RuntimeError(("wrong scene", signal, lang, scene))
            ready.unlink()
            time.sleep(1.0)
            out = PUBLIC / FAMILY / web / filename
            out.parent.mkdir(parents=True, exist_ok=True)
            for _ in range(12):
                call("io", SIM, "screenshot", *(["--display=" + port] if port else []),
                     str(out))
                im = Image.open(out).convert("RGB")
                if im.size != EXPECTED:
                    raise RuntimeError(("wrong size", im.size, lang, scene))
                stat = ImageStat.Stat(im.crop((im.width * 0.1, im.height * 0.16,
                                               im.width * 0.9, im.height * 0.88))
                                      .resize((100, 100)))
                if sum(stat.stddev) >= 25 and sum(stat.mean) >= 15:
                    break
                time.sleep(1)
            else:
                raise RuntimeError(("blank capture", lang, scene))
            print("CAPTURED", FAMILY, lang, scene, out, flush=True)
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
