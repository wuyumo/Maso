#!/bin/bash
set -euo pipefail
python3 scripts/low_memory_build.py sim-prepare CD4768FB-469C-48BE-AB5E-2697DC81C483
python3 scripts/low_memory_build.py xcodebuild --ui -- -project Maso.xcodeproj -scheme MasoExerciseUI -configuration Debug -destination 'platform=iOS Simulator,id=CD4768FB-469C-48BE-AB5E-2697DC81C483' -derivedDataPath build/DerivedData-ProSource48-Simulator ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CURRENT_PROJECT_VERSION=51 MARKETING_VERSION=3.0.2 -collect-test-diagnostics never -only-testing:MasoUITests/CoachEquipmentSwapUITests/testMachineChestPressChineseEnglishAndTraditionalNativeSource -resultBundlePath docs/pro-red51-20261113/red-three51.xcresult test
