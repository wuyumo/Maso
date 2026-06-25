#!/usr/bin/env bash
# Maso — 夜间自动流水线 (launchd @ 23:00).
#
# 做的是「绿了通知我」那一档 (Yumo 2026-06-24 选定):
#   1. verify-app 烟测 (xcodegen + 编译 + 数据 + 各关键页渲染断言)
#   2. 装到 iPhone (best-effort — 手机没插就跳过, 不算失败)
#   3. 写报告 build/nightly/latest.md + 弹 macOS 通知
#
# 故意【不做】上传 / 提交审核 —— App Store 审核是 24-48h 且同时只能有一个版本在审,
# 不适合每晚提交; 而且无人值守上传需要 ASC API 密钥 (Yumo 暂未配)。
# 发版那一步留给交互式跑: 跟 Claude 说一句「提交」, 它会 bump build → 归档上传
# → 填元数据 → Yumo 一键确认 → 提交审核。
#
# 退出码: 0 = verify 通过 · 1 = verify 失败 (报告 + 通知都会说明)。

# launchd 的 PATH 极简, 补上 node / xcrun 等可能落脚的目录.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="/Users/yumowu/Projects/Maso-iOS"
SIM="5617AC82-D030-4E55-8A5D-26A3067DF06E"   # 固定模拟器 (项目惯用, 见 CLAUDE.md)
cd "$REPO" || exit 1

OUTDIR="$REPO/build/nightly"
mkdir -p "$OUTDIR"
STAMP="$(date '+%Y-%m-%d %H:%M')"
DAY="$(date '+%Y%m%d')"
LOG="$OUTDIR/$DAY.log"
MD="$OUTDIR/latest.md"

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Maso/Info.plist 2>/dev/null)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Maso/Info.plist 2>/dev/null)"

note()   { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" >/dev/null 2>&1 || true; }

: > "$LOG"
note "=== Maso nightly $STAMP — v$VER ($BUILD) ==="

# 先把固定模拟器 boot 起来, 让 driver.sh 直接挑这台 (避免设备名漂移).
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM" >>"$LOG" 2>&1
xcrun simctl bootstatus "$SIM" -b >>"$LOG" 2>&1

# 1) verify-app 烟测
note "running verify-app driver..."
VERIFY_OK=1
if bash .claude/skills/verify-app/driver.sh >>"$LOG" 2>&1; then
  note "verify-app: PASS"
else
  VERIFY_OK=0
  note "verify-app: FAIL (see log)"
fi

# 2) 装机 (best-effort)
note "installing to iPhone (best-effort)..."
INSTALL="未装 (iPhone 不在线?)"
if bash scripts/install_iphone.sh >>"$LOG" 2>&1; then
  INSTALL="已装机 ✅"
  note "install: OK"
else
  note "install: skipped/failed"
fi

# 3) 工作区改动概况 (待发版的本地改动)
DIRTY="$(git status --porcelain 2>/dev/null | grep -vc '^?? build/' || echo '?')"

# 4) 报告
{
  echo "# Maso 夜间构建 — $STAMP"
  echo ""
  echo "- 版本: **$VER ($BUILD)**"
  if [ "$VERIFY_OK" = "1" ]; then echo "- 验证 (verify-app): ✅ 通过"; else echo "- 验证 (verify-app): ❌ 失败 — 看 \`build/nightly/$DAY.log\`"; fi
  echo "- 装机: $INSTALL"
  echo "- 工作区改动文件数: $DIRTY"
  echo ""
  if [ "$VERIFY_OK" = "1" ]; then
    echo "> 构建是绿的, 最新版已尝试装到你 iPhone。要发版时跟 Claude 说一句「提交」即可"
    echo "> (它会 bump build → 归档上传 → 填 What's New/关键词 → 你一键确认 → 提交审核)。"
  else
    echo "> ⚠️ 构建没过, 别发版。把 \`build/nightly/$DAY.log\` 给 Claude 看。"
  fi
} > "$MD"

# 5) 通知
if [ "$VERIFY_OK" = "1" ]; then
  notify "Maso 夜间构建 ✅" "v$VER($BUILD) 验证通过 · $INSTALL · 待发版改动 $DIRTY 处。要发版跟 Claude 说「提交」。"
else
  notify "Maso 夜间构建 ❌" "v$VER($BUILD) 验证失败, 看 build/nightly/$DAY.log。别发版。"
fi

note "=== done (verify_ok=$VERIFY_OK) ==="
[ "$VERIFY_OK" = "1" ]
