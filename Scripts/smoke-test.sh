#!/bin/bash
#
# smoke-test.sh — post-install verification of /Applications/Stats.app.
# SERIAL PHASES: every QA driver runs in its OWN app launch, so the
# drivers can never collide (a toggle and an expand firing in the same
# millisecond was a harness-only artifact). Phases:
#   1. panel toggle open→closed→open + outside-click dismissal guards
#   2. expand every section (one-pass render)
#   3. real helper XPC round trip (fan mode/rpm) + attention alerts
#   4. layout stability + open-latency budget
# Ends with crash-report checks per phase and the helper contract check.
#
# Usage: Scripts/smoke-test.sh [/Applications/Stats.app]
# Hard rules: never pkill — kills exact PIDs only.

set -u
APP="${1:-/Applications/Stats.app}"
BIN="$APP/Contents/MacOS/Stats"
DIAG=~/Library/Logs/DiagnosticReports
FAILED=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QA_LOG=/tmp/stats-smoke.log
CAPTURE=/tmp/stats-smoke-capture.png
HELPER_GUIDANCE="helper unreachable — open Stats Settings → Fan control setup → Install"
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }

[ -d "$APP" ] || { echo "FAIL: $APP not found"; exit 1; }

echo "== smoke-test: $APP =="

# --- clean slate: quit any running Stats (exact PIDs only) ---
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
    if [ "$QUIET" -ge 2 ]; then break; fi
  fi
  sleep 1
done
REMAIN=$(pgrep -x Stats | wc -l | tr -d ' ')
[ "$REMAIN" = "0" ] && pass "no Stats processes running" || fail "$REMAIN Stats processes still running"

BEFORE=$(ls -t "$DIAG" 2>/dev/null | grep '^Stats' | head -1)
QA_PID=""

# launch_phase VAR=VALUE... — fresh app launch with only the given knobs;
# waits for the panel-open marker. Leaves QA_PID.
launch_phase() {
  for pid in $(pgrep -x Stats); do kill "$pid" 2>/dev/null; done
  sleep 1
  rm -f "$QA_LOG" "$CAPTURE"
  cd "$(dirname "$BIN")"
  env STATS_POPUP_MODULE=All "$@" ./Stats >"$QA_LOG" 2>&1 &
  QA_PID=$!
  local i
  for i in $(seq 1 25); do
    grep -q "show done visible=1" "$QA_LOG" 2>/dev/null && return 0
    [ -s "$CAPTURE" ] && return 0
    ps -p "$QA_PID" >/dev/null 2>&1 || return 1
    sleep 1
  done
  return 1
}

# wait_for_log PATTERN TIMEOUT — polls the phase log.
wait_for_log() {
  local pat="$1" timeout="${2:-30}" i
  for i in $(seq 1 "$timeout"); do
    grep -q "$pat" "$QA_LOG" 2>/dev/null && return 0
    ps -p "$QA_PID" >/dev/null 2>&1 || return 1
    sleep 1
  done
  return 1
}

# quit_phase NAME — AppleEvent quit (SIGTERM fallback, exact PID), then a
# per-phase crash-report check.
quit_phase() {
  local ok=0 i after
  osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || osascript -e "tell application \"Stats\" to quit" >/dev/null 2>&1
  for i in $(seq 1 8); do
    sleep 1
    ps -p "$QA_PID" >/dev/null 2>&1 || { ok=1; break; }
  done
  if [ "$ok" != "1" ]; then
    kill "$QA_PID" 2>/dev/null
    sleep 2
    ps -p "$QA_PID" >/dev/null 2>&1 || ok=1
  fi
  [ "$ok" = "1" ] && pass "$1 quit cleanly" || fail "$1 did not quit"
  after=$(ls -t "$DIAG" 2>/dev/null | grep '^Stats' | head -1)
  if [ "$after" = "$BEFORE" ]; then
    pass "no new crash reports ($1)"
  else
    fail "new crash report after $1: $after"
    BEFORE="$after"
  fi
}

