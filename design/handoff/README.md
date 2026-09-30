# Handoff: Redline — iPad markup, drawing & notes app

## Overview
Redline is an iPad app with three document types sharing one annotation engine:

- **Markup** — PDF annotation (draw, annotate, edit, forms, comments/review).
- **Drawing** — layered sketching over a base sheet (trace layers with a white "veil" opacity, flatten).
- **Notes** — paged notebook (paper colours, templates, tags, book/calendar views).

The core product decision: **one shared tool/style system**. Every section uses the same toolbar behaviour, the same Style Popover, and the same colour palettes (managed in Settings). A change to a preset in one place is visible everywhere.

## About the design files
The `.dc.html` files in this bundle are **design references built in HTML** — interactive prototypes that show intended look and behaviour. They are **not** code to port. The task is to **recreate these designs natively in Swift/SwiftUI** (iPadOS 17+, PencilKit-style input is expected but the rendering model below is custom) using standard Apple frameworks and patterns. Where the HTML uses a browser affordance (e.g. `window.prompt` for Rename), substitute the native equivalent (alert with text field / inline edit).

Open the HTML files in a browser to explore states; every screen is reachable from the Home screen.

## Device sizing (IMPORTANT)
The HTML prototype uses fixed CSS px tuned for **iPad Pro 12.9" / 13" landscape (1366×1024 pt)**. The Swift app must be **adaptive**, not a fixed layout:

