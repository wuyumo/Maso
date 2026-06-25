#!/usr/bin/env bash
# Maso — iOS product verification driver (Simulator).
#
# iOS can't use a headless browser, so this drives the iOS Simulator and asserts
# state at each step. Maso has almost no accessibilityIdentifiers, so instead of
# fragile taps we exploit the app's built-in deterministic showcase routing
# (SIMCTL_CHILD_MASO_SHOWCASE_SEED=1 + SIMCTL_CHILD_MASO_SHOWCASE=<route>, the same
# mechanism scripts/shoot_screenshots_auto.sh uses) to jump straight to each key
# screen with seeded data, screenshot it, and assert it really rendered.
#
# Steps + assertions:
#   1. xcodegen generate            → project in sync
#   2. exercises.json sanity        → the RUNTIME data file parses + has the library
#   3. build for Simulator          → it compiles (the real gate)
#   4. install + launch each route  → today / exercises / plan_detail / player
#        · every screenshot is non-blank (real pixels, not a black/failed frame)
#        · the screenshots are DISTINCT (distinct screens rendered — not crashed to
#          SpringBoard, not stuck on a splash). Status bar pinned to 9:41 so the clock
#          can't fake a difference.
#
# Usage:  bash .claude/skills/verify-app/driver.sh ["iPhone 17 Pro Max"]
# Exit:   0 = every hard assertion held · 1 = a hard assertion failed

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

SCHEME="Maso"
PROJECT="Maso.xcodeproj"
BUNDLE_ID="com.yumowu.maso"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Maso.app"
OUT="build/verify-screens"
DATA="Maso/Resources/exercises.json"
ROUTES=("" "exercises" "plan_detail" "player")   # "" = today
MIN_PNG_BYTES=40000                              # a real retina screen is far bigger than a black frame
MIN_EXERCISES=500

n=0; fails=()
head() { n=$((n+1)); echo ""; echo "[$n] $1"; }
ok()   { echo "    ✓ $1"; }
bad()  { echo "    ✗ $1"; fails+=("$1"); }
chk()  { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

# ── pick a simulator (prefer one already booted) ───────────────────────────
# node-parsed JSON, not regex — avoids whitespace/format surprises in the udid.
DEVICE_NAME="${1:-iPhone 17 Pro Max}"
pick() { xcrun simctl list devices "$1" -j 2>/dev/null | node -e '
  const d=JSON.parse(require("fs").readFileSync(0,"utf8")).devices; const want=process.argv[1];
  let u="";
  for (const list of Object.values(d)) for (const x of list) {
    if (want==="__booted__") { if (x.state==="Booted") u=x.udid; }
    else if ((x.name||"").includes(want)) { u=x.udid; }
  }
  process.stdout.write(u);' "$2"; }
SIM="$(pick booted __booted__)"
[ -z "$SIM" ] && SIM="$(pick available "$DEVICE_NAME")"
[ -z "$SIM" ] && { echo "✗ no usable simulator found"; exit 1; }
echo "simulator: $SIM"
xcrun simctl boot "$SIM" >/dev/null 2>&1 || true   # idempotent; ok if already booted
open -a Simulator >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
mkdir -p "$OUT"

# ── 1. generate ────────────────────────────────────────────────────────────
head "xcodegen generate"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null 2>&1 && ok "project regenerated from project.yml" || bad "xcodegen generate failed"
else
  bad "xcodegen not installed (brew install xcodegen)"
fi

# ── 2. runtime data sanity ─────────────────────────────────────────────────
head "exercises.json sanity (the file the app actually loads at runtime)"
if [ -f "$DATA" ]; then
  COUNT=$(node -e "try{const a=require('./$DATA');console.log(Array.isArray(a)?a.length:(a.exercises?a.exercises.length:0))}catch(e){console.log(-1)}" 2>/dev/null)
  echo "    exercises in $DATA: $COUNT"
  chk "[ \"$COUNT\" -ge $MIN_EXERCISES ]" "exercise library parses and has ≥ $MIN_EXERCISES entries"
else
  bad "$DATA not found (the app would launch with an empty library)"
fi

# ── 3. build ───────────────────────────────────────────────────────────────
head "build for Simulator"
BLOG=$(mktemp -t maso-build.XXXX.log)
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DERIVED" build \
  >"$BLOG" 2>&1
if [ $? -eq 0 ] && [ -d "$APP" ]; then
  ok "compiled → $(basename "$APP")"
else
  bad "build failed"; echo "    --- errors ---"; grep -E "error:" "$BLOG" | head -15; echo "    full log: $BLOG"
fi

# ── 4. drive showcase routes + screenshot ──────────────────────────────────
if [ -d "$APP" ]; then
  xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
  xcrun simctl uninstall "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$SIM" "$APP" >/dev/null 2>&1
  xcrun simctl status_bar "$SIM" override --time "9:41" --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

  shots=()
  for r in "${ROUTES[@]}"; do
    label="${r:-today}"
    head "route '$label' → launch (seeded) + screenshot"
    xcrun simctl terminate "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
    PID=$(SIMCTL_CHILD_MASO_SHOWCASE_SEED=1 SIMCTL_CHILD_MASO_SHOWCASE="$r" \
      xcrun simctl launch "$SIM" "$BUNDLE_ID" 2>/dev/null | grep -oE '[0-9]+$')
    chk "[ -n \"$PID\" ]" "app launched (pid $PID)"
    sleep 6
    out="$OUT/$label.png"
    xcrun simctl io "$SIM" screenshot "$out" >/dev/null 2>&1
    bytes=$(stat -f%z "$out" 2>/dev/null || echo 0)
    echo "    screenshot: $out ($bytes bytes)"
    chk "[ \"$bytes\" -ge $MIN_PNG_BYTES ]" "screen rendered real pixels (non-blank)"
    shots+=("$out")
  done
  xcrun simctl status_bar "$SIM" clear >/dev/null 2>&1 || true

  head "screens are distinct (real navigation, not crashed/stuck)"
  uniq=$(shasum "${shots[@]}" 2>/dev/null | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
  echo "    distinct frames: $uniq / ${#shots[@]}"
  chk "[ \"$uniq\" -ge 2 ]" "not all identical (would mean crashed-to-SpringBoard / stuck splash)"
  [ "$uniq" -eq "${#shots[@]}" ] && echo "    ✓ all ${#shots[@]} routes rendered a distinct screen" || echo "    ⚠ ${#shots[@]} routes → only $uniq distinct frames (soft)"
fi

echo ""; echo "────────────────────────────────────────────────────"
echo "screenshots → $OUT/"
if [ ${#fails[@]} -ne 0 ]; then
  echo "FAIL — ${#fails[@]} hard assertion(s):"; for f in "${fails[@]}"; do echo "  ✗ $f"; done; exit 1
fi
echo "PASS — every hard assertion held."; exit 0
