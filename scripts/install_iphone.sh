#!/usr/bin/env bash
# Maso → 实机 iPhone 一键安装.
#
# 干啥:
#   1. 自动发现已连接的 iPhone (USB / Wi-Fi pair 都行)
#   2. 编译 Debug build (Maso.app for iphoneos)
#   3. devicectl 推到手机
#   4. 不自动启动 — 你自己手指点开 (省得 ssh-ish 行为搞乱 SwiftUI hot reload)
#
# 用法:
#   ./scripts/install_iphone.sh                    # 自动选第一台连着的 iPhone
#   ./scripts/install_iphone.sh "Yumo's iPhone"    # 指定设备名 (部分匹配)
#   ./scripts/install_iphone.sh --list             # 只列出连接的设备, 不装
#
# 前提:
#   - iPhone 解锁状态, 已"信任此电脑"
#   - project.yml 的 DEVELOPMENT_TEAM 是一个你 Xcode → Settings → Accounts 里已加的 Apple ID 的 Team
#   - Personal Team (免费): 7 天过期, 过期后重新跑这个脚本即可
#   - Paid Developer Team: 不过期 (但 Debug profile 仍然 30 天 refresh)

set -eu

# ━━━ 解析参数 ━━━
DEVICE_HINT=""
LIST_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --list|-l) LIST_ONLY=true ;;
        -h|--help)
            sed -n '2,/^set/p' "$0" | sed 's/^# \?//' | head -n -1
            exit 0 ;;
        -*) echo "❌ Unknown flag: $arg" >&2; exit 1 ;;
        *) DEVICE_HINT="$arg" ;;
    esac
done

# ━━━ 发现 iPhone ━━━
echo "🔍 Scanning connected devices..."
DEVICE_TABLE=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" || true)
if [ -z "$DEVICE_TABLE" ]; then
    echo "❌ No connected iPhone/iPad found."
    echo "   Make sure:"
    echo "   - Cable is plugged in (or Wi-Fi pair set up via Xcode → Devices)"
    echo "   - iPhone is unlocked and trusted this Mac"
    exit 1
fi

if [ "$LIST_ONLY" = true ]; then
    echo "Connected devices:"
    echo "$DEVICE_TABLE"
    exit 0
fi

# 匹配设备 — 如果给了 hint, 按 hint 过滤; 否则取第一台 iPhone
if [ -n "$DEVICE_HINT" ]; then
    DEVICE_LINE=$(echo "$DEVICE_TABLE" | grep -i "$DEVICE_HINT" | head -1 || true)
    if [ -z "$DEVICE_LINE" ]; then
        echo "❌ No device matching: $DEVICE_HINT"
        echo "Connected devices:"
        echo "$DEVICE_TABLE"
        exit 1
    fi
else
    DEVICE_LINE=$(echo "$DEVICE_TABLE" | grep iPhone | head -1 || echo "$DEVICE_TABLE" | head -1)
fi

# devicectl 输出格式:
#   Name                Hostname                              Identifier                            State       Model
#   Yumo's iPhone ...   yumos-iphone.coredevice.local         BFB1C437-2F15-5ACB-9364-E3CD058FF066  connected   iPhone 17 Pro (...)
DEVICE_UDID=$(echo "$DEVICE_LINE" | awk '{
    for (i=1; i<=NF; i++) if ($i ~ /^[A-F0-9]{8}-[A-F0-9]{4}-/) print $i
}' | head -1)

if [ -z "$DEVICE_UDID" ]; then
    echo "❌ Cannot parse device UDID from: $DEVICE_LINE"
    exit 1
fi

# 拿真实硬件 ID (xcodebuild destination 要的是 hardware UDID, 跟 devicectl 的 coredevice UUID 不一样).
# `xctrace list devices` 输出格式:
#   == Devices ==
#   Yumo's iPhone 18 Ultra (26.4.2) (00008150-000E4CD63AC0401C)   ← (...) 里是 hardware ID
#   ...
#   == Simulators ==
#   iPhone 16e (26.3.1) (96A5040E-5490-47BA-BD0A-FE7E684EBFE2)
#
# 用 awk 提取 "== Devices ==" 到 "== Simulators ==" 之间的物理设备区段,
# 再从中找一台 iPhone (跟 devicectl 找到的对应). 不靠 name fuzzy match — 设备名
# 里的 apostrophe / 非 ASCII 字符在不同 tool 输出里被替代成 ? 会导致 grep miss.
PHYSICAL_DEVICES=$(xcrun xctrace list devices 2>&1 | awk '/^== Devices ==$/{f=1;next} /^== Simulators ==$/{f=0} f')
HW_ID=$(echo "$PHYSICAL_DEVICES" | grep -i iPhone | head -1 | grep -oE '\([0-9A-F]{8}-[0-9A-F]{16}\)' | tr -d '()')
if [ -z "$HW_ID" ]; then
    # Fallback: 用 devicectl 那个 UUID — xcodebuild 17.0+ 支持 coredevice UUID,
    # 但实测有时还是不识别, 会 fallback 到 simulator build. 警告用户.
    echo "⚠️  Could not parse hardware ID from xctrace, falling back to devicectl UUID."
    echo "    If build silently goes to simulator, manually pass: -destination 'id=$DEVICE_UDID'"
    HW_ID="$DEVICE_UDID"
fi

# 解析设备显示名 (取行首到第一个 "  " 之前)
DEVICE_NAME=$(echo "$DEVICE_LINE" | awk -F'  ' '{print $1}' | xargs)
echo "✓ Target: $DEVICE_NAME"
echo "  Hardware ID: $HW_ID"
echo "  devicectl UUID: $DEVICE_UDID"

# ━━━ Build ━━━
echo ""
echo "🔨 Building Maso for device (Debug)..."
DERIVED="build/DerivedData-Device"
xcodebuild \
    -project Maso.xcodeproj \
    -scheme Maso \
    -configuration Debug \
    -destination "id=$HW_ID" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    build 2>&1 | tail -3

APP_PATH="$DERIVED/Build/Products/Debug-iphoneos/Maso.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build product not found: $APP_PATH"
    echo "   Re-run with full xcodebuild output to debug:"
    echo "   xcodebuild -project Maso.xcodeproj -scheme Maso -configuration Debug \\"
    echo "     -destination \"id=$HW_ID\" -derivedDataPath $DERIVED -allowProvisioningUpdates build"
    exit 1
fi

# ━━━ Install ━━━
echo ""
echo "📦 Installing to $DEVICE_NAME..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

echo ""
echo "✅ Installed."
echo ""
echo "Open Maso on your iPhone now."
echo ""
echo "If iOS shows 'Untrusted Developer':"
echo "  Settings → General → VPN & Device Management → trust your Apple Developer profile"
