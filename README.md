# Stats Custom

<a href="https://github.com/nashgao/stats"><p align="center"><img src="https://github.com/nashgao/stats/raw/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120"></p></a>

macOS system monitor in your menu bar

## About this fork

Stats Custom is an independently maintained, modified version of [Stats](https://github.com/exelban/stats) by Serhiy Mytrovtsiy. It is not affiliated with or endorsed by the original project.

The original project and this fork are distributed under the [MIT License](LICENSE). The original copyright and permission notice are retained.

## Installation
### Stats Custom
Stats Custom does not yet publish a signed DMG. Build it locally with the verified Xcode 26.6 toolchain:

```bash
git clone https://github.com/nashgao/stats.git
cd stats
open Stats.xcodeproj
```

Select the **Stats** scheme in Xcode and run the app. Future packaged builds will be published on this fork's [Releases page](https://github.com/nashgao/stats/releases).

### Upstream binary
If you want the original upstream application instead of Stats Custom, download it from the [upstream Stats releases](https://github.com/exelban/stats/releases/latest). That binary is maintained by the original project and does not contain this fork's changes.

### Homebrew
Homebrew currently installs the upstream Stats application, not Stats Custom:
```bash
brew install stats
```

### Uninstall
Run the uninstall script bundled with the app (requires administrator privileges to remove the SMC helper):
```bash
sh /Applications/Stats.app/Contents/Resources/Scripts/uninstall.sh
```
The script quits Stats and removes:

   - the SMC helper (`/Library/LaunchDaemons/eu.exelban.Stats.SMC.Helper.plist` and `/Library/PrivilegedHelperTools/eu.exelban.Stats.SMC.Helper`)
   - `Stats.app`
   - application data and preferences (`~/Library/Application Support/Stats`, widget containers, and `eu.exelban.Stats` defaults)

If the app has already been moved to the Trash, the script can be run directly from the repository:
```bash
curl -fsSL https://raw.githubusercontent.com/nashgao/stats/master/Kit/scripts/uninstall.sh | sh
```

### Legacy version
Legacy upstream builds for older systems can be found [here](https://mac-stats.com/downloads).

## Requirements
Stats is supported on macOS 12 (Monterey) and newer.
Beta versions of macOS are not supported - only stable releases.

## Development QA

The custom build exposes environment-only launch controls for deterministic local UI verification. They do not alter normal launches:

```bash
# Dashboard in light appearance
open -n --env STATS_SETTINGS_DESTINATION=Dashboard --env STATS_APPEARANCE=light /path/to/Stats.app

# Application settings with the sidebar collapsed
open -n --env STATS_SETTINGS_DESTINATION=Settings --env STATS_SIDEBAR_COLLAPSED=1 /path/to/Stats.app

# A constrained module popup
open -n --env STATS_POPUP_MODULE=CPU /path/to/Stats.app

# The open menu-bar preset selector
open -n --env STATS_SETTINGS_DESTINATION=Settings --env STATS_OPEN_PRESET_MENU=1 /path/to/Stats.app
```

Do not run a second Stats instance alongside the installed app: both use the same bundle identifier and fan-helper registration. Use `Scripts/release.sh` for installation, then run QA against `/Applications/Stats.app` with the normal instance stopped.

### All-sensors memory regression

Closing the unified panel does not instantiate an unopened **All sensors**
popover. Hidden popovers cache the latest readings without rendering. While
shown, temperature ranking and filter changes reposition or hide existing rows;
each sensor's text fields are created only once.

Verify the never-opened, visible, and opened-then-closed paths with changing
temperature rankings. Hidden samples must leave row views untouched; reopening
must immediately show the latest values. Filtering to no matches and back must
preserve the row views, and adding a sensor must create only its own row.

For memory verification, compare native `heap` snapshots after 100 and 1,000
rank-changing samples in an isolated view-only replay. `NSKeyValueDependency`
and `NSKeyValueDependencyContext` counts must plateau, not grow with each sample.
This catches the macOS 27 appearance-dependency leak that repeated detached
text-field rebuilding triggered. Do not use a second Stats app instance for
this replay or alter the shared preference domain.

### Source-backed Penpot capture

`penpot-capture.json` declares original English light/dark UI states. Capture-only
adapters select existing views and supply synthetic metrics, an uninstalled helper,
disabled login items and an unauthorized remote account. Hardware-detail captures
replace the serial number with `CAPTURE-REFERENCE`. No preference controls, helper
actions, reader mounting, remote login or alert delivery are exercised.

The five module previews receive the same synthetic samples through their
original rendering callbacks, without mounting readers or entering module alert
handlers. CPU preview samples cover the host's core rows; RAM preview samples
scale to its physical-memory total. Disk preview metadata matches the synthetic
root volume. Unavailable SMART and connectivity samples remain explicit no-data
fields rather than fabricated measurements.

Build the capture executable without installing or launching it directly:

```bash
xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Debug \
  -derivedDataPath build/dd -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO build

# The output must be a new directory. Requires the installed penpot-sync skill.
uv run --no-project --no-config ~/.agents/skills/penpot-sync/sync.py extract \
  --source "$PWD" --spec penpot-capture.json --output penpot-capture-reference
```

Only the native producer may launch this capture build: it stages a separate
bundle identity, supplies a synthetic HOME, denies real-home access and networking,
and freezes the original executable, resources, frameworks and declared sources.
This is not an install path; installation remains `Scripts/release.sh`.

All adapters below require `STATS_CAPTURE_FIXTURE=1` and leave normal launches
unchanged:

| Launch control | Original view/state selected |
|---|---|
| `STATS_CAPTURE_SURFACE` | `panel`, `settings`, `setup`, `support`, `update`, `sensors`, `menu`, `context-menu` |
| `STATS_SETTINGS_DESTINATION` | `Dashboard`, `Settings` or the module's configured name |
| `STATS_CAPTURE_TAB` | Available `module`, `widgets`, `popup`, `notifications` or `preview` tab; unavailable requests fail |
| `STATS_CAPTURE_SETUP_PAGE` | Setup page `0`–`4`, without clicking setup actions |
| `STATS_CAPTURE_SEVERITY` | `normal`, `attention` or `critical` synthetic temperature state |
| `STATS_CAPTURE_SCROLL_TO=bottom` | Bottom of the active settings content |
| `STATS_CAPTURE_DASHBOARD_HARDWARE=1` | Original hardware-details disclosure |
| `STATS_CAPTURE_UPDATE_STATE` | `available` or `current`; the update window is dormant in normal custom builds |
| `STATS_CAPTURE_MENU_ELEMENTS` | `off` or comma-separated `watts`, `battery`, `temperature`, `time` |
| `STATS_CAPTURE_MENU_LAYOUT` | Original `horizontal` or `stacked` menu readout |

Panel expansion and scrolling use the existing `STATS_POPUP_EXPAND` and
`STATS_POPUP_SCROLL_TO` controls. The all-sensors fixture supplies enough
temperatures to expose its original affordance. Legacy module popups remain
quarantined; this inventory does not imply coverage of every translation.

Capture fixtures ignore foreign desktop clicks so the All sensors source popover
remains open without changing normal dismissal behavior. Context-menu captures
select the observed native `NSGlassEffectView` root while menu tracking is active.
Menu-readout captures bind the original status button's public Accessibility
identifier, `StatsCaptureStatusItem`, to its actual source-process-owned physical
frame. They require an unlocked, on-console session and pre-existing Accessibility
access: macOS can expose a virtual status window with zero height and no usable
WindowServer capture ID. The menu controls remain explicitly non-editable original
native paint; no replacement control, fake layer tree or relaxed fidelity gate is used.

The approved native-appearance reference can contain outlined glyphs, bounded
native-control paint and measured materials; these are not editable text or live
controls. An extracted capture is not a verified sync. Producer blockers and
source/target mismatches must remain explicit; never omit failed states, replay
old target approvals or relax fidelity checks.

`.penpot-sync/goal.json` is the canonical inventory, capture-evidence and blocker
record. Check it before planning target changes; a valid subset bundle does not
reduce the agreed scope or authorize an unverified import.

### Verification rig

The automated checks that gate shipping. Run order: tests, release,
smoke, perf.

```bash
# 1. Unit tests with the normal installed instance stopped.
#    Release needs testability enabled for the suite's @testable imports.
xcodebuild test -project Stats.xcodeproj -scheme Stats -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/stats-test \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES

# 2. Release: build, helper contract, de-dup Spotlight apps, install to
#    /Applications, relaunch, smoke test. The ONLY supported install path.
Scripts/release.sh

# 3. Post-install smoke (also run standalone any time)
Scripts/smoke-test.sh

# 4. CPU guardrail on the running app (8% budget; baseline ~2.7% idle)
Scripts/perf-check.sh

# 5. Fan-helper contract (run by release.sh; standalone after plist edits)
Scripts/check-helper-contract.sh /Applications/Stats.app
```

Smoke-test exercises the harness end to end: unified panel opens,
a genuine helper XPC round trip (version probe) plus real command
replies for a fan auto→manual→RPM target→auto cycle
(`STATS_QA_FAN_CYCLE=1`), a read-back anchored to the commanded target
(auto fan drift cannot satisfy it), no crash report, clean quit, and
the helper contract holds. QA builds live under
`/tmp` (`-derivedDataPath /tmp/stats-build`); the installed app is
always Release.

For Settings navigation changes, also exercise the installed UI with **Show icon
in dock** enabled: open Settings from the panel footer, the menu-bar item's
right-click menu, and the window sidebar. The footer and context-menu actions
must select the **Settings** page (not Dashboard) and dismiss the floating panel.
Repeat with the main window closed and minimized; the Settings window must
appear or restore without changing the Dock preference.

### Menu readouts and fan controls

Settings → **Menu bar readout** selects watts, battery percentage, temperature,
and time remaining. Horizontal fits up to three selected readouts; Stacked fits
two centered rows in the same clickable status item. A single available value
uses the normal full-size text, and no available values restores the status
glyph. Temperature uses the same hottest curated sensor as the Sensors section.

Expanded Sensors controls size each fan independently: selecting Manual reserves
space for its slider and min/current/max RPM row immediately. Switching back
reclaims that space; live sensor updates retain the current layout.

The release smoke includes `STATS_QA_MENU_READOUT=1`, which cycles horizontal,
stacked, single-value and glyph presentations in light and dark appearances
without writing preferences. `STATS_QA_MENU_CAPTURE_DIR=/tmp/stats-menu-captures`
saves `phase-0.png` through `phase-9.png` from the real status button. The smoke
output reports its unique capture directory for visual inspection; title-string
checks alone cannot detect clipped text.

## Fan control & code signing

Fan control talks to the SMC through a privileged helper (`eu.exelban.Stats.SMC.Helper`) registered via `SMAppService`. macOS only registers the helper when the app and the helper are signed by the same development team, so ad-hoc builds cannot enable fan control — the "Install fan helper" flow will fail with an unsigned-build message.

One-time setup for a local fork build:

1. Open `Stats.xcodeproj` in Xcode and sign in with your Apple ID (Xcode ▸ Settings ▸ Accounts; a free account is enough).
2. Select your team in the Signing & Capabilities pane of the **Stats** target (the project's `SMPrivilegedExecutables`/`SMAuthorizedClients` requirements resolve against that team automatically).
3. Build and run once from Xcode. Approve the "Stats" daemon when macOS asks (System Settings ▸ Login Items).
4. Fan control is live from then on, including for subsequently installed local builds.

### Fan helper contract — do not break

- The daemon label is `eu.exelban.Stats.SMC.Helper`. Renaming it orphans every
  installed helper (stale BTM records resurrect as zombies); never change it.
- The app and the helper must be signed by the **same team**. The requirement
  macros (`SMPrivilegedExecutables` in the app's Info.plist, `SMAuthorizedClients`
  in the helper's) may carry the concrete team or `$(DEVELOPMENT_TEAM)` — anything
  else breaks registration or the connection.
- **Rebuilds do not re-register the helper**; only renaming, team, or plist
  changes do. After any of those, verify before shipping:

  ```bash
  Scripts/check-helper-contract.sh /path/to/Stats.app
  ```

  The script checks same-team signing, both requirement plists, the daemon
  label, and `codesign --verify`. Run it against the Release bundle from the
  repo root; it exits non-zero on any violation.

## Features
Stats is an application that allows you to monitor your macOS system.

 - CPU utilization
 - GPU utilization
 - Memory usage
 - Disk utilization
 - Network usage
 - Battery level
 - Fan's control (not maintained)
 - Sensors information (Temperature/Voltage/Power)
 - Bluetooth devices
 - Multiple time zone clock

## FAQs

### How do you change the order of the menu bar icons?
macOS decides the order of the menu bar items not `Stats` - it may change after the first reboot after installing Stats.

To change the order of any menu bar icon - macOS Mojave (version 10.14) and up.

1. Hold down ⌘ (command key).
2. Drag the icon to the desired position on the menu bar.
3. Release ⌘ (command key)

### Stats icons do not appear in the menu bar
macOS 26 introduced a new privacy control under System Settings → Menu Bar. Apps must be explicitly allowed there to display menu bar items. If Stats is running with at least one module active and one widget enabled, but none of its icons show up in the menu bar, this is almost certainly the cause. More details you can find [here](https://github.com/exelban/stats/issues/3120).

**Solution:** open **System Settings → Menu Bar** and toggle **Stats** ON.

### Desktop widgets not showing the data
Due to a problem with high data load in the system process (`chronod`) responsible for communication between the app and widgets, communication is disabled by default on the Stats side. To enable it, the `macOS widgets` option must be enabled in the Stats settings. More details you can find [here](https://github.com/exelban/stats/issues/2733).

**Solution:** open **Stats Settings** and toggle **macOS widgets** ON.

### How to reduce energy impact or CPU usage of Stats?
Stats tries to be efficient as it's possible. But reading some data periodically is not a cheap task. Each module has its own "price". So, if you want to reduce energy impact from the Stats you need to disable some Stats modules. The most inefficient modules are Sensors and Bluetooth. Disabling these modules could reduce CPU usage and power efficiency by up to 50% in some cases.

### Fan control
Fan control is in legacy mode. It does not receive any updates or fixes. It's not dropped from the app just because in the old Macs it works pretty acceptable. I'm open to accepting fixed or improvements (via PR) for this feature in case someone would like to help with that. But have no option and time to provide support for this feature.

### Sensors show incorrect CPU/GPU core count
CPU/GPU sensors are simply thermal zones (sensors) on the CPU/GPU. They have no relation to the number of cores or specific cores.
For example, a CPU is typically divided into two clusters: efficiency and performance. Each cluster contains multiple temperature sensors, and Stats simply displays these sensors. However, "CPU Efficient Core 1" does not represent the temperature of a single efficient core—it only indicates one of the temperature sensors within the efficiency core cluster.
Additionally, with each new SoC, Apple changes the sensor keys. As a result, it takes time to determine which SMC values correspond to the appropriate sensors. If anyone knows how to accurately match the sensors for Apple Silicon, please contact me.

### App crash – what to do?
Check this fork's [open and closed issues](https://github.com/nashgao/stats/issues) first. If the problem is not already tracked, open a [new Stats Custom issue](https://github.com/nashgao/stats/issues/new) with the macOS version, app version, and reproduction steps.

### External API
Stats Custom does not collect any telemetry or analytics. Its current optional external request is:

- https://api.mac-stats.com – Retrieving the public IP address in the Network module

Automatic update checks and installation are disabled in custom builds. The source is configured to use `https://api.github.com/repos/nashgao/stats/releases/latest` if a future signed distribution enables the updater, but the current custom build does not contact that release endpoint. An external request is still required to obtain the public IP address when that Network feature is enabled.

If you have concerns about these requests, you have a few options:

- propose a PR that allows these features to work without an external server
- block either endpoint using a network filtering app. In that case, do not expect the corresponding release check or public-IP feature to work.

### How to contribute to the project?
Open an issue in [nashgao/stats](https://github.com/nashgao/stats/issues) before starting a substantial change so scope and verification can be aligned. Pull requests should preserve the MIT attribution, the custom-update safety boundary, and the single-source Native Telemetry design contract in [DESIGN.md](DESIGN.md).

## Supported languages
- English
- Polski
- Українська
- Русский
- 中文 (简体) (thanks to [chenguokai](https://github.com/chenguokai), [Tai-Zhou](https://github.com/Tai-Zhou), and [Jerry](https://github.com/Jerry23011))
- Türkçe (thanks to [yusufozgul](https://github.com/yusufozgul) and [setanarut](https://github.com/setanarut))
- 한국어 (thanks to [escapeanaemia](https://github.com/escapeanaemia) and [iamhslee](https://github.com/iamhslee))
- German (thanks to [natterstefan](https://github.com/natterstefan) and [aneitel](https://github.com/aneitel))
- 中文 (繁體) (thanks to [iamch15542](https://github.com/iamch15542) and [jrthsr700tmax](https://github.com/jrthsr700tmax))
- Spanish (thanks to [jcconca](https://github.com/jcconca))
- Vietnamese (thanks to [HXD.VN](https://github.com/xuandung38))
- French (thanks to [RomainLt](https://github.com/RomainLt))
- Italian (thanks to [gmcinalli](https://github.com/gmcinalli))
- Portuguese (Brazil) (thanks to [marcelochaves95](https://github.com/marcelochaves95) and [pedroserigatto](https://github.com/pedroserigatto))
- Norwegian Bokmål (thanks to [rubjo](https://github.com/rubjo))
- 日本語 (thanks to [treastrain](https://github.com/treastrain))
- Portuguese (Portugal) (thanks to [AdamModus](https://github.com/AdamModus))
- Czech (thanks to [mpl75](https://github.com/mpl75))
- Magyar (thanks to [moriczr](https://github.com/moriczr))
- Bulgarian (thanks to [zbrox](https://github.com/zbrox))
- Romanian (thanks to [razluta](https://github.com/razluta))
- Dutch (thanks to [ngohungphuc](https://github.com/ngohungphuc))
- Hrvatski (thanks to [milotype](https://github.com/milotype))
- Danish (thanks to [casperes1996](https://github.com/casperes1996) and [aleksanderbl29](https://github.com/aleksanderbl29))
- Catalan (thanks to [davidalonso](https://github.com/davidalonso))
- Indonesian (thanks to [yooody](https://github.com/yooody))
- Hebrew (thanks to [BadSugar](https://github.com/BadSugar))
- Slovenian (thanks to [zigapovhe](https://github.com/zigapovhe))
- Greek (thanks to [sudoxcess](https://github.com/sudoxcess) and [vaionicle](https://github.com/vaionicle))
- Persian (thanks to [ShawnAlisson](https://github.com/ShawnAlisson))
- Slovenský (thanks to [martinbernat](https://github.com/martinbernat))
- Thai (thanks to [apiphoomchu](https://github.com/apiphoomchu))
- Estonian (thanks to [postylem](https://github.com/postylem))
- Hindi (thanks to [patiljignesh](https://github.com/patiljignesh))
- Finnish (thanks to [eightscrow](https://github.com/eightscrow))
- Bengali (thanks to [adnan29979](https://github.com/adnan29979))
- Tamil (thanks to [sabapathy7](https://github.com/sabapathy7))

You can help by adding a new language or improving the existing translation.

## License
[MIT License](LICENSE)
