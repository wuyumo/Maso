#!/usr/bin/env bash
# Maso App Store 截图自动化脚本.
#
# App Store 要求 iPhone 6.7" 截图 (1290 × 2796) — iPhone 15 Pro Max Simulator 自带这个尺寸.
# 这个脚本:
#   1. 启动 iPhone 15 Pro Max Simulator (或别的 6.7" device)
#   2. 装最新 Debug build
#   3. 开 app, 提示你手动操作每一屏
#   4. 每按 Enter 截一张图到 build/screenshots/
#
# 不自动跑 navigation — 真截图需要真实数据 (训练计划 / 历史 / 完成态), 自动化 nav 容易出错;
# 这个脚本只负责"装好 + 起好 simulator + 截图保存到正确位置", nav 你来按手机.
#
# 使用:
#   ./scripts/screenshot_simulator.sh
#
# 拍完所有图后, 文件在 build/screenshots/, 直接拖进 App Store Connect.

set -eu  # 不开 pipefail — grep 没命中时 silent exit 隐藏不了错误

# ━━━ 配置 ━━━
# 默认用 iPhone 17 Pro Max (6.9" 屏, App Store 接受为 6.7"+ 类别).
# 如果你装的别的型号, export DEVICE_NAME=... 跑脚本.
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro Max}"
OUTPUT_DIR="build/screenshots"
BUNDLE_ID="com.maso.app"
SCHEME="Maso"
PROJECT="Maso.xcodeproj"

# 想拍多语言版本就改这里 — Apple Store 每种语言可以放各自的截图.
LANGUAGE="${1:-en-US}"   # 调用 ./screenshot_simulator.sh zh-Hans 切中文版

# ━━━ 实际逻辑 ━━━

mkdir -p "$OUTPUT_DIR/$LANGUAGE"
echo "📸 Output directory: $OUTPUT_DIR/$LANGUAGE"
echo "🌍 Language: $LANGUAGE"
echo "📱 Device: $DEVICE_NAME"
echo ""

# 找 Simulator UDID
DEVICE_UDID=$(xcrun simctl list devices available | grep -E "$DEVICE_NAME \(" | head -1 | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()')
if [ -z "$DEVICE_UDID" ]; then
    echo "❌ Cannot find simulator: $DEVICE_NAME"
    echo "   Available devices:"
    xcrun simctl list devices available | grep iPhone | head -20
    exit 1
fi
echo "✓ Simulator UDID: $DEVICE_UDID"

# 启动 Simulator (如果没开)
SIM_STATE=$(xcrun simctl list devices | grep "$DEVICE_UDID" | grep -oE 'Booted|Shutdown' | head -1)
if [ "$SIM_STATE" != "Booted" ]; then
    echo "🚀 Booting simulator..."
    xcrun simctl boot "$DEVICE_UDID"
    open -a Simulator
    sleep 3
fi

# 设置 Simulator 语言
echo "🌍 Setting language to $LANGUAGE..."
xcrun simctl spawn "$DEVICE_UDID" defaults write -g AppleLanguages -array "$LANGUAGE"
xcrun simctl spawn "$DEVICE_UDID" defaults write -g AppleLocale "$LANGUAGE"

# Build for simulator
echo "🔨 Building for Simulator..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE_UDID" \
    -derivedDataPath "build/DerivedData" \
    build > /dev/null 2>&1

# 装 app
APP_PATH="build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build product not found: $APP_PATH"
    exit 1
fi
echo "📦 Installing app..."
xcrun simctl install "$DEVICE_UDID" "$APP_PATH"

# 启动
echo "▶️  Launching app..."
xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$DEVICE_UDID" "$BUNDLE_ID"
sleep 2

# Status bar — 把状态栏调成 9:41 (App Store screenshot 标准)
echo "🕘 Pinning status bar to 9:41..."
xcrun simctl status_bar "$DEVICE_UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularMode active \
    --cellularBar 4 \
    --wifiBars 3 \
    --operatorName ""

# 截图循环
SHOTS=(
    "01-today.png|Today tab — recommended workout card"
    "02-plan-detail.png|Plan detail with steps list"
    "03-training.png|Training in progress (exercise stage)"
    "04-rest.png|Training rest stage (countdown ring)"
    "05-history.png|History tab — muscle status + session list"
    "06-completed.png|Workout complete + share entry"
    "07-quick-workout.png|Quick workout — muscle picker"
    "08-share.png|Share card preview"
)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Now: navigate the app manually in the Simulator."
echo "After each screen is ready, hit Enter to capture."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for entry in "${SHOTS[@]}"; do
    filename="${entry%%|*}"
    description="${entry#*|}"
    out="$OUTPUT_DIR/$LANGUAGE/$filename"

    echo ""
    echo "→ $description"
    echo "  Navigate to that screen in Simulator, then press Enter (or 's' to skip)..."
    read -r choice
    if [ "$choice" = "s" ] || [ "$choice" = "skip" ]; then
        echo "  ⊘ skipped"
        continue
    fi

    xcrun simctl io "$DEVICE_UDID" screenshot "$out"
    echo "  ✓ saved: $out"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 All done."
echo "Screenshots: $OUTPUT_DIR/$LANGUAGE/"
echo ""
echo "Tips for App Store Connect:"
echo "  • iPhone 6.7\" set is sufficient (covers iPhone 14/15/16 Plus / Pro Max)"
echo "  • Apple auto-scales these for iPhone 6.5\" set too"
echo "  • Order matters: first 3 screenshots show on Search results"
echo "  • Drop them into App Store Connect → App → 1.0 Prepare for Submission"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 清掉 status bar override (恢复 Simulator 自然状态)
xcrun simctl status_bar "$DEVICE_UDID" clear
