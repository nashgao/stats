#!/bin/bash
#
# check-helper-contract.sh — verify the fan-helper signing contract of a
# built Stats.app bundle. Run manually after building (NOT wired into any
# build phase):
#
#     Scripts/check-helper-contract.sh \
#         ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/Stats.app
#
# Checks (exit 1 with a clear message on any violation):
#   1. App binary and helper binary carry the SAME, non-empty TeamIdentifier.
#   2. App Info.plist SMPrivilegedExecutables authorizes the helper by label
#      and anchored to that same team (no unexpanded $(DEVELOPMENT_TEAM)).
#   3. Helper binary's embedded Info.plist (__TEXT,__info_plist)
#      SMAuthorizedClients is anchored to the same team (no unexpanded
#      $(DEVELOPMENT_TEAM) macro).
#   4. LaunchDaemons plist Label == eu.exelban.Stats.SMC.Helper.
#   5. codesign --verify passes on the app bundle and the helper binary.
#
# Invariants this protects (see README "Fan helper contract"):
#   - The daemon label eu.exelban.Stats.SMC.Helper must never change.
#   - App and helper must be signed by the SAME team.
#   - Rebuilds do NOT re-register the helper; only label/team/plist changes
#     do - so this script only needs to run when those change.

set -u
APP_BUNDLE="${1:-}"
HELPER_LABEL="eu.exelban.Stats.SMC.Helper"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -n "$APP_BUNDLE" ] || fail "usage: $0 /path/to/Stats.app"
[ -d "$APP_BUNDLE" ] || fail "bundle not found: $APP_BUNDLE"
APP_BIN="$APP_BUNDLE/Contents/MacOS/Stats"
HELPER_BIN="$APP_BUNDLE/Contents/Library/LaunchServices/$HELPER_LABEL"
DAEMON_PLIST="$APP_BUNDLE/Contents/Library/LaunchDaemons/$HELPER_LABEL.plist"
[ -f "$APP_BIN" ] || fail "app binary missing: $APP_BIN"
[ -f "$HELPER_BIN" ] || fail "helper binary missing: $HELPER_BIN"
[ -f "$DAEMON_PLIST" ] || fail "daemon plist missing: $DAEMON_PLIST"

# 1. same team on both binaries
TEAM_APP="$(codesign -dv "$APP_BIN" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
TEAM_HELPER="$(codesign -dv "$HELPER_BIN" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
[ -n "$TEAM_APP" ] || fail "app binary has no TeamIdentifier (ad-hoc signed?)"
[ -n "$TEAM_HELPER" ] || fail "helper binary has no TeamIdentifier (ad-hoc signed?)"
[ "$TEAM_APP" = "$TEAM_HELPER" ] || fail "team mismatch: app=$TEAM_APP helper=$TEAM_HELPER"
echo "OK: both binaries signed by team $TEAM_APP"

# 2. SMPrivilegedExecutables (app) authorizes the helper, team-anchored.
# The requirement may carry the concrete team or the $(DEVELOPMENT_TEAM)
# macro (the helper embeds its plist via -sectcreate, without build-setting
# expansion); anything else is a violation.
APP_PLIST="$APP_BUNDLE/Contents/Info.plist"
SPE="$(/usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables:$HELPER_LABEL" "$APP_PLIST" 2>/dev/null)" \
    || fail "app Info.plist missing SMPrivilegedExecutables[$HELPER_LABEL]"
echo "$SPE" | grep -q "$HELPER_LABEL" || fail "app SMPrivilegedExecutables does not reference $HELPER_LABEL"
if echo "$SPE" | grep -q "$TEAM_APP"; then
    echo "OK: SMPrivilegedExecutables authorizes $HELPER_LABEL (team $TEAM_APP)"
elif echo "$SPE" | grep -qF '$(DEVELOPMENT_TEAM)'; then
    echo "OK: SMPrivilegedExecutables references \$(DEVELOPMENT_TEAM) macro (resolves to $TEAM_APP in build settings)"
else
    fail "app SMPrivilegedExecutables not anchored to team $TEAM_APP or \$(DEVELOPMENT_TEAM): $SPE"
fi

# 3. helper embedded Info.plist: SMAuthorizedClients team-anchored
EMBEDDED="$(mktemp -t helper-info)"
trap 'rm -f "$EMBEDDED"' EXIT
python3 - "$HELPER_BIN" "$EMBEDDED" <<'PY' || fail "could not extract embedded Info.plist from helper binary"
import binascii, subprocess, sys
out = subprocess.check_output(["otool", "-s", "__TEXT", "__info_plist", sys.argv[1]], text=True)
data = b""
for line in out.splitlines()[2:]:
    for word in line.split()[1:5]:
        if 2 <= len(word) <= 8 and len(word) % 2 == 0 and all(c in "0123456789abcdef" for c in word):
            data += binascii.unhexlify(word)[::-1]  # otool prints little-endian words
open(sys.argv[2], "wb").write(data)
PY
plutil -lint "$EMBEDDED" >/dev/null 2>&1 || fail "helper embedded Info.plist is not valid XML"
SAC="$(/usr/libexec/PlistBuddy -c "Print :SMAuthorizedClients:0" "$EMBEDDED" 2>/dev/null)" \
    || fail "helper embedded Info.plist missing SMAuthorizedClients"
if echo "$SAC" | grep -q "$TEAM_APP"; then
    echo "OK: helper SMAuthorizedClients anchored to team $TEAM_APP"
elif echo "$SAC" | grep -qF '$(DEVELOPMENT_TEAM)'; then
    echo "OK: helper SMAuthorizedClients references \$(DEVELOPMENT_TEAM) macro (helper plist is embedded via -sectcreate; resolves in build settings)"
else
    fail "helper SMAuthorizedClients not anchored to team $TEAM_APP or \$(DEVELOPMENT_TEAM): $SAC"
fi

# 4. daemon plist label
LABEL="$(/usr/libexec/PlistBuddy -c "Print :Label" "$DAEMON_PLIST" 2>/dev/null)" \
    || fail "daemon plist missing Label"
[ "$LABEL" = "$HELPER_LABEL" ] || fail "daemon Label is '$LABEL', expected $HELPER_LABEL"
echo "OK: daemon Label is $HELPER_LABEL"

# 5. codesign verify
codesign --verify "$APP_BUNDLE" 2>/dev/null || { codesign --verify --verbose=4 "$APP_BUNDLE" 2>&1; fail "codesign verify failed for app bundle"; }
codesign --verify "$HELPER_BIN" 2>/dev/null || { codesign --verify --verbose=4 "$HELPER_BIN" 2>&1; fail "codesign verify failed for helper"; }
echo "OK: codesign verify passed for app and helper"

echo "PASS: fan helper contract intact for $APP_BUNDLE"