# --- phase 1: toggle open→closed→open + dismissal guards ---
echo "-- phase 1: toggle + dismiss --"
if launch_phase STATS_QA_PANEL_TOGGLE=1 STATS_QA_DISMISS=1; then
  pass "panel opened"
else
  fail "panel did not open"
fi
wait_for_log "\[QA\] dismiss: outside event" 25 || true
grep -q "\[QA\] panel toggle: open effective=1 visible=1" "$QA_LOG" && pass "panel toggle: open state effective" || fail "panel toggle: open state not effective"
grep -q "\[QA\] panel toggle: closed effective=0 visible=0" "$QA_LOG" && pass "panel toggle: click closes panel" || fail "panel toggle: click did not close the panel"
grep -q "\[QA\] panel toggle: reopen effective=1 visible=1" "$QA_LOG" && pass "panel toggle: second click reopens" || fail "panel toggle: second click did not reopen"
grep -q "\[QA\] panel toggle: settled effective=1 visible=1" "$QA_LOG" && pass "panel stays open after opening (no flash)" || fail "panel vanished after opening — flash regression"
grep -q "\[QA\] dismiss: inside-button event -> visible=1" "$QA_LOG" && pass "dismiss guard: icon-area click does not close" || fail "dismiss guard: icon-area click closed the panel"
grep -q "\[QA\] dismiss: outside event -> visible=0" "$QA_LOG" && pass "dismiss: outside click closes panel" || fail "dismiss: outside click did not close the panel"
quit_phase "phase 1 (toggle+dismiss)"

# --- phase 2: expand every section in one pass ---
# An island appearance mid-window is a REAL content transition (attention
# threshold crossing), not a render defect: tolerated when the height
# delta matches the island size and a transition is logged.
echo "-- phase 2: expand all sections --"
if launch_phase STATS_QA_EXPAND=All; then
  pass "panel opened"
else
  fail "panel did not open"
