#!/usr/bin/env bash
# 全自动 App Store 截图: 种子数据 (MASO_SHOWCASE_SEED) + showcase 路由逐屏截.
# 用法: ./scripts/shoot_screenshots_auto.sh <sim-udid> <lang> <locale>
#   en: ./scripts/shoot_screenshots_auto.sh <udid> en-US en_US
#   zh: ./scripts/shoot_screenshots_auto.sh <udid> zh-Hans zh_CN
set -eu
SIM="$1"; LANG_TAG="$2"; LOCALE="${3:-en_US}"
APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app"
OUT="build/screenshots/$LANG_TAG"; mkdir -p "$OUT"
xcrun simctl bootstatus "$SIM" -b >/dev/null
# 卸载重装 — 清掉 app 容器里的语言/数据残留, 语言由启动参数决定
xcrun simctl uninstall "$SIM" com.yumowu.maso 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
shoot() { # $1 showcase-mode  $2 filename  $3 settle-seconds
  xcrun simctl terminate "$SIM" com.yumowu.maso 2>/dev/null || true
  SIMCTL_CHILD_MASO_SHOWCASE_SEED=1 SIMCTL_CHILD_MASO_SHOWCASE="$1" \
    xcrun simctl launch "$SIM" com.yumowu.maso \
      -AppleLanguages "($LANG_TAG)" -AppleLocale "$LOCALE" >/dev/null
  sleep "$3"
  xcrun simctl io "$SIM" screenshot "$OUT/$2.png" >/dev/null
  echo "  ✓ $2"
}
shoot ""             01-today         7
shoot "routines"     02-routines      9
shoot "exercises"    03-exercises     8
shoot "plan_detail"  04-plan-detail   8
shoot "player"       05-training      9
shoot "rest"         06-rest          10
shoot "history"      07-history       7
shoot "free_workout" 08-quick-workout 8
echo "DONE → $OUT"
