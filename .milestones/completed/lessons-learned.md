## Milestone Completion Report: milestone-stats-custom-v3013

**Completed:** 2026-08-30 05:18 AEST

**Tracked effort:** 3.40 active-goal hours

**Estimated effort:** Not recorded

**Efficiency and schedule variance:** Not calculable

### What Worked Well

- Preserved the verified v3.0.13 AppKit foundation, single-branch/worktree invariant, wake handling, and distinct watts-reader stale-sample protections.
- Routed live Dashboard telemetry through the existing CPU, RAM, Disk, Network, Battery, and Sensors readers instead of creating a parallel data model.
- Turned `DESIGN.md` into executable policy through `Constants.Design`, shared popup geometry, menu-bar presets, and deterministic QA launch controls.
- Centralized fork-owned product links while retaining explicit upstream credit and the MIT license.
- Required exact-current signed screenshots and independent product gates before archival.

### What Could Improve

- Implement executable design tokens before building surfaces; the first Dashboard pass still contained one-off fonts, geometry, and materials.
- Record initial hour/date estimates and phase timers when the milestone is created. Commit timestamps are useful provenance but not labor data.
- Generate final appearance/state captures only after the last source edit so evidence cannot become stale.

### Unexpected Challenges

- A collapsed `NSSplitViewItem` reclaimed its own pane, but the Dashboard's inner scroll surface retained the old 184-point offset and 716-point width. The outer view looked expanded while its content was clipped.
- Semantic AppKit materials resolved differently across light and dark appearance and needed real visual confirmation.
- The existing `eu.exelban.*` identity remains an operational dependency for the privileged SMC helper, so fork ownership had to be separated from bundle/helper migration.

### Process Improvements

- Test the entire rendered frame chain for adaptive UI: split content, Dashboard, inner scroll/document view, and final column count.
- Reserve 35-40% of comparable AppKit redesign work for hands-on visual QA, regression checks, and independent review.
- Front-load clean build, launch, signing/helper, narrow-layout, appearance, and screenshot-automation probes in the first 15-20% of future work.
- Use a 25-35% AppKit layout/render buffer; treat signing, helper, or distribution changes as a separate risk-retirement phase.

### Completion Evidence

- Final implementation: `ecd18905aec9913bf44bb33a0d1d540506cf7967`
- Tests: 16/16 passed from fresh DerivedData.
- SwiftLint strict: 0 violations across 119 files.
- Clean local app build: succeeded and passed deep signature verification.
- Runtime: clean signed app launched with live telemetry; light, dark, collapsed, German, Japanese, popup, and preset-menu states passed final gates.

### Accepted Residuals

- The local build is ad-hoc signed and cannot authenticate to the installed upstream-signed SMC helper.
- A signed/notarized distribution artifact and fork-owned helper migration remain future release work.
- Xcode 26.6 emits seven AppIntents metadata warnings for targets with no AppIntents dependency.

---
