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

## 4. Two Rules of Liquid Glass

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
    .foregroundColor(selectedStyle == style ? .primary : .secondary)
    .frame(width: buttonWidth, height: 24)
    .liquidGlassControl(isActive: selectedStyle == style)
}
.buttonStyle(.plain)
```
Note the glyph is `.primary` when active, not `.accentColor`: the surface carries the accent tint,
so tinting the glyph too would put an accent icon on accent glass.

#### 4. Grouping Sibling Surfaces
Wrap a row of glass controls so the system samples once and lets neighbours merge optically on
macOS 26+ (passthrough on macOS 13–15):
```swift
HStack(spacing: 4) {
  ToolbarButton(treatment: .glass, icon: "crop", isSelected: isCropping) { beginCrop() }
  ToolbarButton(treatment: .glass, icon: "pencil", isSelected: isDrawing) { draw() }
}
.liquidGlassGroup(spacing: Spacing.xs)
```

#### 5. Window Backdrop (`LiquidGlassWindowBackdrop`)
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

Shared toolbar icon buttons live outside this folder in
`Snapzy/Shared/Styles/ToolbarControls.swift`. `ToolbarButton` takes a `treatment:` parameter that
defaults to `.standard`; pass `.glass` to opt a toolbar into the design system. `BottomBarButton`
(`Snapzy/Features/Annotate/Components/AnnotateBottomBarView.swift`) takes the same parameter.

The Annotate window is fully converted: toolbar icons and action buttons, the quick-properties bar
controls, and the bottom bar. The Video Editor deliberately still passes no `treatment:`, so it
keeps the pre-existing look — flipping it is a one-line change per call site.
