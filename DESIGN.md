# Stats Custom Native Telemetry Design System

## 1. Atmosphere & Identity

Stats Custom is a quiet native telemetry instrument: calm at a glance, dense only when a person asks for detail. The signature is the **live health ribbon** — a compact sequence of current system states and trends that always answers what needs attention before exposing raw inventory. The interface uses macOS materials, SF Symbols, system typography, and the user's accent color; it must feel built into macOS rather than themed on top of it.

The primary journey is: glance at health -> identify a changing subsystem -> inspect its trend -> act or configure. Static hardware identity is supporting information, never the main Dashboard story.

### Personas and task constraints

- **Everyday owner**: wants a trustworthy “is my Mac healthy?” answer without learning kernel terminology.
- **Power user**: wants dense, accurate values, configurable menu-bar output, and fast drill-down without losing context.
- **Keyboard or VoiceOver user**: must reach every navigation item and action with visible focus and a meaningful label.
- **Low-vision or situationally constrained user**: needs Increase Contrast, Reduce Transparency, larger text, and non-color-only status encoding.
- **Localized user**: German, Russian, CJK, and pseudo-localized labels must reflow without clipping or hiding primary values.

### Principles

1. Live state before static inventory.
2. Summary before breakdown; breakdown before raw detail.
3. Native semantic behavior before custom decoration.
4. Color reinforces meaning but never carries it alone.
5. One shared anatomy per component family.
6. User-selected density changes quantity, not legibility or accessibility.

## 2. Color

All roles resolve through semantic `NSColor`; views do not introduce raw RGB or hex values.

| Role | Token | AppKit mapping | Usage |
|---|---|---|---|
| Window material | `surfaceWindow` | `NSVisualEffectView.Material.contentBackground` | Main content plane |
| Sidebar material | `surfaceSidebar` | native sidebar visual-effect material | Navigation plane |
| Surface secondary | `surfaceSecondary` | `.controlBackgroundColor` | Metric groups and settings sections |
| Surface elevated | `surfaceElevated` | `.windowBackgroundColor` with native vibrancy | Popups and elevated summaries |
| Surface hover | `surfaceHover` | `.quaternaryLabelColor` at semantic hover opacity | Pointer hover |
| Text primary | `textPrimary` | `.labelColor` | Titles, values, body |
| Text secondary | `textSecondary` | `.secondaryLabelColor` | Explanations and metadata |
| Text tertiary | `textTertiary` | `.tertiaryLabelColor` | Noncritical captions |
| Separator | `separatorSubtle` | `.separatorColor` | Section rhythm only |
| Accent | `accentPrimary` | `.controlAccentColor` | Selection, focus, direct interaction |
| Healthy | `statusHealthy` | `.systemGreen` | Healthy state plus checkmark/label |
| Attention | `statusAttention` | `.systemOrange` | Degraded state plus warning symbol/label |
| Critical | `statusCritical` | `.systemRed` | Critical state plus error symbol/label |
| Informational | `statusInfo` | `.systemBlue` | Neutral live information |
| Series primary | `seriesPrimary` | `.systemBlue` | Dominant chart series |
| Series secondary | `seriesSecondary` | `.systemIndigo` | Secondary chart series |
| Series tertiary | `seriesTertiary` | `.systemOrange` | Third comparison series |
| Series neutral | `seriesNeutral` | `.systemGray` | Idle, capacity, or baseline |

Rules:

- The user's accent color is the only navigation/action accent.
- Status roles always pair color with text, symbol, shape, or line style.
- Charts use consistent series roles across Dashboard, popups, and previews.
- Increase Contrast strengthens separators and text; Reduce Transparency falls back to opaque semantic surfaces.
- Selected sidebar rows use the system selection material and preserve contrast in custom accent colors.

## 3. Typography

Use the macOS system families only. SF Pro Text/Display comes from `NSFont.systemFont`; live numbers use `NSFont.monospacedDigitSystemFont` so values do not shift while updating.

