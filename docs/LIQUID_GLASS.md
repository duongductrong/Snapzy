# Liquid Glass Design System & Architecture

This document details the architectural foundation, rendering pipeline, component specifications, and developer guidelines for **Liquid Glass** in Snapzy, covering both Apple's official Liquid Glass APIs (macOS 26+) and Ruru's 4-layer optical composite model with backward compatibility for macOS 13.0+.

---

## 1. Overview & Problem Statement

Modern macOS designs frequently employ blurred, translucent materials to evoke physical glass. However, standard SwiftUI `.ultraThinMaterial` or basic `NSVisualEffectView` implementations suffer from critical visual flaws:
1. **Desktop Washout**: Pure glass or vibrancy materials placed over bright or white wallpapers wash out, reducing contrast below accessibility standards (< 4.5:1) and rendering white typography invisible.
2. **Flat Borders**: Solid 1px borders look artificial and disconnect from ambient lighting.
3. **OS Version Fragmentation**: Apple's dedicated Liquid Glass APIs (`.glassEffect()`, `GlassEffectContainer`, `.glassEffectID()`) are introduced in macOS 26+. Older macOS releases (macOS 13–15) require an optically faithful fallback.
4. **Subtree Isolation Glitch**: Wrapping glass materials in an animated `.opacity` or opacity transition isolates the view into an offscreen buffer, cutting off background sampling and blowing out the glass into an opaque white slab.

To solve these challenges, Snapzy adopts a **Dual-Path Architecture** centered around **Ruru's 4-Layer Composite Model**.

---

## 2. The 4-Layer Composite Model

```
┌────────────────────────────────────────────────────────┐
│ 1. Specular Border Overlay (0.5 pt Hairline)           │
│    • Inset strokeBorder(0.5pt)                         │
│    • Diagonal LinearGradient: .white.opacity(0.16→0.04)│
├────────────────────────────────────────────────────────┤
│ 2. Interactive Foreground Content                      │
│    • Typography, SF Symbols, Keycap Chips              │
│    • .tint(Color.clear) to prevent tint bleed          │
├────────────────────────────────────────────────────────┤
│ 3. Optical Refraction Layer                            │
│    • macOS 26+: .glassEffect(.regular.interactive())   │
│    • macOS 13–15: NSVisualEffectView or gradient sheen │
├────────────────────────────────────────────────────────┤
│ 4. Adaptive Substrate (appearance-resolved)            │
│    • Dark Aqua: black @ 0.28 · Aqua: white @ 0.154     │
│    • Guaranteed contrast ratio (> 4.5:1)               │
└────────────────────────────────────────────────────────┘
```

> **This composite is the macOS 13–15 path only.** On macOS 26+ `LiquidGlassSurface` short-circuits
> to `.glassEffect`, which supplies all four layers itself. Stacking the composite on top of native
> glass is what makes it read as a flat dark slab with a chalky white outline.

### Layer 1: Adaptive Substrate
- **Role**: Base fill placed beneath the glass refraction pass.
- **Tuning**: `LiquidGlassTokens.substrateFill` resolves to black under Dark Aqua and white under
  Aqua, and `LiquidGlassSurface` scales the opacity to `0.55×` in Aqua (light glass is thinner).
  Ink (`inkPrimary`/`inkBody`/`inkMuted`/`inkFaint`) inverts with it — hardcoding white ink made
  glass buttons invisible in the Annotate window's Light theme and in Preferences.
- **Why it matters**: Liquid Glass samples whatever sits directly behind it. Without a dark substrate, bright desktop wallpapers bleed through, causing text to lose contrast. The dark substrate ensures reliable translucency and crisp typography over arbitrary wallpapers (from solid black to bright white).

### Layer 2: Optical Refraction Pass
- **On macOS 26+**: Uses native `.glassEffect(.regular.interactive(), in: shape)`.
- **On macOS 13.0–15.x**:
  - *Backdrop Surfaces*: Bridged `NSVisualEffectView` configured with `.hudWindow` material, `.behindWindow` blending, and `.active` state.
  - *Nested Controls / Buttons*: Subtle linear gradient sheen (`.white.opacity(0.10)` to `.white.opacity(0.02)`) from `.topLeading` to `.bottomTrailing`. This avoids spinning up and tearing down AppKit view hierarchies during high-frequency pointer movements.

