#!/bin/bash
#
# smoke-test.sh — post-install verification of /Applications/Stats.app.
# Launches the installed app through the QA harness, proves the unified
# panel opens, exercises the real fan-command round trip (the path that
# crashed on XPC reply thread affinity), verifies a clean quit, checks
# for new crash reports, and runs the helper contract check.
#
# Usage: Scripts/smoke-test.sh [/Applications/Stats.app]
# Hard rules: never pkill — kills exact PIDs only.

set -u
APP="${1:-/Applications/Stats.app}"
BIN="$APP/Contents/MacOS/Stats"
DIAG=~/Library/Logs/DiagnosticReports
FAILED=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }

[ -d "$APP" ] || { echo "FAIL: $APP not found"; exit 1; }

echo "== smoke-test: $APP =="

# --- 0. ensure a clean slate: quit any running Stats (exact PIDs only) ---
for pid in $(pgrep -f "Stats.app/Contents/MacOS/Stats"); do kill "$pid" 2>/dev/null; done
sleep 2
REMAIN=$(pgrep -f "Stats.app/Contents/MacOS/Stats" | wc -l | tr -d ' ')
if [ "$REMAIN" != "0" ]; then
  for pid in $(pgrep -f "Stats.app/Contents/MacOS/Stats"); do kill "$pid" 2>/dev/null; done
  sleep 2
fi
REMAIN=$(pgrep -f "Stats.app/Contents/MacOS/Stats" | wc -l | tr -d ' ')
[ "$REMAIN" = "0" ] && pass "no Stats processes running" || fail "$REMAIN Stats processes still running"

# --- 1. crash-report snapshot ---
BEFORE=$(ls -t "$DIAG" 2>/dev/null | grep '^Stats' | head -1)

# --- 2. launch with QA knobs; capture stderr of the direct run ---
QA_LOG=/tmp/stats-smoke.log
CAPTURE=/tmp/stats-smoke-capture.png
rm -f "$QA_LOG" "$CAPTURE"
cd "$(dirname "$BIN")"
STATS_POPUP_MODULE=All \
STATS_POPUP_CAPTURE=1 \
STATS_POPUP_CAPTURE_PATH="$CAPTURE" \
STATS_QA_FAN_CYCLE=1 \
./Stats >"$QA_LOG" 2>&1 &
QA_PID=$!

# --- 3. panel opened + process alive ---
ALIVE=0
for i in $(seq 1 25); do
  sleep 1
  if [ -s "$CAPTURE" ]; then ALIVE=1; break; fi
  if ! ps -p "$QA_PID" >/dev/null 2>&1; then break; fi
done
[ "$ALIVE" = "1" ] && pass "unified panel opened (self capture written at +${i}s)" || fail "panel capture missing"
ps -p "$QA_PID" >/dev/null 2>&1 && pass "process alive at +${i}s" || fail "process died within ${i}s of launch"

# --- 4. helper reachable through the real XPC path ---
sleep 8
grep -q "helper active=1" "$QA_LOG" && pass "SMC helper reachable (active=1)" || fail "helper not reachable: $(grep 'helper' "$QA_LOG" | tail -1)"
grep -q "\[QA\] fan cycle: manual" "$QA_LOG" && pass "fan command round trip (manual) completed" || fail "fan manual command never fired"
grep -q "\[QA\] fan cycle: automatic" "$QA_LOG" && pass "fan command round trip (automatic) completed" || fail "fan automatic command never fired"

# --- 5. stay alive through the fan cycle window ---
sleep 10
ps -p "$QA_PID" >/dev/null 2>&1 && pass "process alive after fan cycle window (~25s)" || fail "process died during fan cycle"

# --- 6. no new crash reports ---
AFTER=$(ls -t "$DIAG" 2>/dev/null | grep '^Stats' | head -1)
if [ "$AFTER" = "$BEFORE" ]; then
  pass "no new crash reports"
else
  fail "new crash report: $AFTER"
fi

# --- 7. clean quit via the AppleEvent path ---
osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || osascript -e "tell application \"Stats\" to quit" >/dev/null 2>&1
QUIT_OK=0
for i in $(seq 1 8); do
  sleep 1
  ps -p "$QA_PID" >/dev/null 2>&1 || { QUIT_OK=1; break; }
done
# fallback: graceful SIGTERM (still not pkill; exact PID)
if [ "$QUIT_OK" != "1" ]; then
  kill "$QA_PID" 2>/dev/null
  sleep 2
  ps -p "$QA_PID" >/dev/null 2>&1 || QUIT_OK=1
fi
[ "$QUIT_OK" = "1" ] && pass "clean quit" || fail "process ignored quit"

# --- 8. helper contract ---
"$SCRIPT_DIR/check-helper-contract.sh" "$APP" && pass "helper contract" || fail "helper contract"

echo "== smoke-test: $([ "$FAILED" = "0" ] && echo ALL PASS || echo FAILURES) =="
exit "$FAILED"
