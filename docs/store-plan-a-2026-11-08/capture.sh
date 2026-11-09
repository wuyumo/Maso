#!/bin/bash
# Plan A captures inside the managed low-memory workflow.
#   bash docs/store-plan-a-2026-11-08/capture.sh
# runs via: python3 scripts/low_memory_build.py run -- bash docs/store-plan-a-2026-11-08/capture.sh
set -euo pipefail
PHONE=CD4768FB-469C-48BE-AB5E-2697DC81C483
WATCH=3915EE74-D7CB-460F-BB9D-28E841D3A080
PUBLIC=design/app-store-studio-2026-10-29/public/screenshots/localized

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
for lang in zh-Hans zh-Hant en ja; do
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
