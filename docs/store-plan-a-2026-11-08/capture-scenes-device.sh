#!/bin/bash
# Re-capture the shared App scenes the Plan A pages reuse, on the iPad / Duo.
# Boots one simulator inside the managed build lock, captures the requested scenes
# for the requested locales, then releases the device.
#
#   bash docs/store-plan-a-2026-11-08/capture-scenes-device.sh ipad insights zh-Hant
#   bash docs/store-plan-a-2026-11-08/capture-scenes-device.sh duo diet zh-Hant
set -euo pipefail
family=$1; scenes=$2; shift 2

case "$family" in
  iphone) sim=CD4768FB-469C-48BE-AB5E-2697DC81C483 ;;
  ipad) sim=B7FA50A7-2D85-42F9-83F9-34378020F4A4 ;;
  duo)  sim=52FA8324-79C2-4FF2-A101-FA91C96C46CB ;;
  *)    echo "unknown family: $family" >&2; exit 2 ;;
esac

python3 scripts/low_memory_build.py run -- \
  env FAMILY="$family" SCENES="$scenes" SIM="$sim" LOCALES="$*" bash -c '
set -euo pipefail
python3 scripts/low_memory_build.py sim-prepare "$SIM"
SIM="$SIM" CAPTURE_FAMILY="$FAMILY" CAPTURE_SCENES="$SCENES" \
  python3 docs/store-plan-a-2026-11-08/capture_plan_a_scenes.py $LOCALES
python3 scripts/low_memory_build.py sim-release
'