### Layer 3: Body Tint & Dim Wash
- **Role**: Optional substrate-direction wash (`dim`) or inverse veil (`tint`, via
  `LiquidGlassTokens.veilFill`) composited directly over the refraction layer.
- **Use Case**: Deepening expanded panels (dim) or creating vibrant floating chips and hovered buttons (tint).

### Layer 4: Specular Hairline Border
- **Role**: Simulates physical ambient lighting striking the edge of a curved glass slab.
- **Geometry**: Inset `strokeBorder` with `lineWidth = 0.5pt`.
- **Gradient**: `LinearGradient` from `.topLeading` to `.bottomTrailing`:
  - Resting: `.white.opacity(0.16)` $\rightarrow$ `.white.opacity(0.04)`.
  - Hover / Active: `.white.opacity(0.24)` $\rightarrow$ `.white.opacity(0.08)`.

---

## 3. Official Liquid Glass vs. Legacy Fallback

| Feature | Official macOS 26+ API | macOS 13–15 Fallback |
| :--- | :--- | :--- |
| **Refraction Engine** | `.glassEffect(.regular.interactive(), in: shape)` | `NSVisualEffectView` (`.hudWindow`) or gradient sheen |
| **Edge Lighting** | Native specular refraction + custom hairline | Specular hairline diagonal gradient (`0.5pt`) |
| **Optical Merging** | `GlassEffectContainer(spacing:)` merges adjacent shapes | Static layout with uniform spacing |
| **Morphing Identity** | `.glassEffectID(id, in: namespace)` | Passthrough / matched geometry effect |
| **Performance** | Metal-accelerated real-time shader | Hardware-accelerated AppKit compositor |

Path selection lives in one place — `LiquidGlassCapabilities.hasNativeLiquidGlass` and the
`#available(macOS 26.0, *)` branch at the top of `LiquidGlassSurface.body`. Call sites pass both
sets of knobs (`substrate`/`tint` for the composite, `glassTint`/`isInteractive` for native) and the
surface ignores whichever set does not apply. Callers that draw their own edge stroke must gate it
on `!LiquidGlassCapabilities.hasNativeLiquidGlass`; native glass already has a refractive edge, and a
second stroke on top is what produces a white outline.

### Debugging & Testing Fallbacks
To test how components look on macOS 13–15 when developing on macOS 26+, launch the app with:
```bash
-SnapzyForceLegacyGlass
```
or set the environment variable:
```bash
SNAPZY_FORCE_LEGACY_GLASS=1
```

---

## 4. Three Rules of Liquid Glass

### Rule 1: Glass contributes no hit-testable content

`.glassEffect` draws a surface but adds nothing clickable. A label made only of an SF Symbol
hit-tests just its glyph, so an icon button whose background is glass has a dead margin — the user
has to hit the symbol itself. The fill-based chrome it replaced did not have this problem, because
`Color.clear` *is* hit-testable.

Always pair a glass surface with an explicit `.contentShape(shape)` on the same frame. This is
already handled inside `.liquidGlassControl(isActive:)`, `ToolbarButton`, and `BottomBarButton`.

### Rule 2: The Golden Rule

> **Never place an animated `.opacity` or `.opacity` transition directly on a view containing Liquid Glass.**

This includes the *implicit* transition SwiftUI applies when conditional content is inserted or
removed. Rendering a surface only `if isSelected || isHovering` is the same bug in disguise. Use
`isVisible:` on `liquidGlassSurface(...)` instead — it maps to `Glass.identity` on native, keeping
the effect in the hierarchy so nothing is ever inserted or removed. That also means resting controls
do no backdrop sampling, so a dense property bar costs what its *lit* surfaces cost, not what its
button count suggests.

### Why It Breaks:
Liquid Glass is a backdrop filter: it determines light vs. dark by sampling the composite behind itself, including Layer 1 (the dark substrate).