fi
wait_for_log "\[QA\] expand-seq: Battery " 35 || true
ISLAND_APPEARANCES=$(grep -c "island=1 " "$QA_LOG")
for module in CPU GPU RAM Sensors Battery; do
  PAIR=$(grep "\[QA\] expand-seq: $module " "$QA_LOG" | tail -1 | grep -oE "panel [0-9]+->[0-9]+")
  FROM=${PAIR#panel }; FROM=${FROM%%->*}; TO=${PAIR##*->}
  if [ -n "$FROM" ] && [ "$FROM" = "$TO" ]; then
    pass "expand $module renders in one pass (panel ${FROM})"
  elif [ -n "$FROM" ] && [ "$ISLAND_APPEARANCES" -ge 1 ] \
       && python3 -c "exit(0 if 40 <= abs($TO - $FROM) <= 70 else 1)" 2>/dev/null; then
    pass "expand $module one-pass up to an island transition ($(python3 -c "print(abs($TO - $FROM))")pt)"
  else
    fail "expand $module two-phase ($PAIR)"
  fi
done
quit_phase "phase 2 (expand)"

# --- phase 3: real helper replies + attention alerts ---
echo "-- phase 3: helper XPC + alerts --"
if launch_phase STATS_QA_FAN_CYCLE=1 STATS_QA_ALERT=1; then
  pass "panel opened"
else
  fail "panel did not open"
fi
wait_for_log "\[QA\] fan cycle: automatic" 30 || true
grep -q "\[QA\] helper version reply: OK" "$QA_LOG" && pass "helper XPC round trip (version reply)" || fail "$HELPER_GUIDANCE"
grep -q "\[QA\] fan cycle: manual" "$QA_LOG" && pass "fan mode command sent (manual)" || fail "fan manual command never fired"
grep -q "\[QA\] fan cycle: mode reply" "$QA_LOG" && pass "fan mode reply (real XPC reply)" || fail "$HELPER_GUIDANCE"
grep -q "\[QA\] fan cycle: rpm target set" "$QA_LOG" && pass "fan rpm target sent through the slider path" || fail "fan rpm target never sent"
grep -q "\[QA\] fan cycle: helper accepted" "$QA_LOG" && pass "helper accepted the rpm target" || fail "$HELPER_GUIDANCE"
grep -q "\[QA\] fan cycle: read-back speed .* (meets target" "$QA_LOG" && pass "fan speed read-back meets target" || fail "fan read-back below target or missing — the command had no effect"
grep -q "\[QA\] fan cycle: automatic" "$QA_LOG" && pass "fan mode command sent (automatic)" || fail "fan automatic command never fired"
grep -q "\[QA\] alert:" "$QA_LOG" && pass "attention alert composed (QA log)" || fail "attention alert never composed"
grep -q "\[Attention\]" "$QA_LOG" && pass "attention evaluator active" || fail "attention evaluator silent"
quit_phase "phase 3 (helper+alerts)"

# --- phase 4: layout stability + open latency ---
echo "-- phase 4: layout + latency --"
if launch_phase STATS_QA_LAYOUT=1; then
  pass "panel opened"
else
  fail "panel did not open"
fi
sleep 12
LAYOUT_CHANGES=$(grep "\[QA\] layout tick:" "$QA_LOG" | grep -oE "content=[0-9.]+" | cut -d= -f2 | awk 'NR>1 { d = $1 - prev; if (d < 0) d = -d; if (d > 2) n++ } { prev = $1 } END { print n+0 }')
python3 -c "exit(0 if $LAYOUT_CHANGES <= 1 else 1)" 2>/dev/null \
  && pass "layout stable ($LAYOUT_CHANGES height transitions)" \
  || fail "layout oscillating ($LAYOUT_CHANGES large height changes)"
OPEN_TOTAL=$(grep "\[UnifiedPerf\] show latency" "$QA_LOG" | tail -1 | grep -oE "total=[0-9.]+" | cut -d= -f2)
if [ -z "$OPEN_TOTAL" ]; then
  fail "no show latency line captured"
else
  python3 -c "exit(0 if float('$OPEN_TOTAL') < 100.0 else 1)" \
    && pass "open latency ${OPEN_TOTAL}ms < 100ms" \
    || fail "open latency ${OPEN_TOTAL}ms over 100ms budget"
fi
ps -p "$QA_PID" >/dev/null 2>&1 && pass "process alive through phase 4" || fail "process died during phase 4"
quit_phase "phase 4 (layout+latency)"

# --- phase 5: island settles in one pass ---
# The first visible island frame must be pinned at the panel top and
# identical to the following samples — a correction after appearance is
# the "wrong spot, then jumps" defect.
echo "-- phase 5: island --"
if launch_phase STATS_QA_ISLAND=1; then
  pass "panel opened"
else
  fail "panel did not open"
fi
wait_for_log "\[QA\] island: sample visible=1" 22 || true
ISLAND_RESULT=$(grep "\[QA\] island: sample" "$QA_LOG" | python3 -c '
import sys, re
frames = []
for line in sys.stdin:
    m = re.search(r"visible=1 frame=\{\{[\d.]+, ([\d.]+)\}, \{([\d.]+),", line)
    if m:
        frames.append((float(m.group(1)), float(m.group(2))))
if not frames:
    print("never-visible")
elif frames[0][0] <= 0:
    print("unpinned")
elif any(f != frames[0] for f in frames[1:]):
    print("moved")
else:
    print("stable@%d" % frames[0][0])
')
case "$ISLAND_RESULT" in
  stable@*) pass "island settles in one pass (first visible frame pinned at y${ISLAND_RESULT#stable@})" ;;
  *) fail "island placement defect: $ISLAND_RESULT" ;;
esac
quit_phase "phase 5 (island)"

# --- helper contract ---
"$SCRIPT_DIR/check-helper-contract.sh" "$APP" && pass "helper contract" || fail "helper contract"

echo "== smoke-test: $([ "$FAILED" = "0" ] && echo ALL PASS || echo FAILURES) =="
exit "$FAILED"