| Role | Size | Weight | Usage |
|---|---:|---|---|
| Window title | 17 pt | semibold | Current navigation destination |
| Health headline | 24 pt | semibold | Overall state or primary metric |
| Metric value | 20 pt | semibold, tabular | Current live metric |
| Section title | 15 pt | semibold | Named content group |
| Body | 13 pt | regular | Settings labels and readable content |
| Body emphasis | 13 pt | medium | Selected or important text |
| Secondary | 12 pt | regular | Descriptions, chart axes, metadata |
| Caption | 11 pt | medium | Compact labels; never critical data |

Rules:

- Critical information is never below 12 pt.
- Numeric columns use monospaced digits and align on units/decimals where possible.
- Labels wrap or expand intrinsically; fixed-width text frames are legacy debt.
- Long localized labels retain the primary metric and move descriptions below when space is constrained.
- A future text-size preference may scale the table, but the default follows macOS control metrics.

## 4. Spacing & Layout

All intentional spacing derives from a 4-point base.

| Token | Value | Usage |
|---|---:|---|
| `space1` | 4 pt | Icon/label micro gap |
| `space2` | 8 pt | Compact row and chart inset |
| `space3` | 12 pt | Default row gap |
| `space4` | 16 pt | Card/section padding |
| `space5` | 20 pt | Comfortable group padding |
| `space6` | 24 pt | Major group separation |
| `space8` | 32 pt | Page-level separation |

### Window states

- **Compact**: 760-839 pt wide. Sidebar 168 pt; main content is one column; labels wrap; only the main content scrolls.
- **Default**: 840-1099 pt wide. Sidebar 184 pt; Dashboard supports two metric columns.
- **Expanded**: 1100 pt and wider. Sidebar 200 pt; Dashboard supports three metric columns and persistent secondary detail.
- Minimum height is 520 pt. Header, sidebar, and window toolbar stay fixed; main content owns vertical scrolling.
- Sidebar can collapse when the window becomes compact, using the standard macOS sidebar command.

### Popup states

- Default content width: 320 pt.
- Compact popups target one screen-height viewport; secondary sections collapse before the popup becomes taller than available screen space.
- Header remains visible; body owns scrolling when needed.
- Primary metric and trend stay above the fold.

## 5. Components

### `TelemetryMetricCard`

- **Structure**: icon + label + live value + status text; optional sparkline and change caption.
- **Variants**: standard, compact, critical, unavailable.
- **States**: loading skeleton, live, stale, unavailable, attention, critical.
- **Accessibility**: one concise summary plus separately reachable detail; status is not color-only.
- **Layout**: intrinsic grid; value never truncates before the label.

### `HealthRibbon`

- **Structure**: overall state followed by CPU, memory, power/thermal, disk, network, and battery summaries where available.
- **Variants**: compact labels, default cards, expanded trend view.
- **States**: healthy, attention, critical, partial-data, paused.
- **Interaction**: selecting a subsystem opens its module without losing Dashboard context.

### `TrendChart`

- **Structure**: title/unit, plot, direct series labels, time range, accessible summary.
- **States**: loading, live, paused, stale gap, empty, error.
- **Accessibility**: VoiceOver summary includes current, minimum, maximum, direction, and period; series differ by label and line/fill treatment as well as color.
- **Motion**: new samples update without decorative entrance motion; Reduce Motion disables interpolation.

### `SidebarRow`

- **Structure**: SF Symbol, label, optional status/count.
- **Variants**: overview, module, application destination.
- **States**: default, hover, selected, focused, disabled, attention.
- **Accessibility**: native button/list semantics, arrow-key traversal, visible focus, meaningful role and label.
- **Layout**: intrinsic label width; no fixed 100-point title frame.

### `ApplicationActionGroup`

- **Structure**: labelled Settings and Help destinations; Pause is a clearly labelled state action; Quit remains in the App menu and is not an equal-weight sidebar icon.
- **States**: default, hover, focused, pressed, paused.

### `SettingsSection` and `SettingsRow`

