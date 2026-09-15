#!/bin/bash
#
# release.sh — the ONLY supported install path.
#
#   1. Release-build into a throwaway DerivedData (/tmp/stats-build)
#   2. Verify the fan-helper contract
#   3. Remove any DerivedData Debug/Release Stats.app copies (duplicate
#      Spotlight apps) and quit the running instance (exact PIDs only)
#   4. ditto the fresh build to /Applications/Stats.app
#   5. Verify exactly one Spotlight-visible Stats.app
#   6. Relaunch and verify a single PID
#   7. Run smoke-test.sh
#
# Usage: Scripts/release.sh
# Any failure stops the script with a clear message.

set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
BUILD=/tmp/stats-build
APP=/Applications/Stats.app
step() { echo "== $1 =="; }

step "Release build (derivedDataPath $BUILD)"
rm -rf "$BUILD"
xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Release \
  -derivedDataPath "$BUILD" -allowProvisioningUpdates build 2>&1 | tail -3
BUILT_APP="$BUILD/Build/Products/Release/Stats.app"
[ -d "$BUILT_APP" ] || { echo "FAIL: build product missing: $BUILT_APP"; exit 1; }

step "Fan helper contract"
Scripts/check-helper-contract.sh "$BUILT_APP"

step "Remove DerivedData app copies (duplicate Spotlight apps)"
DERIVED_DATA=~/Library/Developer/Xcode/DerivedData
REMOVED=0
for bundle in $(find "$DERIVED_DATA" -path "*Products/*/Stats.app" -maxdepth 6 2>/dev/null); do
  echo "removing $bundle"
  rm -rf "$bundle"
  REMOVED=1
done
[ "$REMOVED" = "1" ] || echo "no DerivedData copies found"

step "Quit running Stats (exact PIDs only)"
# -x matches the process NAME regardless of how it was launched — a
# shell-launched instance shows as "./Stats" in its cmdline and the
# full-path pattern misses it, leaving a ghost menu bar icon.
for pid in $(pgrep -x Stats); do kill "$pid" 2>/dev/null || true; done
sleep 2
for pid in $(pgrep -x Stats); do kill "$pid" 2>/dev/null || true; done
sleep 1
REMAINING=$(pgrep -x Stats | wc -l | tr -d ' ')
[ "$REMAINING" = "0" ] || { echo "FAIL: $REMAINING Stats processes still running: $(pgrep -x Stats | tr '\n' ' ')"; exit 1; }

step "Install to $APP"
rm -rf "$APP"
ditto "$BUILT_APP" "$APP"

step "Verify single Spotlight entry"
# mdfind lags a few seconds behind a fresh ditto — retry before failing.
SPOTLIGHT=""
COUNT=0
for attempt in 1 2 3 4 5 6; do
  SPOTLIGHT=$(mdfind "kMDItemCFBundleIdentifier == 'eu.exelban.Stats'" 2>/dev/null)
  COUNT=$(echo "$SPOTLIGHT" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$COUNT" = "1" ]; then break; fi
  sleep 3
done
echo "$SPOTLIGHT"
[ "$COUNT" = "1" ] || { echo "FAIL: expected 1 Spotlight entry, got $COUNT"; exit 1; }
echo "$SPOTLIGHT" | grep -q "^/Applications/Stats.app$" || { echo "FAIL: Spotlight entry is not /Applications/Stats.app"; exit 1; }

step "Relaunch"
open -n "$APP"
sleep 8
PIDS=$(pgrep -x Stats)
COUNT=$(echo "$PIDS" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$COUNT" = "1" ] || { echo "FAIL: expected 1 running Stats, got: $PIDS"; exit 1; }
echo "single instance: $PIDS"

step "Smoke test"
Scripts/smoke-test.sh "$APP"

step "release.sh complete"
