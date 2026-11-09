#!/bin/bash
# Write the heart-ripple patch onto a Mac checkout of Maso.
# Refuses unless PlanPlayerScreen.swift is still the captured snapshot.
# Does not checkout, reset, pull, commit, or modify any other file.

set -euo pipefail

SNAPSHOT_SHA="9d869071a4177ef26a250adccb84ca6b6b3d8baa8b2c3349c7ea218d1605dd86"
PATCHED_SHA="ac99fdfe7aaeaef28c5d90b3c227403a529e12dfdd0cfc76441b5fcaed3f85f0"
ROOTVIEW_SHA="f633da0eefe20e87a47f524fa2bce7972813e09745ca4558824edc7146719d41"
UITEST_SHA="5bab8c0d5ab8f684c381a725fd11af401e8a97e045c2210bcf5eca93ea1de471"

CHECK_ONLY=0
ROOT=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      echo "Usage: $0 [--check] /path/to/Maso-iOS"
      exit 0
      ;;
    *)
      if [[ -n "$ROOT" ]]; then
        echo "STOP: unexpected extra argument: $arg"
        exit 2
      fi
      ROOT="$arg"
      ;;
  esac
done
ROOT="${ROOT:-.}"

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

warn_unchanged() {
  local path="$1"
  local expected="$2"
  if [[ ! -f "$path" ]]; then
    echo "WARN: $path is absent. This patch does not create it."
    return
  fi
  local actual
  actual="$(hash_file "$path")"
  if [[ "$actual" == "$expected" ]]; then
    echo "OK unchanged $path"
  else
    echo "WARN: $path SHA is $actual, snapshot was $expected."
    echo "WARN: leaving that file untouched."
  fi
}

DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$DIR/heart-ripple-motion.patch"
FILE="$ROOT/Maso/Views/Screens/PlanPlayerScreen.swift"

if [[ ! -f "$PATCH" ]]; then
  echo "STOP: missing $PATCH"
  exit 2
fi
if [[ ! -f "$FILE" ]]; then
  echo "STOP: missing $FILE"
  echo "Pass the Maso-iOS repo root. Do not point this at a GitHub checkout of main 02106ee and expect it to gain the local player."
  exit 2
fi

warn_unchanged "$ROOT/Maso/Views/RootView.swift" "$ROOTVIEW_SHA"
warn_unchanged "$ROOT/MasoUITests/ExerciseLibraryBrowserUITests.swift" "$UITEST_SHA"

ACTUAL="$(hash_file "$FILE")"
if [[ "$ACTUAL" == "$PATCHED_SHA" ]]; then
  echo "Already patched ($PATCHED_SHA). No write."
  exit 0
fi
if [[ "$ACTUAL" != "$SNAPSHOT_SHA" ]]; then
  echo "STOP: $FILE"
  echo "SHA is $ACTUAL"
  echo "Snapshot SHA is $SNAPSHOT_SHA"
  echo "Not patching. The working tree moved after the snapshot; merge the hunk by hand."
  echo "Do not replace this file with a copy from git, and do not checkout main."
  exit 2
fi

if ! patch -p1 --forward --batch --fuzz=0 --no-backup-if-mismatch --dry-run -d "$ROOT" < "$PATCH"; then
  echo "STOP: dry-run failed. No write."
  exit 2
fi
if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "CHECK OK. Dry-run matched snapshot $SNAPSHOT_SHA. No write."
  exit 0
fi

BACKUP="$(mktemp)"
cp "$FILE" "$BACKUP"
cleanup_fail() {
  cp "$BACKUP" "$FILE"
  rm -f "$BACKUP" "$FILE.rej" "$FILE.orig"
  echo "STOP: apply failed. Restored the snapshot bytes."
  exit 3
}

if ! patch -p1 --forward --batch --fuzz=0 --no-backup-if-mismatch \
    --reject-file="$(mktemp)" -d "$ROOT" < "$PATCH"; then
  cleanup_fail
fi

AFTER="$(hash_file "$FILE")"
if [[ "$AFTER" != "$PATCHED_SHA" ]]; then
  echo "Result SHA $AFTER != $PATCHED_SHA"
  cleanup_fail
fi
rm -f "$BACKUP" "$FILE.rej" "$FILE.orig"
echo "Patched $FILE"
echo "New SHA $PATCHED_SHA"
echo "No other file was written."
