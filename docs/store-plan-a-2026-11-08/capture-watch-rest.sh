#!/bin/bash
# Apple Watch rest screen at the marketing fixture 160 bpm (not a sensor reading).
#   python3 scripts/low_memory_build.py run -- bash docs/store-plan-a-2026-11-08/capture-watch-rest.sh
#
# CAPTURE_LANGS, when set, replaces zh-Hans zh-Hant en ja. zh-Hans is stored as "zh".
# Do not include languages whose rest-160.png should be kept.
# Does not pair or unpair. Uses Watch Series 11 3915EE74-D7CB-460F-BB9D-28E841D3A080 only.
set -euo pipefail
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

python3 scripts/low_memory_build.py sim-prepare "$WATCH"
xcrun simctl install "$WATCH" build/DerivedData/Build/Products/Debug-watchsimulator/MasoWatch.app
for lang in "${LANGS[@]}"; do
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
