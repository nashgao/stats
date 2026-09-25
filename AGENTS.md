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

- **Never `pkill`.** Kill only exact PIDs (`pgrep -x Stats` then `kill <pid>`),
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

The helper is an **on-demand launchd service**: `SMC/Helper/main.swift`
exits when its connections drain, so "registered but not loaded" is the
NORMAL healthy idle state — launchd activates it on the next XPC
connection. Never run `sfltool resetbtm`, `launchctl bootout`, or any
registration as an experiment. Registration happens ONLY via the
explicit Install button (Settings → Fan control setup, or the fan
controls' install prompt).

Failure modes this machinery has survived:

- The 2026-09-15 dead-helper incident: the launch-time "zombie drop"
  misclassified the healthy idle-unloaded state as broken, dropped the
  record, and headless `register()` then failed ("Operation not
  permitted" — daemon registration needs the user's consent). Forensics
  on the recurrence the same night caught the exact signature in the
  unified log: `launchd ... removing job: caller = smd` immediately
  followed by `registerLaunchItem: found existing item` — an unregister
  whose re-register no-op'd against the still-existing BTM item, leaving
  [enabled] with no launchd job ("Could not find service") and an
  Install-prompt loop. The fix: `healIfNeeded()` is activation-only (one
  XPC round trip, no register/drop); `install()` probes with a real XPC
  round trip first and only unregisters a record confirmed broken (no
  launchd job or spawn failure, checked TWICE ~3s apart — never exit
  codes, which are negative for plain signal kills); `checkForUpdate()`
  is a version note only. Every unregister/register decision logs with
  NSLog under `[SMC]` so the next incident is greppable.
- Exit-code misclassification: launchd records SIGKILL/SIGTERM as
  negative "last exit code" (-9/-15); using `code != 0` as broken
  evidence turned normal lifecycle kills into wrongful drops.
- Probe flapping: the on-demand spawn can exceed the 2s probe deadline
  under load, so reachability failures are debounced (2 consecutive
  misses ≈10s before the UI flips to broken; one success restores
  instantly).
- TWO BUILDS, ONE BUNDLE ID: a /tmp Debug Stats running while the
  installed Stats runs makes backgroundtaskmanagementd re-attribute the
  shared BTM items back and forth (`_bundleURLForAuditToken: updating
  item ... URL to: <other path>` in the unified log). Never run a QA
  /tmp instance concurrently with the installed app when the helper
  record matters; release.sh quits the installed app first for exactly
  this reason.
- Stale BTM records (enabled disposition, no launchd entry) make
  `register()` a silent no-op — the confirmed-broken check in
  `install()` covers exactly that case.
- XPC reply blocks run on the **connection queue** — anything that
  touches AppKit from a helper reply must hop to the main thread first
  (see `SMCHelper.updateReachability`; the fan-settings crash was this).
- The helper embeds its Info.plist via `-sectcreate` **without build-setting
  expansion** — `$(DEVELOPMENT_TEAM)` stays literal in the binary; that is
  expected and accepted by the contract check.

⚠️ CURRENT STATE: the record is MISSING (destroyed by the incident) and
MUST be restored by the USER clicking Install in Settings → Fan control
setup (registration requires their consent). Do NOT attempt
registration, `sfltool resetbtm`, `bootout`, or `launchctl bootstrap`
from agent code — the hardened smoke test is expected to fail with the
"helper unreachable" message until the user installs.

## Machine quirks

- Hottest sensor TCMb idles **88–94°C** here; attention/critical
  thresholds (93°C/100°C) are intentional — do not "fix" them.
- The Xcode GUI won't open via `-a` in this environment; use
  `xcodebuild` and edit files directly.
- **The screen locks when idle** — real-window screencaptures fail at the
  lock screen. Use the self-capture harness
  (`STATS_POPUP_CAPTURE=1 STATS_POPUP_CAPTURE_PATH=/tmp/x.png`) which
  renders the panel content off-screen.
- **NSLog from this app does not surface in `log show` on macOS 27** —
  capture stdout via direct exec (`./Stats >log 2>&1`) when diagnosing.
- Sixteen `yes > /dev/null` jobs for ~25s trips the temperature/CPU
  attention states for alert-path testing; kill by exact PIDs.

## Live-metric readouts (verification playbook)

"Stuck number" readouts have three distinct causes — identify which
before attempting a fix:

1. **Wrong source semantics** — the feed is accurate but is not the
   quantity the user expects. (Menu watts showed adapter delivery
   PDTR = system + battery charge: pinned ~84 W whenever charging.)
2. **Slow feed** — the registry snapshot refreshes far slower than the
   UI cadence. AppleSmartBattery properties, *including the
   PowerTelemetryData accumulators*, publish every 25–60 s on this
   machine; a per-second readout drawn from them is frozen that whole
   time. (The "stuck at 52 W" report.)
3. **Dead connection** — the launch-opened SMC connection goes stale
   over sleep/wake, freezing every SMC-fed readout. (Fixed: NSLock +
   `reconnect()` on wake.)

Rules:

- **Format/cadence QA is not liveness QA** — a pinned number passes
  format checks. Every live readout needs a step-response assertion:
  known load step (4–6 × `yes`, exact PIDs), require the composed
  value to move ≥ 4 W within ~10 s. Smoke phase 5 does this for menu
  watts; extend the pattern to any new live metric.
- Characterize a candidate source before trusting it:
  `swift Scripts/audit-power-keys.swift scan` enumerates every SMC key
  twice (8 s apart) and diffs — keys that changed are live feeds;
  `watch KEY…` tracks keys at 1 s cadence through a load step.
- This machine's verified power sources (2026-09-25): menu watts =
  PPBR (drain) on battery · PDTR (total system draw, 1 s step
  response) on AC not charging · si10 (SoC power, live even while
  charging) on AC charging. PPBR reads ~0.6–4 on AC — garbage,
  battery-only. PDTR pins at the adapter delivery limit while
  charging (charge current absorbs every load change — unfixable from
  PDTR arithmetic).

## QA knobs (all env-var, launch-only)

| Knob | Effect |
|---|---|
| `STATS_POPUP_MODULE=<name>` | force-enable + open that module's popup; `All` opens the unified panel |
| `STATS_APPEARANCE=light\|dark` | force appearance |
| `STATS_POPUP_CAPTURE=1` + `STATS_POPUP_CAPTURE_PATH` | render panel content to a PNG (lock-screen safe) |
| `STATS_POPUP_CAPTURE_CHROME=1` | with `STATS_POPUP_CAPTURE=1`, also render the footer bar as `<path>-footer.png` — it lives in the panel chrome, outside the content render |
| `STATS_POPUP_SCROLL_TO=bottom\|<points>` | scroll position for captures |
| `STATS_POPUP_EXPAND=<module>` | expand a section at open |
| `STATS_POPUP_PERF=1` | per-tick timing signposts (`[UnifiedPerf]`) |
| `STATS_QA_FAN_CYCLE=1` | drive a real fan auto→manual→RPM target→read-back→auto via XPC (smoke test) |
| `STATS_QA_ALERT=1` | force a synthetic RAM attention edge and log the composed notification (`[QA] alert:`) |
| `STATS_QA_PANEL_TOGGLE=1` | drive the status-item toggle path open→closed→open and log the state transitions (`[QA] panel toggle:`) |
| `STATS_QA_DISMISS=1` | synthesize click events inside/outside the icon frame to exercise the outside-click dismissal guards (`[QA] dismiss:`) |
| `STATS_QA_LAYOUT=1` | log the panel content height once per second (`[QA] layout tick:`) for the layout-stability smoke assertion |
| `STATS_QA_EXPAND=<module\|All>` | expand a section (or all of CPU/GPU/RAM/Sensors/Battery in sequence) and sample panel heights across +1.2s (`[QA] expand:`/`expand-seq:`) — two-phase expand detector |
| `STATS_QA_MENU_WATTS=1` | force the unified menu bar watts readout on and log the composed title every tick (`[QA] menu watts:`, raw keys in `[QA] watts raw:`) — smoke test asserts format + 1s cadence + step-response liveness under a `yes` load. Battery level/time live in the panel's Battery row, not the menu bar |
| `STATS_QA_SENSOR_TICK=1` | log reader/repeater lifecycle and every Sensors_List sample delivered to the panel (`[QA] reader …`, `[QA] repeater(…)`, `[QA] sensor sample:`) — used to catch reader idling (frozen sensors card) |
