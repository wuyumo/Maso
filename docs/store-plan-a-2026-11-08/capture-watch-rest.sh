#!/bin/bash
# Apple Watch rest screen at the same 160 bpm as the training page phone capture.
#   python3 scripts/low_memory_build.py run -- bash docs/store-plan-a-2026-11-08/capture-watch-rest.sh
set -euo pipefail
WATCH=3915EE74-D7CB-460F-BB9D-28E841D3A080
PUBLIC=design/app-store-studio-2026-10-29/public/screenshots/localized
python3 scripts/low_memory_build.py sim-prepare "$WATCH"
xcrun simctl install "$WATCH" build/DerivedData/Build/Products/Debug-watchsimulator/MasoWatch.app
for lang in zh-Hans zh-Hant en ja; do
  web=$lang
  if [ "$lang" = zh-Hans ]; then web=zh; fi
  mkdir -p "$PUBLIC/watch/$web"
  SIMCTL_CHILD_MASSO_WATCH_PREVIEW=rest \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_HEART=1 \
  SIMCTL_CHILD_MASSO_WATCH_MARKETING_BPM=160 \
    xcrun simctl launch --terminate-running-process "$WATCH" com.yumowu.maso.watchkitapp -AppleLanguages "($lang)" -AppleLocale "$lang"
  sleep 4
  xcrun simctl io "$WATCH" screenshot "$PUBLIC/watch/$web/rest-160.png"
  echo "CAPTURED watch $web rest-160"
done