When you animate `.opacity` on a SwiftUI subtree, SwiftUI promotes that subtree to an offscreen layer buffer. This promotion severs the backdrop connection, causing the glass to stop sampling the dark substrate underneath. The glass detects only the document or desktop behind the window and resolves to its **light variant** (sampling ~232/255 white instead of ~109/255 dark). The surface flashes into an opaque white slab, obliterating white text.

### The Correct Patterns:
1. **Fade the Window**: Animate `NSWindow.animator().alphaValue` instead of view opacity.
2. **Use Scale or Offset**: Animate `.scaleEffect` or `.offset`, which SwiftUI folds into transformation matrices without layer detachment.
3. **Fade Color Fills**: Animate the opacity of the fill color (`Color.black.opacity(val)`) rather than `.opacity()` on the container.

### Rule 3: Ink on a tinted surface is resolved against the tint, never the appearance

`.glassEffect(.regular.tint(_:))` floods the surface with its tint, and an accent or red tint is
dark in *both* appearances. Adaptive ink (`inkPrimary`, `.primary`, `.label`) follows the app
appearance instead, so in Light theme it resolves near-black and lands black glyphs on a blue pill
— around 3:1, failing AA. Every selected control in the app shipped that way: the Annotate
toolbar's tools, the quick-properties bar, the Video Editor transport, the recording toolbar's
output rows, the segmented control.

Ask `LiquidGlassTokens` for the ink instead of hardcoding it:

```swift
Image(systemName: icon)
  .foregroundColor(isSelected ? LiquidGlassTokens.inkOnAccent : .primary)
  .liquidGlassChrome(shape: shape, isVisible: showsGlass, isActive: isSelected,
                     glassTint: isSelected ? .accentColor : nil)
```

- `LiquidGlassTokens.ink(onTint:otherwise:)` picks the ink from the tint's sRGB luminance, so a
  yellow or orange system accent flips to dark glyphs instead of shipping white-on-yellow.
- It returns the adaptive fallback when there is **no** tint, and on macOS 13–15, where the
  composite drops `glassTint` entirely and signals state with a substrate step instead.
- `LiquidGlassTokens.inkOnAccent` is the shorthand for the accent tint every `isActive` control uses.

The glyph still never carries the tint itself — an accent icon on accent glass disappears. The
surface tints; the ink contrasts.

---

## 4b. Corner Radius Scale

Radius lives in `Snapzy/Shared/Styles/RadiusTokens.swift` (`enum Radius`) and is shared by glass
and non-glass chrome alike. `LiquidGlassTokens.controlRadius`/`cardRadius`/`surfaceRadius`/
`windowRadius` are pass-throughs onto it, not a second scale.

### The rule: roundness is a function of control height

A fixed radius applied across sizes makes small controls look circular and large ones look boxy.
Every control token sits near **`0.36 × height`**, so a 24pt chip and a 32pt button read as the
same family:

| Token | Value | Control height |
| :--- | :--- | :--- |
| `controlXS` | 6 | ≤ 19pt — keycaps, inline badges, mini toggles |
| `controlS` | 8 | 20–25pt — property-bar chips, segment buttons |
| `controlM` | 10 | 26–30pt — toolbar/bottom-bar icon buttons, selects, fields |
| `controlL` | 12 | 31–36pt — recording toolbar buttons |
| `controlXL` | 14 | ≥ 37pt — stacked icon+label buttons |

**Do not pick a token by eye.** State the height you already know:

```swift
.frame(width: ControlMetrics.toolbarButton, height: ControlMetrics.toolbarButton)
.liquidGlassChrome(
  shape: Radius.controlRect(forHeight: ControlMetrics.toolbarButton),
  isVisible: showsGlass
)
```

`Radius.control(forHeight:)` snaps `height × 0.36` to the nearest ramp entry; ties resolve
downward. `ControlMetrics` holds the heights the shared chrome is built at, so a height and its
radius cannot drift apart.

