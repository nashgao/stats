#!/bin/bash
#
# perf-check.sh — guardrail on the running app's CPU cost.
#
# Samples the running Stats with `top` and asserts the per-process CPU
# share stays under budget. Budget: 8% of one core — baseline measured
# ~2.7% at idle on the target machine (M5 Max, Release build, helper
# connected); the headroom covers this dev machine's heavy background
# load (docker, indexing, agent processes). This is a guardrail against
# regressions (poll loops, per-tick layout storms), not a benchmark.
#
# Note: `sample`'s "running: N% of wallclock" footer was removed in
# recent macOS (sample Report Version 7), so this uses top's
# per-process %CPU instead.
#
# Usage: Scripts/perf-check.sh [pid]   (default: the running /Applications Stats)
# Exit non-zero on breach.

set -u
PID="${1:-$(pgrep -f '/Applications/Stats.app/Contents/MacOS/Stats' | head -1)}"
BUDGET=8
FAILED=0

if [ -z "$PID" ]; then
  echo "FAIL: no running Stats found (launch /Applications/Stats.app first)"
  exit 1
fi
if ! ps -p "$PID" >/dev/null 2>&1; then
  echo "FAIL: pid $PID not running"
  exit 1
fi

# top's first-sample %CPU is a lifetime average; later samples are
# deltas. Take the last of three 1s samples.
CPU=$(top -pid "$PID" -l 3 -s 1 | grep -E "^\s*$PID\s" | tail -1 | awk '{print $3}')
if [ -z "$CPU" ]; then
  echo "FAIL: could not parse %CPU from top output"
  exit 1
fi

echo "Stats pid $PID: ${CPU}% CPU of one core (budget ${BUDGET}%)"
if python3 -c "exit(0 if float('$CPU') < $BUDGET else 1)"; then
  echo "PASS: within budget"
else
  echo "FAIL: over budget"
  FAILED=1
fi

# Optional refresh-budget check when the QA perf signposts are present
# (STATS_POPUP_PERF=1 builds; the Release build skips this).
LOG=/tmp/stats-perf.log
if [ -f "$LOG" ]; then
  RELAYOUT_AVG=$(grep -oE "relayout avg [0-9.]+ms" "$LOG" | tail -1 | grep -oE "[0-9.]+")
  if [ -n "$RELAYOUT_AVG" ]; then
    echo "QA perf signposts: relayout avg ${RELAYOUT_AVG}ms (budget 1.0ms)"
    python3 -c "exit(0 if float('$RELAYOUT_AVG') < 1.0 else 1)" || { echo "FAIL: relayout over budget"; FAILED=1; }
  fi
fi

exit "$FAILED"