- **Structure**: optional title/description, grouped rows, trailing control, optional help.
- **States**: default, hover where actionable, focused, disabled with explanation, loading, error.
- **Accessibility**: label and control form one logical pair; disabled reasons remain perceivable.
- **Layout**: descriptions move below labels at compact widths; controls retain intrinsic size.

### `ModuleHeader`

- **Structure**: module identity, live availability/status, preview action, enable switch.
- **States**: enabled, disabled, unavailable, loading, focused.
- **Interaction**: enable/disable confirmation appears in place; preview is labelled.

### `PopupShell`

- **Structure**: header -> primary metrics -> recent trend -> breakdown -> top contributors -> secondary details.
- **Variants**: standard, compact, scrollable.
- **States**: loading, live, stale, empty, error, locked.
- **Accessibility**: header actions are labelled native controls with visible focus; Escape closes; Command-comma opens the corresponding settings pane.

### `MenuBarMetric`

- **Structure**: optional symbol/label, tabular value, unit, optional trend glyph.
- **Presets**: Essential, Performance, Power & Thermals, Network, Custom.
- **States**: live, paused, stale, unavailable, attention.
- **Layout**: shared baseline, spacing, truncation, and density grammar across modules.

## 6. Motion & Interaction

| Type | Duration | Usage |
|---|---:|---|
| Immediate | 0 ms | Live numeric sample replacement |
| Micro | 120 ms | Hover, press, focus, status tint |
| Standard | 180 ms | Pane/section transition and disclosure |
| Emphasis | 240 ms | Dashboard drill-down or popup resize |

Rules:

- Motion explains selection, hierarchy, or state change; there is no decorative ambient motion.
- Use `NSAnimationContext` with opacity/transform-friendly transitions where AppKit supports them.
- Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and remove nonessential interpolation.
- Keyboard and pointer interactions produce the same state and feedback.
- Focus never disappears merely to make a screenshot cleaner.

## 7. Depth & Surface

Strategy: **native material plus tonal shift**.

- Sidebar uses the native sidebar material above content.
- Main content uses content-background material.
- Metric groups and settings sections use one subtle tonal step; separators appear only between structurally related rows.
- Popups use the native elevated/window material with one outer outline supplied by macOS.
- Avoid custom shadow stacks, decorative gradients, heavy borders, and glass effects that compete with system materials.
- Device imagery is supporting identity and never the primary source of depth.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Full Keyboard Access reaches every navigation destination, control, disclosure, and popup action.
- Every interactive element has a visible focus state; `focusRingType = .none` requires an equivalent documented focus treatment.
- VoiceOver exposes meaningful labels, values, roles, states, and chart summaries.
- Increase Contrast, Reduce Transparency, Reduce Motion, light, and dark appearances remain usable.
- Status and chart meaning is never color-only.
- Controls meet the native minimum hit region and avoid unlabeled icon-only destructive actions.
- Dashboard, Settings, representative module panes, and popups are tested with long English, German/Russian-like expansion, and CJK strings.
- Empty, loading, stale, unavailable, paused, error, and permission-denied states are designed—not left blank.

### Verification matrix

| Surface | Required evidence |
|---|---|
| Dashboard | Compact/default/expanded, light/dark, live/paused/stale, keyboard and VoiceOver |
| Settings shell | Sidebar expanded/collapsed, long labels, 200% text/zoom equivalent, keyboard traversal |
| Module settings | CPU plus one low-density module and one complex module across all subareas |
| Popups | CPU, Network, Battery, Sensors in light/dark and constrained screen height |
| Menu bar | Every preset, stale/unavailable state, mixed numeric widths |

### Accepted debt

| Item | Location | Why accepted | Owner / Exit |
|---|---|---|---|
| Legacy fixed frames remain outside migrated shared shells | `Modules/*/popup.swift`, widget drawing code | Incremental migration avoids destabilizing readers and specialized visualizations | Task 008 removes or documents remaining constraints |
| Distribution signing does not yet authenticate the fork to the privileged SMC helper | project signing + helper requirement | Local ad-hoc UI QA cannot satisfy the upstream Team ID requirement | Task 009 defines fork-owned signing/helper migration before distribution |