- **Target devices**: all iPads, iPadOS 17+, portrait and landscape, plus Split View / Slide Over. Use size classes and `GeometryReader`/layout, never hard-coded screen widths.
- **Fixed values that stay fixed** (they are pt sizes, not proportions): bar height 54, tool button 36×36, sidebar 232/262, Home nav 240, Settings nav 250, popover width 250, presets popover 176, modals 560/400 (capped at 92 % of width), radii, type sizes, paddings. Treat every px in this README as **pt**.
- **What flexes**: the canvas area takes all remaining space; `fit width` zoom = (available width − sidebar) ÷ canvas logical width (1000 or 600/1200 for spreads). Recompute on rotation and Split View resize.
- **Compact width (< ~900 pt, e.g. portrait 11", Split View, Slide Over)**: sidebar becomes an overlay sheet (toggle button in the top bar already exists) instead of a persistent column; the Home/Settings left nav collapses into a navigation stack; the tool row **scrolls horizontally** — the prototype shows a scrollbar in the Markup Draw tab at ~920 pt, which is the intended behaviour (`ScrollView(.horizontal)` with no indicator), not a bug to fix by shrinking buttons.
- **Regular width (≥ 900 pt)**: layouts as shown in the screenshots — persistent right sidebar, persistent left nav on Home/Settings.
- **Popovers** anchor to the pressed tool button and clamp inside the safe area; on compact width present them as `.popover` with `presentationCompactAdaptation(.popover)` so they never become full sheets.
- **Touch targets**: every tappable element is ≥ 44×44 pt hit area even when the visible glyph is 36 (add padding/contentShape). Apple Pencil hover/pressure supported on the canvas; finger pans/zooms by default.
- Respect safe areas (rounded corners, home indicator) — bars extend under them with material; content is inset.
- Screenshots were captured at 924×540 CSS px (a 2:1-ish letterboxed frame); use them for look and hierarchy, not absolute measurement — the numbers in this README are authoritative.

## Fidelity
**High-fidelity.** Colours, sizes, spacing, radii and copy are final. Recreate pixel-close using SwiftUI, but map to system semantics where they exist (system blue accent, `.regularMaterial` bars, SF Symbols). Light and dark themes are both specified.

---

## Architecture summary (what to build)

### Document model
```
Document { id, type: markup|drawing|journal, name, created, modified, pages: [Page] }
Markup Page   { id, strokes: [Stroke], fields: [FormField] }      // + doc.comments: [Comment]
Drawing Page  { id, layers: [Layer] }
Notes Page    { id, tpl: blank|dot|grid|lined, paper: white|cream|grey|blue|dark, tags: [String], strokes }
Layer   { id, name, kind: base|trace, opacity 0–1 (veil strength), visible, locked, strokes }
Stroke  { id, tool, color, pts: [[x,y,pressure]], cid? (linked comment id), ...tool extras }
Comment { id, pageId, kind, author, time, status: Open|Accepted|Completed, text, color, replies:[{author,time,text}] }
FormField { id, type: text|check|radio|drop|list|date|sig, name, x,y,w,h, value, def, tab, valid, calc, req, opts }
```
Canvas logical sizes: Markup/Drawing sheet **1000×707**, Notes page **600×800** (spread = 1200 wide). Default zoom 0.72; fit-to-width on open.

Per-document **undo/redo** stacks (snapshot-based, cap 100).
Persistence: docs, settings, presets (`sets`, `setSel`), theme, active shelf.

### Shared style system (the heart of the app)
Every stylable tool has **4 presets**. State per tool: `sets[tool] = [preset×4]`, `setSel[tool] = selectedIndex`.

Preset shape: `{ c: color, w: width, op?: opacity }`; shapes add `{ f: fill, fp: fillPattern, fo: fillOpacity }`; Text adds `{ bg, bgo, bc, bco, bw }` (background, bg opacity, border colour/opacity/width).

Default widths / opacity (Notes & Drawing pens):
- Rollerball w 2.4 · Fineliner w 1.3 · Felt tip w 4.2 · Marker w 14, op .55 · Highlighter w 22, op .4

Width ranges (min–max): roller 1–6, fine .5–3, felt 2–10, marker 6–30, highlighter 10–36, rect/ellipse 1–8, text 1–14.

Default preset colours:
- Rollerball/Fineliner: `#1c1c1e #e8483f #007AFF #34C759`
- Marker/Highlighter: `#ffd60a #ff6fa8 #34C759 #007AFF`
- Everything else: `#e8483f #1c1c1e #007AFF #FF9500`

Markup (PDF Annotator) tool defaults: Highlighter `#FFCC00` w5 · Text box `#FF3B30` · Sticky note `#FFCC00` w2.5 · Signature `#1c1c1e` w2.5 · Rollerball `#1c1c1e` w2 · Fineliner `#007AFF` w1 · Felt `#34C759` w4 · Bucket fill `#FFCC00` opacity .5 · Marker `#FF9500` w6 · Check `#34C759` w4 · X mark `#FF3B30` w4.

### Toolbar interaction (identical in all three sections)
- **Tap** a tool → selects it. Tapping the already-active tool **deselects** (returns to Select).
- **Long-press (450 ms)** a tool that has presets → opens **Tool presets** popover (4 circles) anchored under the button. Tapping a preset selects it; tapping the *already-selected* preset expands into the full **Style Popover**.
- Tool icon **tints to the active preset colour**. If that colour is unreadable (luminance > .9 in light, < .22 in dark) fall back to `ink1`.
- Active tool button bg: `hov2` (rgba(0,0,0,.08)) when tinted, else accent blue with white glyph.
- Toolbar height 54, buttons 36×36 radius 9, gap 3, horizontal padding 12.

### Style Popover (StylePopover.dc.html) — width 250, padding 14, radius 14
Sections stack top→bottom; show only those relevant to the tool:
1. **Presets row** — 4 × 30px circles, gap 12, selected has 2.5px ring in accent. Glyph inside shows tool weight/colour.
2. **Target segment** (shapes/text only) — Stroke · Fill · (Text: Text · Background · Border). Segmented control bg `hov`, radius 8, selected pill `card` with shadow `0 1px 3px rgba(0,0,0,.14)`.
3. **Colour** header (11px/700 uppercase, letter-spacing .5, `ink4`) + **12-column grid** of the quick palette (`#1c1c1e #6d6d72 #ffffff #e8483f #FF9500 #ffd60a #34C759 #00a3a3 #007AFF #5856D6 #AF52DE #ff6fa8`), square cells, 8px radius on group, selected cell ringed.
4. **Palettes** disclosure card (40px row, palette icon, dot preview of 4 colours, chevron rotates). Expanded: each user palette as name + 12-col swatch grid (radius 6, gap 4); footer link **"Manage palettes in Settings…"** in accent.
5. **Fill pattern** (shapes, Fill target) — 5 options: None · Solid · Hatch · Cross · Dots. 26px swatch preview + 9.5px label.
6. **Line weight / Stroke width** slider (system slider, accent tint) + value label 12px/700 `ink2` right-aligned min-width 36.
7. **Line weight mode** (pens): segmented **Constant · Pressure** with 64×12 stroke preview.
8. **Border size** slider 0–6 step .5 (Text border).
9. **Line style** — Solid · Dashed · Dotted, 3 equal tiles, radius 6, ring 2px accent when selected.
10. **Opacity** slider .1–1 step .05.
11. **Preview** row: label 11px `ink4` + live swatch (pill for pens, 30px rounded rect for shapes, "Text note" chip for text).

Popover appears with 160 ms fade+6px slide-down. Tap outside dismisses.

### Colour palettes (Settings → General · Color palettes)
- Split view: left list (320 max) of palettes (built-in first, then custom) with **New** button (accent, 34px, radius 9); right editor.
- Built-in palettes are **locked** ("Built-in palettes can't be edited. Duplicate one to make your own."). Custom: rename inline, add/remove swatches, delete palette (34×34 `bg3` button).
- New palette seeds `['#FF3B30','#007AFF','#34C759','#FFCC00']`, name "New palette".
- Changes propagate **live** to every open Style Popover.

---

## Screens

### 1. Home (Redline Studio → "Home")
- Left nav 240 wide, bg `bg2`, right border `line`, padding 18/12. Title "Redline" 22px/700.
- Shelves: **Markup · Drawing · Notes**, plus Settings gear at bottom. Selected row: `card` bg, radius 9.
- Content: document grid of cards (thumbnail, name 14px/600, modified "2h ago"), **New** button opens *New document* sheet.
- **New document** modal: 560 wide, radius 16, shadow `0 20px 60px rgba(0,0,0,.3)`; name field 40px radius 9; per-type options (Notes: paper colour + template pickers; Markup: choose a PDF template / import).

### 2. Markup workspace (PDF Annotator, embedded)
- Top bar 54: back chevron "Markups" (accent 15px), doc title, undo/redo, zoom −/+, ruler, search, share/export, sidebar toggle.
- Second bar 54: **tab segment** Favorites ★ · Draw · Annotate · Edit · Forms, then that tab's tools:
  - Draw: pen, fineliner, felt, marker, fill, eraser, rect, ellipse, line, arrow, dblarrow, polyline, polygon, check, xmark, cloud, distance, perimeter, area, calibrate
  - Annotate: select, lasso, highlighter, underline, strike, squiggly, textbox, note, callout, stamps, signature, datestamp, initials
  - Edit: edittext, image, link, redact, rotatepg, crop
  - Forms: ftext, farea, fcheck, fradio, fdrop, fdate, fsig, ftoggle
  - Favorites: user-ordered tray (drag to reorder), edit mode toggles.
- Optional **open-document tabs** row 48px (`bg2`, tabs radius 9 9 0 0, min 130 / max 230).
- **Sidebar (right, 232)** segment: Comments · Forms · Pages. Comments list: avatar (initials, colour from `AV` set), author, time-ago, status chip (Open/Accepted/Completed), text, replies, reply field. Tapping a comment highlights its linked stroke on the page.
- Overlays: Favorites tray, Stamp gallery (2-col), Tool presets, Style Popover, Export sheet (300 wide, top-right: doc name, Flattened PDF / Annotated PDF / Share…), Organize pages (full canvas overlay, page grid with rotate/duplicate/delete/reorder).
- Measure/edit tools currently show a toast "…preview-only" — real implementation TBD.

### 3. Drawing workspace
- Same two bars. Tool set: Select, Rollerball, Fineliner, Felt tip, Marker, Eraser, Text, Rectangle, Ellipse (no Highlighter).
- Sidebar (right, 262): **Layers · Pages**.
- **Layer row**: thumbnail (renders last 80 strokes, min stroke w 6), name 12.5px/600, eye toggle, ⋯ button. Active layer has accent border; hidden layer row at 55 % opacity. No subtext.
- **⋯ menu** (in-row, reveals): Opacity slider (trace layers), **Rename**, Lock/Unlock, **Flatten down** (trace only). Menu bg `hov`, items 12px/600 radius 7 padding 6/8.
- **+ Layer** adds "Layer N" trace at opacity .5 above active.
- **Flatten all** button appears when > 2 layers. **Flatten dialog** (400 wide, radius 16): title, description, two option cards (Keep veil / Ink only — Keep disabled at 45 % when impossible), Cancel.
- Layer veil model: each trace layer paints `rgba(255,255,255,opacity)` over everything beneath it; ink stays full strength. Footer note copy: "Layers veil everything beneath them. Ink on each layer stays full strength; hidden layers lift their veil."
- Locked active layer shows a "layer locked" hint and blocks drawing.

### 4. Notes workspace
- Top bar centre segment **Pages · Calendar**; spread toggle (single/facing pages); page flip via horizontal drag with a live curl-less slide (`flipDx`).
- Same toolbar as Drawing plus Highlighter.
- Sidebar (right, 262): **Pages · Tags**. Pages: thumbnails with paper/template. Tags: tag chips, search field, filter → page results ("N pages tagged "x"", "Tap a tag to filter").
- Paper colours: white `#ffffff`, cream `#f7f0dc`, grey `#e6e6ea`, blue `#dfe9f5`, dark `#2b2b30`. Templates: blank, dot (24 grid, 1px dots .28 alpha), grid (28px, .1 alpha), lined (32px, .14 alpha).
- **Calendar view**: month grid 7×6, prev/next 32px buttons, days with pages show a mini thumbnail; today ringed in accent. Date mode toggle Created/Modified.
- Tag popover for adding tags to current page.

### 5. Settings (full-screen, left nav 250)
Back link "‹ …" in accent. Sections: **General** (Author name, Theme: Light/Dark/System), **Color palettes** (see above). Reached from Home gear and from every Style Popover's "Manage palettes in Settings…".

---

## Interactions & behaviour
- Long-press threshold **450 ms**; cancel on pointer up/leave. Context menu suppressed.
- Popover/menu enter animation: `dcpop` 160 ms ease (opacity 0→1, translateY −6→0).
- Toast: bottom-centre pill, 2 s auto-dismiss.
- Keyboard (Drawing/Notes): ⌘Z / ⇧⌘Z undo/redo, tool hotkeys; ignored while a text field is focused.
- Zoom: pinch + toolbar −/+; fit width = (viewport − sidebar) ÷ canvas width.
- Pressure mode "Pressure" varies width by `pts[i][2]`; "Constant" ignores it.
- Eraser removes whole strokes it touches.
- Selecting a comment in Markup scrolls to and highlights linked strokes (`cid`).
- All edits to `docs` are undoable via snapshot; layer opacity slider drags use non-undoable `patch` until release.

## State (top-level)
`screen (home|work|markup|settings) · shelf · curId · pageIdx · tool · sets · setSel · setPop{x,y,edit} · styleTarget (c|f|bg|bc) · weight (const|pressure) · ruler · side · sideOpen · zoom · session (in-progress stroke) · activeLayer · layerMenu · flatten{id|all} · exportOpen · toast · jView (book|calendar) · jSpread · dateMode · calOff · tagFilter/tagQuery/tagDraft · theme · settings{author} · palettes`

## Design tokens
Light:
- accent `#007AFF` · bg `#f2f2f7` · bg2 `#eceaef` · bg3 `#e4e2e8` · card `#ffffff`
- bar `rgba(249,249,251,.94)` + blur 18 · pop `rgba(250,250,252,.97)` + blur 20
- ink1 `#1c1c1e` · ink2 `#3a3a3c` · ink3 `#6d6d72` · ink4 `#8e8e93` · dis `#c7c7cc`
- line `rgba(0,0,0,.08)` · hov `rgba(0,0,0,.05)` · hov2 `rgba(0,0,0,.08)`

Dark:
- bg `#000` · bg2 `#1c1c1e` · bg3 `#2c2c2e` · card `#1c1c1e` · bar `rgba(28,28,30,.94)` · pop `rgba(36,36,38,.97)`
- ink1 `#f2f2f7` · ink2 `#d1d1d6` · ink3 `#a1a1a6` · ink4 `#8e8e93` · dis `#48484a`
- System theme follows appearance.

Avatar colours `AV`: `#007AFF #FF9500 #AF52DE #34C759 #e8483f` (hash of name).

Type: system font (SF Pro). Scale used: 9.5, 11 (section labels, 700, uppercase, +.5 tracking), 11.5, 12, 12.5, 13, 13.5, 14, 15, 18, 20, 21, 22. Weights 500/600/700/800.
Radii: 4 (chips), 6, 7, 8 (segments), 9 (buttons/rows), 10, 14 (popovers), 16 (modals).
Shadows: popover `0 14px 44px rgba(0,0,0,.22)`; modal `0 20px 60px rgba(0,0,0,.3)`; segment pill `0 1px 3px rgba(0,0,0,.14)`; scrim `rgba(0,0,0,.28)`.
Bars: 54px; sidebar 232 (Markup) / 262 (Drawing, Notes); left nav 240 (Home) / 250 (Settings, Library).

## Assets / icons
Icons are **Tabler Icons (outline, MIT)** via the `ti ti-<name>` mapping in `icons.js`. Map to **SF Symbols** in Swift where a match exists; keep custom vector glyphs for: the four pens (upright tip-up nibs), shapes, line/arrows/polyline, bucket fill, text area, radio button (paths in `PDF Annotator.dc.html` → `TOOLS`, 24×24 grid, 1.6 stroke). `Icon Sheet.dc.html` shows every glyph.

## Screenshots (`screenshots/`)
01 Home (Markups shelf) · 02 Markup workspace, Favorites tab + Comments sidebar · 03 Markup Draw tab (toolbar overflow → horizontal scroll) · 04 Tool-presets popover after long-press · 05 Full Style Popover (Markup) · 06 Drawing workspace, Layers sidebar · 07 Layer ⋯ menu open (Veil slider, Rename, Lock, Flatten down) · 08 Flatten dialog · 09 Notes book view, Pages sidebar · 10 Notes calendar view · 11 Notes Tags sidebar · 12 Notes tool presets · 13 Notes Style Popover · 14 Settings General, dark · 15 Settings General, light · 16 Settings Color palettes · 17 Drawing in dark theme with Style Popover.

## Files
- `Redline Studio.dc.html` — Home, Drawing, Notes, Settings/palettes, New-document, Flatten, Export.
- `PDF Annotator.dc.html` — Markup workspace (embedded via `dc-import`), Library, Organize pages, Favorites tray, Stamps, Comments.
- `StylePopover.dc.html` — shared Style Popover.
- `Icon Sheet.dc.html`, `icons.js` — icon inventory and mapping.
- `support.js` — prototype runtime only; ignore.
