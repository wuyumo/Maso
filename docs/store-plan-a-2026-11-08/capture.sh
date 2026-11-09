#!/bin/bash
# Plan A captures inside the managed low-memory workflow.
#   bash docs/store-plan-a-2026-11-08/capture.sh
# runs via: python3 scripts/low_memory_build.py run -- bash docs/store-plan-a-2026-11-08/capture.sh
#
# CAPTURE_LANGS, when set, replaces the default four languages (Apple language ids).
# zh-Hans is written to the folder "zh". Leave the four already-captured languages
# out of CAPTURE_LANGS or those PNGs are overwritten.
# CAPTURE_SCENES, when set, is forwarded to capture_plan_a.py
# (default there: player-heart-warning and insights-progress).
#
# This script never pairs or unpairs. Phone shots use iPhone 17 Pro
# CD4768FB-469C-48BE-AB5E-2697DC81C483. Watch shots use Watch Series 11
# 3915EE74-D7CB-460F-BB9D-28E841D3A080 and leave its current pair alone.
set -euo pipefail
PHONE=CD4768FB-469C-48BE-AB5E-2697DC81C483
WATCH=3915EE74-D7CB-460F-BB9D-28E841D3A080
PUBLIC=design/app-store-studio-2026-10-29/public/screenshots/localized
if [ -n "${CAPTURE_LANGS:-}" ]; then
  read -r -a LANGS <<< "$CAPTURE_LANGS"
else
  LANGS=(zh-Hans zh-Hant en ja)
fi

python3 - << 'PY'
import pathlib, re, sys
p = pathlib.Path("scripts/low_memory_build.py")
if not p.is_file():
    sys.exit("refusing: scripts/low_memory_build.py is not in this working tree")
for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
    code = line.split("#", 1)[0]
    if re.search(r"""simctl["']?\s*,\s*["'](?:pair|unpair)["']""", code) or re.search(r"\bsimctl\s+(?:pair|unpair)\b", code):
        sys.exit(f"refusing: {p}:{n} invokes simctl pair/unpair")
PY

python3 scripts/low_memory_build.py sim-prepare "$PHONE"
SIM="$PHONE" CAPTURE_FAMILY=iphone python3 docs/store-plan-a-2026-11-08/capture_plan_a.py
xcrun simctl shutdown "$PHONE" >/dev/null 2>&1 || true

python3 scripts/low_memory_build.py sim-prepare "$WATCH"
xcrun simctl install "$WATCH" build/DerivedData/Build/Products/Debug-watchsimulator/MasoWatch.app
# Same 9:41 clock as the phone capture; a different time on the two devices reads as two
# sessions. watchOS simulators may refuse the override — report the real reason and keep going.
if ! out=$(xcrun simctl status_bar "$WATCH" override --time "9:41" --batteryState charged --batteryLevel 100 2>&1); then
  echo "watch status bar override unavailable: ${out:-no message}"
fi
for lang in "${LANGS[@]}"; do
  web=$lang
  if [ "$lang" = zh-Hans ]; then web=zh; fi
  mkdir -p "$PUBLIC/watch/$web"
  # Mirror the phone capture one to one: same exercise, set 1/3, 8 reps, 60 kg, 185 bpm vs
  # the 155 personal limit, so page 3 describes a single moment across both devices.
  SIMCTL_CHILD_MASSO_WATCH_PREVIEW=exercise \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_HEART=1 \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_BPM=185 \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_EXERCISE=bench_press_machine \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_REPS=8 \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_WEIGHT=60 \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_SET=1 \
    xcrun simctl launch --terminate-running-process "$WATCH" com.yumowu.maso.watchkitapp -AppleLanguages "($lang)" -AppleLocale "$lang"
  sleep 4
  xcrun simctl io "$WATCH" screenshot "$PUBLIC/watch/$web/exercise-185.png"
  echo "CAPTURED watch $web"
done
