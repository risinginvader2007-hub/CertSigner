# CertSigner design system

Everything visual comes from a few files. Screens are assembled from the components below and the
tokens in `Sources/Components/DesignTokens.swift`; no screen should hard-code a size, radius,
colour or animation.

## Tokens (`Components/DesignTokens.swift`)

### Spacing (4/8 pt grid)

| Token | pt | Use |
|---|---|---|
| `Space.hair` | 2 | Line gap inside one text block (title / subtitle) only |
| `Space.x1` / `xs` | 4 | Icon-to-badge, tight stacks |
| `Space.x2` / `s` | 8 | Icon-to-label, rows inside a card |
| `Space.x3` / `m` | 12 | Card content gaps |
| `Space.x4` / `l` | 16 | Card padding, screen side margins (`Theme.padding`) |
| `Space.x5` | 20 | Gap between top-level sections on a screen |
| `Space.x6` / `xl` | 24 | Empty / error state padding |
| `Space.x8` / `xxl` | 32 | Hero spacing |

Values of 1 to 3 pt (hairline offsets) and fixed layout offsets (`.padding(.top, 60)` on empty
states) are the only literals left.

### Corner radii (always `style: .continuous`)

| Token | pt | Use |
|---|---|---|
| `Radius.xs` | 8 | Small icon tiles, skeleton blocks |
| `Radius.sm` / `small` | 12 | Text fields, tonal strips, icon previews |
| `Radius.md` / `medium` | 16 | Rows that leave during a delete |
| `Radius.lg` / `large` | 22 | Every card and container (`Theme.corner`); rows live inside one clipped card |
| `Radius.xl` | 28 | Sheets before iOS 26 (iOS 26 sheets use the system shape) |
| `Radius.pill` / `Capsule()` | ∞ | Pills, badges, segmented controls, toasts |

Nested shapes: `Radius.inner(outer, padding:)` = outer − padding (minimum 4). Icon tiles:
`Radius.tile(side)` = 28 % of the side (app-icon squircle).

### Type scale (`TypeScale`, SF Rounded via `.roundedDesign()`, all Dynamic Type)

`largeTitle` (bold) · `title` (title2 bold) · `headline` · `body` · `callout` · `subheadline` ·
`caption` (medium) · `captionStrong` (semibold) · `sectionTitle` (caption semibold, uppercase,
0.6 tracking) · `number` (rounded title, bold, tabular digits).

### Semantic colours (`SemanticColor`, all dynamic light / dark)

`surface`, `elevatedSurface`, `background`, `textPrimary`, `textSecondary`, `success`, `warning`,
`danger`, `hairline`. The accent comes from `@Environment(\.themeAccent)` (and
`\.themeGradient`) so it follows the active theme. Storage categories have five fixed hues
(`StorageCategory.color`) that are identical in the ring, the cards and the detail screens.

### Borders & elevation

`Border.width` 1 pt (cards, controls), `Border.hairlineWidth` 0.75 pt (badges, tiles).
`.elevation(.flat | .raised | .floating)`: no shadow / card shadow / floating shadow.

### Motion (`Motion`)

| Token | Spec | Use |
|---|---|---|
| `snappy` | spring 0.28 / 0.82 | Taps, toggles, press states |
| `selection` | spring 0.35 / 0.82 | Sliding highlights (segmented controls, swatch rings, tab bar) |
| `smooth` | spring 0.45 / 0.86 | Layout changes, cards appearing |
| `bouncy` | spring 0.42 / 0.68 | Checkmarks, badges popping in |
| `fade` | ease-in-out 0.25 s | Opacity; the Reduce Motion replacement for movement |
| `color` / `themeCrossfade` | ease-in-out 0.35 s | Accent and appearance cross-fades |
| `gentle` | ease-in-out 0.6 s | Ambient loops only (glows, breathing) |
| `DeleteMotion` | press 0.18 → slide 0.22 → collapse spring 0.4 / 0.85 | Every delete |

Staggered entrances: 0.04 s per item, capped at 0.16 s so a list is fully in by about 0.3 s.

**Theme changes.** An accent change publishes once from `ThemeStore`, inside one 0.35 s
ease-in-out animation, so each view re-renders once and SwiftUI interpolates the colours; the
background Canvas blends its own colours from `ThemeFade`. System / Light / Dark switches use
`AppearanceCrossfade`: a snapshot of the screen fades out over the new appearance, so there is
never a white or black flash, even when switching quickly and repeatedly.

**Reduce Motion** swaps every slide, scale and sweep for a short fade (`Motion.adaptive`,
`reduceMotion ? Motion.fade : …`). The background drift stops and the shine sweep is removed.

## Components