Containers are **not** proportional — a 400pt inspector does not want a 144pt radius — so they stay
semantic: `ornament` 4 (badges, keycap plates, hairline frames), `tile` 8 (grid thumbnails, preset
tiles), `card` 14 (cards, rows, floating bars), `panel` 20 (popovers, inspectors), `window` 26.

### Shape families

Radius is only half the system. The shape a control takes states what class of control it is:

| Shape | Reserved for |
| :--- | :--- |
| `Capsule` | Terminal text actions (`Done`, `Save As`, `Apply`) and selection tracks (the segmented control and its sliding indicator). The pill *is* the "this commits" signal. |
| `Radius.controlRect(forHeight:)` | Every other interactive control: icon buttons, toggle chips, **selects and dropdowns**, ratio buttons, text fields. |
| `Circle` | Only where the content is inherently round — colour swatches, radio dots. |

A square icon button is deliberately not promoted to a capsule: at 28×28 a capsule *is* a circle,
which reads as a different control class (destructive, media transport) and loses the glyph's
optical alignment. `controlM` closes most of the gap to the neighbouring `Done` pill while keeping
the button legibly rectangular.

A select is not a terminal action, so the Annotate zoom picker takes the rounded-rect control
shape rather than a capsule — which also puts it on the same radius as the `BottomBarButton`s
beside it.

