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
# -x matches the process NAME, not the cmdline — shell-launched instances
# show as "./Stats" and a full-path pattern misses them. The app is a
# SMAppService login item: launchd respawns it after an unexpected death,
# so kill every appearance until none has existed for ~2s.
for pid in $(pgrep -x Stats); do kill "$pid" 2>/dev/null; done
sleep 2
QUIET=0
for i in $(seq 1 12); do
  PIDS=$(pgrep -x Stats)
  if [ -n "$PIDS" ]; then
    QUIET=0
    for pid in $PIDS; do kill -9 "$pid" 2>/dev/null; done
  else
    QUIET=$((QUIET + 1))
    if [ "$QUIET" -ge 2 ]; then ALIVE=0; break; fi
  fi
  sleep 1
done
REMAIN=$(pgrep -x Stats | wc -l | tr -d ' ')
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
STATS_QA_ALERT=1 \
STATS_QA_PANEL_TOGGLE=1 \
STATS_QA_DISMISS=1 \
STATS_QA_LAYOUT=1 \
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

# --- 4. real helper replies: version probe, mode reply, rpm acceptance ---
# The version probe and the command replies are genuine XPC round trips —
# without them the fan lines below would be fire-and-forget lies.
HELPER_GUIDANCE="helper unreachable — open Stats Settings → Fan control setup → Install"
sleep 8
grep -q "\[QA\] helper version reply: OK" "$QA_LOG" && pass "helper XPC round trip (version reply)" || fail "$HELPER_GUIDANCE"
grep -q "\[QA\] fan cycle: manual" "$QA_LOG" && pass "fan mode command sent (manual)" || fail "fan manual command never fired"
grep -q "\[QA\] fan cycle: mode reply" "$QA_LOG" && pass "fan mode reply (real XPC reply)" || fail "$HELPER_GUIDANCE"
grep -q "\[QA\] fan cycle: rpm target set" "$QA_LOG" && pass "fan rpm target sent through the slider path" || fail "fan rpm target never sent"
grep -q "\[QA\] fan cycle: helper accepted" "$QA_LOG" && pass "helper accepted the rpm target" || fail "$HELPER_GUIDANCE"
grep -q "\[QA\] alert:" "$QA_LOG" && pass "attention alert composed (QA log)" || fail "attention alert never composed"
grep -q "\[Attention\]" "$QA_LOG" && pass "attention evaluator active" || fail "attention evaluator silent"
grep -q "\[QA\] panel toggle: open effective=1 visible=1" "$QA_LOG" && pass "panel toggle: open state effective" || fail "panel toggle: open state not effective"
grep -q "\[QA\] panel toggle: closed effective=0 visible=0" "$QA_LOG" && pass "panel toggle: click closes panel" || fail "panel toggle: click did not close the panel"
grep -q "\[QA\] panel toggle: reopen effective=1 visible=1" "$QA_LOG" && pass "panel toggle: second click reopens" || fail "panel toggle: second click did not reopen"
grep -q "\[QA\] panel toggle: settled effective=1 visible=1" "$QA_LOG" && pass "panel stays open after opening (no flash)" || fail "panel vanished after opening — flash regression"

# --- 5. spin-up read-back vs the commanded target, then return to auto ---
# Floor is max(baseline, target/2): auto fan drift cannot satisfy it.
# (Read-back poll until +17s, auto at +20s.) ---
sleep 15
grep -q "\[QA\] fan cycle: read-back speed .* (meets target" "$QA_LOG" && pass "fan speed read-back meets target" || fail "fan read-back below target or missing — the command had no effect"
grep -q "\[QA\] dismiss: inside-button event -> visible=1" "$QA_LOG" && pass "dismiss guard: icon-area click does not close" || fail "dismiss guard: icon-area click closed the panel"
grep -q "\[QA\] dismiss: outside event -> visible=0" "$QA_LOG" && pass "dismiss: outside click closes panel" || fail "dismiss: outside click did not close the panel"
# layout stability: content height spread across the visible ticks must
# stay within epsilon — section jumping shows up as a large spread
HEIGHT_SPREAD=$(grep "\[QA\] layout tick:" "$QA_LOG" | grep -oE "content=[0-9.]+" | cut -d= -f2 | sort -n | awk 'NR==1{min=$1} {max=$1} END{if (NR>0) printf "%.1f", max-min; else print "none"}')
case "$HEIGHT_SPREAD" in
  none) fail "no layout ticks captured" ;;
  *) python3 -c "exit(0 if float('$HEIGHT_SPREAD') <= 4.0 else 1)" \
       && pass "layout stable (content height spread ${HEIGHT_SPREAD}pt <= 4pt)" \
       || fail "layout jumping (content height spread ${HEIGHT_SPREAD}pt)" ;;
esac
# open latency budget: show() synchronous cost must stay under 100ms
OPEN_TOTAL=$(grep "\[UnifiedPerf\] show latency" "$QA_LOG" | tail -1 | grep -oE "total=[0-9.]+" | cut -d= -f2)
if [ -z "$OPEN_TOTAL" ]; then
  fail "no show latency line captured"
else
  python3 -c "exit(0 if float('$OPEN_TOTAL') < 100.0 else 1)" \
    && pass "open latency ${OPEN_TOTAL}ms < 100ms" \
    || fail "open latency ${OPEN_TOTAL}ms over 100ms budget"
fi
grep -q "\[QA\] fan cycle: automatic" "$QA_LOG" && pass "fan mode command sent (automatic)" || fail "fan automatic command never fired"

# --- 6. stay alive through the whole QA window ---
sleep 5
ps -p "$QA_PID" >/dev/null 2>&1 && pass "process alive after QA window (~28s)" || fail "process died during QA window"

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