| Component | File | Notes |
|---|---|---|
| `Card`, `CardSection`, `.cardBackground()` | `Card.swift` | Layered surface, top highlight, gradient hairline border |
| `SectionHeader` | `Components.swift` | Uppercase section title + optional trailing accessory |
| `ListRow` | `Components.swift` | Icon tile, title, subtitle, trailing; 44 pt minimum |
| `InfoRow` | `Card.swift` | Label / value; values are one line with middle truncation |
| `Pill` (= `StatusBadge`) | `StatusBadge.swift` | success / warning / danger / info / neutral |
| `IconTile` | `Components.swift` | Rounded coloured square with an SF Symbol (filled or tinted) |
| `StatTile` | `Components.swift` | Number + label + icon with numeric transition |
| `EmptyState` (= `EmptyStateView`) | `EmptyStateView.swift` | Icon, title, one line, one action; `.emptyStateEntrance()` |
| `ErrorState` | `Components.swift` | Plain-language title and message, Retry, "Details" disclosure; full or compact |
| `LoadingSkeleton`, `SkeletonBlock` | `Components.swift`, `Effects.swift` | Shimmering placeholder rows |
| `ToastView` / `ToastCenter` | `ToastView.swift` | Below the nav bar; optional action (Undo) |
| `AppButtonStyle`, `PrimaryButton`, `.buttonRow()` | `PrimaryButton.swift` | The only action button: 52 pt capsule (primary / secondary / destructive; compact 36 pt inside a row); `.buttonRow()` puts it under a card in a List |
| `SlidingSegmentedControl` | `SlidingSegmentedControl.swift` | One sliding highlight, equal segments, scrub, adjustable for VoiceOver |
| `CertificatePickerSheet` | `Views/Certificates` | Long-list picker as a bottom sheet with spring checkmark |
| `StorageRing`, `StorageSummaryCard`, `StorageCategoryRow` | `Views/Settings/StorageDashboard.swift` | Storage dashboard |
| `.deleteExit(_:)`, `DeleteMotion.run` | `DesignSystem.swift` | The one delete animation |
| `.glassShine()`, `ShinePressStyle`, `PressableButtonStyle` | `GlassShine.swift`, `Theme.swift` | Reflection, press flash, press scale |
| `.identifierText()` | `CertificatePickerSheet.swift` | Long IDs: one line, slight shrink, middle truncation |

## Rules

1. **Selection** always slides: any 2 to 5 option choice is a `SlidingSegmentedControl`; swatch
   pickers move one ring; long lists open a sheet whose checkmark springs in. No system `Menu` for
   choices with long labels.
2. **Two shapes only.** Actions (primary, secondary, destructive, Share) are `AppButtonStyle`
   capsules; navigation and information are rows inside a card. Buttons in a List sit under the
   card (`.buttonRow()`), never as the card's last row, so every card keeps four rounded corners.
   Buttons use `AppButtonStyle`, `ShinePressStyle` or `PressableButtonStyle`. Everything inside
   a button (background, border, glow, shine) is clipped to the button's own shape and its hit
   area is `.contentShape(shape)`. Minimum 44 pt hit target. Icon-only buttons have a VoiceOver label.
3. **Text** never wraps mid-word: identifiers use `.identifierText()`; certificates show
   `displayName`, never a raw ID, with the ID as small secondary text.
4. **Copy** is short and plain ("Couldn't refresh this source. Check your connection and try
   again."). Technical detail goes into the `ErrorState` "Details" disclosure.
5. **States**: every list has a loading skeleton, an empty state (icon, title, one line, one
   action) and an error state with Retry.
6. **Numbers** that change use `.numericTransition()` (iOS 17+) and tabular digits; sizes use
   `StorageService.format` (locale-aware, "Empty" for zero).
7. **Deletes** use `DeleteMotion.run` + `.deleteExit` on the row and its row background.
8. **Haptics**: `Haptics.selection()` for selection changes, `.impact(.light)` for taps and
   deletes, `.success()` / `.warning()` / `.error()` via toasts.
9. **iOS 26**: Liquid Glass (`glassEffect`) where available, the material fallbacks before.

## What changed in the design pass

- **Design system**:
  - New: `DesignTokens.swift`, `Components.swift`, `SlidingSegmentedControl.swift`.
  - `AppearanceCrossfade` added.
  - Theme cross-fade shortened to 0.35 s.
  - Literal spacing, padding and radii replaced with tokens in every screen.
- **Sliding selection**:
  - Settings:
    - Appearance (with the cross-fade).
    - Signing mode.
    - Install method (short titles).
    - Accent swatches (sliding ring).
    - App icon swatches (sliding ring).
  - Review & Sign:
    - Signing mode.
  - Library:
    - Sort & Filter is now a sheet with sliding Sort and Status controls.
    - Its certificate list has a spring checkmark.
  - Tab bar (iOS 16–25): one sliding pill. iOS 26 keeps the native Liquid Glass tab bar.
  - Certificate picker sheet: spring checkmark.
- **Storage**: dashboard with:
  - a ring chart;
  - device free space and the app's share of it;
  - a Reclaim pill;
  - five category cards, each with a detail screen (sort, swipe delete, Delete All);
  - sized action buttons (Clear Cache, Remove Unused IPAs, Clear Log) with "Freed …" toasts;
  - tips, the largest item and the oldest signed app;
  - recursive on-disk sizes, calculated off the main thread and cached.
- **Audit**:
  - Toasts use certificate display names.
  - Download errors are in plain language.
  - Source errors use `ErrorState` with Retry and Details.
  - Source screen has loading and empty states.
  - Counts animate with numeric transitions.
  - Staggered entrances are capped at 0.16 s.

## Performance rules

- Never publish per frame from an `ObservableObject` the whole tree reads. Animate one value
  with `withAnimation`; views that draw every frame (Canvas) interpolate locally.
- The background is one Canvas at 30 fps that holds still while scrolling, with a sheet up,
  in Low Power Mode, with Reduce Motion, with the background animation setting off and on hidden
  tabs (`BackgroundActivity`, `AuroraClock` holds). An accent change redraws it for the 0.35 s fade
  (colours blended from `ThemeFade`) even while the drift is held.
- Shadows go on a single base shape, not on layered groups. No looping effects (shine sweep)
  on repeated list rows.