Grid cells that share an edge (the sidebar's 3×3 alignment picker) stay at `ornament`: a
control-sized radius on abutting tiles opens visible gaps between them.

### Always `.continuous`

At an identical radius, circular corners read *squarer* — the curvature starts abruptly instead of
easing in — so mixing the two styles reintroduces the inconsistency the scale exists to remove.
`Radius.rect(_:)` and `Radius.controlRect(forHeight:)` pin it for you; prefer them over a bare
`RoundedRectangle`.

### Legacy

`Size.radiusXs/Sm/Md/Lg` (DesignTokens.swift) predate this and name a size rather than a use,
which is how a 32pt recording button and a 12pt badge both ended up asking for `radiusSm`. They
are kept at their original values so untouched surfaces do not move. New code uses `Radius`;
migrate a legacy call site when you are already editing its surface.

The scale is rendered live in the Liquid Glass playground under **Overview & Tokens →
Geometry & Hairline Physics**, so it cannot go stale.

---

## 5. Component System

### A. Liquid Glass Button (`LiquidGlassButton` / `LiquidGlassButtonStyle`)

Provides 4 distinct emphasis tiers, physical hover lighting, and tactile spring feedback:

| Emphasis | Resting Substrate | Hover Substrate | Pressed Substrate | Border Hairline (Hover) |
| :--- | :--- | :--- | :--- | :--- |
| **`.primary`** | `0.20` | `0.28` | `0.38` | `0.36` $\rightarrow$ `0.14` |
| **`.secondary`** | `0.12` | `0.22` | `0.30` | `0.28` $\rightarrow$ `0.08` |
| **`.destructive`** | `0.10` (+ red tint) | `0.20` (+ red tint) | `0.30` (+ red tint) | `0.40` $\rightarrow$ `0.14` |
| **`.contextPill`** | `0.20` | `0.28` | `0.36` | `0.28` $\rightarrow$ `0.10` |

> These levels apply to the **macOS 13–15 composite only**. On macOS 26+ the substrate, tint, and
> hairline are all supplied by `.glassEffect`; emphasis maps to `Glass.tint(_:)` instead —
> `.primary` → accent, `.destructive` → red, `.secondary`/`.contextPill` → untinted (accent when
> `isActive`).

#### Spring Physics:
- **Hover**: `.spring(response: 0.28, dampingFraction: 0.75)`
- **Press Scale**: Instant micro-scale `0.97` via `.spring(response: 0.18, dampingFraction: 0.8)`

```swift
Button("Save Screenshot") {
  saveAction()
}
.buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
```

#### Shortcut Keycaps:
Use `LiquidGlassActionButton` to display trailing shortcut glyphs without tooltip hover delays:
```swift
LiquidGlassActionButton(
  title: "Copy",
  trailingKey: "⌘C",
  emphasis: .secondary
) {
  copyAction()
}
```

---

### B. Liquid Glass Segment & Tabs

Snapzy provides two segmented paradigms for different interaction models:

#### 1. Sliding-Indicator Segmented Control (`LiquidGlassSegmentedControl`)
Ideal for view modes, filtering, and tab selection:
- Capsule/rounded container with dark translucent backing.
- Continuous sliding indicator pill driven by SwiftUI `.matchedGeometryEffect` and spring animation.
- Clean typography: active tab highlights to `.white`, inactive stays at `0.72` opacity.

```swift
LiquidGlassSegmentedControl(
  items: ["Capture", "Record", "OCR"],
  selection: $selectedMode
) { mode in
  Text(mode)
}
```

#### 2. Etched-Divider Action Bar (`LiquidGlassActionBar`)
Ideal for grouped actions, dialog footers, and floating multi-action toolbars:
- Unified `Capsule(style: .continuous)` outer glass surface.
- Vertical etched hairlines: `LinearGradient` (transparent $\rightarrow$ `0.18` white $\rightarrow$ transparent, `0.5pt` width).
- Nested interactive segments that independently highlight on hover while sharing the common glass capsule.

```swift
LiquidGlassActionBar(
  cancelTitle: "Skip",
  confirmTitle: "Continue",
  confirmKey: "↩",
  onCancel: { dismiss() },
  onConfirm: { proceed() }
)
```

---

### C. Custom View & Window Containers

#### 1. Generic Glass Surface
`LiquidGlassSurface` renders the surface itself — it takes no content closure, so use it as a
background:
```swift
VStack(alignment: .leading) {
  Text("Floating Card Header").font(.headline)
  Text("Detailed card content inside a glass container.")
}
.padding(16)
.background {
  LiquidGlassSurface(
    shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
    substrate: LiquidGlassTokens.baseDarkness,
    tint: 0.04
  )
}
```

#### 2. Convenient View Modifier
```swift
VStack {
  Text("Quick Access Card")
}
.padding()
.liquidGlass(
  shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
  substrate: LiquidGlassTokens.baseDarkness,
  tint: 0.04,
  isInteractive: true
)
```

#### 3. Compact Property-Bar Controls
`.liquidGlassControl(isActive:)` replaces the fill-plus-stroke chrome used by small toggle and
segment buttons. Apply it to the control's **label content**, inside the `Button` — it owns its own
hover state and declares the hit target:
```swift
Button { select(style) } label: {
  Image(systemName: style.icon)
    .font(.system(size: 12, weight: .semibold))
    .foregroundColor(selectedStyle == style ? LiquidGlassTokens.inkOnAccent : .secondary)
    .frame(width: buttonWidth, height: 24)
    .liquidGlassControl(isActive: selectedStyle == style)
}
.buttonStyle(.plain)
```
Note the glyph is never `.accentColor` when active — the surface carries the accent tint, so
tinting the glyph too would put an accent icon on accent glass. It is not `.primary` either: see
Rule 3, active glyphs take `LiquidGlassTokens.inkOnAccent`.

`liquidGlassControl` also has a shape-generic overload (`in: Circle()`, `in: Capsule()`) for round
and pill controls.

#### 4. Caller-Owned Chrome (`.liquidGlassChrome`)

`liquidGlassControl` tracks its own hover, which is what a self-contained property-bar control
wants. Toolbar and card buttons instead derive visibility from state the parent already holds, so
they drive the surface directly:

```swift
Image(systemName: icon)
  .frame(width: 28, height: 28)
  .liquidGlassChrome(
    shape: RoundedRectangle(cornerRadius: Size.radiusMd, style: .continuous),
    isVisible: isEnabled && (isSelected || isHovering),
    isActive: isSelected,
    glassTint: isSelected ? .accentColor : nil
  )
```

This is the single place the icon-button composite is tuned — `ToolbarButton`, `BottomBarButton`,
`ToolbarIconButtonLabel`, and `AnnotationToolbarIconButton` all route through it, and
`liquidGlassControl` is built on top of it.

##### Emphasis tiers

| Emphasis | Resting substrate (13–15) | Active substrate (13–15) | Native glass tint | Ink |
| :--- | :--- | :--- | :--- | :--- |
| **`.standard`** | `0.14` | `0.24` | none (caller supplies selection tint) | `inkPrimary` at rest, `inkOnAccent` once the caller tints it |
| **`.overlay`** | `0.34` | `0.44` | black `0.38` → `0.52` on hover | `inkOverlay` (always light — the tint pins the glass dark) |

> **On the native path, the tint is the only knob you have.** `substrate` and `tint` are macOS
> 13–15 composite knobs that `.glassEffect` ignores outright, and a fill placed *behind* the
> surface is not part of what the material samples either — measured side by side, a black `0.42`
> fill behind a glass capsule is indistinguishable from no fill at all. `.interactive()` adds no
> pointer response on macOS either. So persistent chrome signals state through
> `LiquidGlassChromeEmphasis.glassTint(isActive:)`. Chrome that *materialises* on hover is fine
> as-is: flipping `isVisible` swaps `Glass.identity` for `Glass.regular`, and that is the tell.

`.overlay` is for chrome that floats over *user content* — the pinned window's zoom pill and drag
handle. It pins the ink light (`inkOverlay`) rather than letting it flip with the drawing appearance,
because a capture's brightness has nothing to do with Light or Dark Aqua.

> **Overlay chrome pins its own material dark.** Left untinted, `.glassEffect` resolves *light*
> over a bright screenshot and the white glyph lands at roughly 1.5:1. The fix is a dark tint on
> the glass itself, not a fill behind it: a tint colours the material and keeps it refracting,
> which a backing fill cannot do because the material never sees it. Hover *deepens* the tint
> rather than brightening it, so the state change can never cost the glyph contrast. Past `~0.55`
> the surface stops reading as glass and turns into a grey slab, so the pair is tuned to `0.38` / `0.52`.

#### 5. Grouping Sibling Surfaces
Wrap a row of glass controls so the system samples once and lets neighbours merge optically on
macOS 26+ (passthrough on macOS 13–15):
```swift
HStack(spacing: 4) {
  ToolbarButton(icon: "crop", isSelected: isCropping) { beginCrop() }
  ToolbarButton(icon: "pencil", isSelected: isDrawing) { draw() }
}
.liquidGlassGroup(spacing: Spacing.xs)
```

#### 6. Window Backdrop (`LiquidGlassWindowBackdrop`)
For borderless HUD panels, floating tools, and onboarding windows:
- `.hudWindow` vibrancy backdrop.
- Directional vertical scrim (`0.46` $\rightarrow$ `0.38` $\rightarrow$ `0.44`) for high header contrast.
- Subtle radial bloom (`RadialGradient` in `.topLeading` corner).
- Top specular hairline fading smoothly before the corners turn.

```swift
struct MyHUDWindowView: View {
  var body: some View {
    ZStack {
      LiquidGlassWindowBackdrop(cornerRadius: 24)
      ContentView()
    }
  }
}
```

---

## 6. Leading & Trailing Optical Lighting Architecture

Real convex glass capsules and cylindrical lenses exhibit dramatic tangential light catchments at their curved extremities (the leading and trailing caps):

```
┌────────────────────────────────────────────────────────┐
│  ╭─[Primary Glint]─────────[Top Specular]───────╮      │
│ (  [Leading Flare]         [Lens Sheen]        )     │
│  ╰──────────────────────────────────────[Rim]───╯      │
└────────────────────────────────────────────────────────┘
```

1. **Convex Rim Lighting (`LiquidGlassRimBorder`)**:
   - In addition to the standard diagonal hairline, a horizontal `LinearGradient` spans from `.leading` to `.trailing`.
   - **Leading Edge**: Catches primary ambient light with high specular intensity (`0.34` resting $\rightarrow$ `0.56` hover) along the convex cap.
   - **Trailing Edge**: Catches secondary refractive back-scattering (`0.22` resting $\rightarrow$ `0.42` hover).
   - Rendered with a dedicated `0.75pt` stroke width for pronounced edge definition.
2. **Internal Caustic Blooms & Lens Sheen (`LiquidGlassCaustics`)**:
   - **Leading Radial Glare**: A localized `RadialGradient` anchored at `.leading` (radius 30pt) fills the leading curved cap with an internal optical glow (`0.18` resting $\rightarrow$ `0.32` hover).
   - **Trailing Radial Glare**: A localized `RadialGradient` at `.trailing` (radius 26pt) provides balanced refraction (`0.12` resting $\rightarrow$ `0.24` hover).
   - **Vertical Lens Thickness**: Vertical gradient (`.top` to `.bottom`) providing subtle top lip reflection and bottom ground bounce.
3. **Live Backdrop Material & Elevation**:
   - Backed by `.ultraThinMaterial` for authentic optical blurring of the desktop or window underneath.
   - Grounded with soft contact elevation shadow (`y: 1.0` resting $\rightarrow$ `y: 2.0` hover) to lift the glass element off the substrate.

---

## 7. Directory Structure

```
Snapzy/Shared/DesignSystem/LiquidGlass/
├── LiquidGlassTokens.swift            # Substrates, strokes, colors, rim/glare tokens, capability check
├── LiquidGlassVibrancy.swift          # AppKit NSVisualEffectView bridge (.hudWindow)
├── LiquidGlassLighting.swift          # Rim lighting stroke and radial caustic bloom components
├── LiquidGlassSurface.swift           # Dual-path LiquidGlassSurface<Shape> and .liquidGlass()
├── LiquidGlassContainer.swift         # .liquidGlassGroup()/.liquidGlassID() → macOS 26+ grouping
├── LiquidGlassControlChrome.swift     # .liquidGlassControl() for compact property-bar controls
├── LiquidGlassWindowBackdrop.swift    # Window HUD backdrop with radial bloom and edge light
├── LiquidGlassButton.swift            # LiquidGlassButtonStyle and LiquidGlassActionButton
├── LiquidGlassButtonSurface.swift     # Hover/press surface backing the button style
├── LiquidGlassSegmentedControl.swift  # Sliding indicator segmented control
├── LiquidGlassActionBar.swift         # Etched-divider grouped action bar
└── LiquidGlassPreview.swift           # Interactive demo and playground (DEBUG only)
```

Shared icon buttons live outside this folder in `Snapzy/Shared/Styles/ToolbarControls.swift`,
and the corner-radius scale in `Snapzy/Shared/Styles/RadiusTokens.swift` (see §4b).
`ToolbarButton` and `BottomBarButton` are glass-only — there is no longer a `treatment:` opt-in,
because every call site uses the design system.

### Converted surfaces

| Surface | What moved to glass |
| :--- | :--- |
| **Annotate** | Toolbar icons and action buttons, quick-properties bar, bottom bar (action buttons & mode segmented control) |
| **Video Editor** | Toolbar (via `ToolbarButton`), rename field, playback transport + play/pause, bottom bar (`.liquidGlass` emphasis buttons, shared `BottomBarButton`) |
| **Quick Access** | Pinned-window zoom pill, drag handle, chrome buttons, zoom picker rows (card buttons use standard translucent controls) |
| **Recording toolbar** | `ToolbarIconButtonLabel`, record/options/stop button styles, capture-area toggle, output-mode dropdown and its rows, option pills |
| **Recording annotation toolbar** | `AnnotationToolbarIconButton` |
| **History floating panel** | Filter pills, round control buttons, search bar and selection bar surfaces |

Colour swatches and stroke-width pickers keep their solid fills on purpose: they *encode* a colour,
and glass would wash the sample out.

### Rule 2 fixes made during the rollout

Converting a surface means auditing everything that animates around it. These were real violations
found and fixed:

- `ToolbarButton` / `BottomBarButton` now dim their own glyph when disabled, so call sites no longer
  wrap them in `.opacity()`.
- `RecordButtonWithBadge` dimmed the whole button while preparing to record; that moved onto the
  label.
- The History selection bar faded in with `.opacity.combined(with: .scale)`; it is scale-only now.
