#!/usr/bin/env bash
# 全自动 App Store 截图: 种子数据 (MASO_SHOWCASE_SEED) + showcase 路由逐屏截.
# 用法: ./scripts/shoot_screenshots_auto.sh <sim-udid> <lang> <locale>
#   en: ./scripts/shoot_screenshots_auto.sh <udid> en-US en_US
#   zh: ./scripts/shoot_screenshots_auto.sh <udid> zh-Hans zh_CN
# 6.9" 素材 (1320×2868) 要用 iPhone Pro Max 级模拟器跑.
set -eu
SIM="$1"; LANG_TAG="$2"; LOCALE="${3:-en_US}"
APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app"
OUT="build/screenshots/$LANG_TAG"; mkdir -p "$OUT"
xcrun simctl bootstatus "$SIM" -b >/dev/null
# 状态栏钉死 marketing 标准样 (9:41 / 满电 / 满格) — 不然每张时间都不一样.
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
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
# 2.0 IA: Coach 聊天是主打 (coach_chat 种子对话), Routines/Exercises tab 已并入 Coach.
shoot "coach_chat"      01-coach-chat    9
shoot ""                02-today         8
shoot "player"          03-training      9
shoot "rest"            04-rest          10
shoot "coach_templates" 05-templates     9
shoot "plan_detail"     06-plan-detail   8
shoot "history"         07-progress      8
shoot "exercises"       08-library       9
echo "DONE → $OUT"
