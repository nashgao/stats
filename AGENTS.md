# Agent conventions — Stats fork

Hard-won rules from the fan-helper and unified-panel sagas. Follow them;
they exist because every one was learned from a user-visible failure.

## Install & release

- **One install, ever: `/Applications/Stats.app`, Release, team `4LXUDSR683`.**
- **`Scripts/release.sh` is the ONLY supported install path.** It builds
  Release to `/tmp/stats-build`, checks the helper contract, removes
  DerivedData app copies, installs, verifies a single Spotlight entry,
  relaunches, and smoke-tests. Never `ditto` by hand, never ship Debug.
- After changing the helper label, team, or either plist, run
  `Scripts/check-helper-contract.sh <bundle>` before shipping.

## Process rules

- **Never `pkill`.** Kill only exact PIDs (`pgrep -f ...` then `kill <pid>`),
  and only the QA instance you launched. The user's instance is off limits
  unless the task explicitly says to swap it.
- **Never `defaults write` against the shared `eu.exelban.Stats` domain.**
  Read via `defaults read` is fine. Debug builds share this domain with the
  user's instance — QA harness paths that need a module force-enable it
  **in memory only**.
- Keep `brand-spec.md` and `stats-unified-redesign.html` untracked.
- Conventional English commits; green build before every commit; small
  scoped commits.

## Fan helper — DO NOT TOUCH

The helper registration is **healthy** (team 4LXUDSR683, daemon loaded,
fans working). Never run `sfltool resetbtm`, `launchctl bootout`, or
re-register it as an experiment. The failure modes it survived:

- Stale BTM records resurrect as **zombie** launchd entries (enabled but
  spawn-failed) — `install()` now drops zombies before registering, and
  `daemonIsLoaded()` requires `state = running`.
- XPC reply blocks run on the **connection queue** — anything that
  touches AppKit from a helper reply must hop to the main thread first
  (see `SMCHelper.updateReachability`; the fan-settings crash was this).
- The helper embeds its Info.plist via `-sectcreate` **without build-setting
  expansion** — `$(DEVELOPMENT_TEAM)` stays literal in the binary; that is
  expected and accepted by the contract check.

## Machine quirks

- Hottest sensor TCMb idles **88–94°C** here; attention/critical
  thresholds (93°C/100°C) are intentional — do not "fix" them.
- The Xcode GUI won't open via `-a` in this environment; use
  `xcodebuild` and edit files directly.
- **The screen locks when idle** — real-window screencaptures fail at the
  lock screen. Use the self-capture harness
  (`STATS_POPUP_CAPTURE=1 STATS_POPUP_CAPTURE_PATH=/tmp/x.png`) which
  renders the panel content off-screen.
- Sixteen `yes > /dev/null` jobs for ~25s trips the temperature/CPU
  attention states for alert-path testing; kill by exact PIDs.

## QA knobs (all env-var, launch-only)

| Knob | Effect |
|---|---|
| `STATS_POPUP_MODULE=<name>` | force-enable + open that module's popup; `All` opens the unified panel |
| `STATS_APPEARANCE=light\|dark` | force appearance |
| `STATS_POPUP_CAPTURE=1` + `STATS_POPUP_CAPTURE_PATH` | render panel content to a PNG (lock-screen safe) |
| `STATS_POPUP_SCROLL_TO=bottom\|<points>` | scroll position for captures |
| `STATS_POPUP_EXPAND=<module>` | expand a section at open |
| `STATS_POPUP_PERF=1` | per-tick timing signposts (`[UnifiedPerf]`) |
| `STATS_QA_FAN_CYCLE=1` | drive a real fan auto→manual→auto via XPC (smoke test) |
