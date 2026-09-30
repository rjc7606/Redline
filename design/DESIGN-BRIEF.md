# Redline — design brief for refinement

Redline is an iPad app (iPadOS 17+, SwiftUI) with three tools that share one toolbar, style system and
colour palettes: **Markups** (PDF annotation, PDFKit-native), **Drawings** (layered plan sheets) and
**Notes** (paged notebooks). This brief describes what exists today so a refined design can be handed
back and implemented directly. Please keep the screen, overlay and component names used here; the
implementation maps to them one-to-one.

## What we need back

1. A change list per screen: "Home › Tool shelf: header becomes …; New button moves to …". Exact values
   in points, hex colours, font sizes and weights. "Slightly larger" can't be implemented.
2. Updated tokens (section 6) if they change. Every token is a one-place edit in code.
3. Mockups or HTML prototypes per screen, iPad Pro 13" landscape (1366 × 1024 pt) and 11" portrait
   (834 × 1194 pt). Compact width (< 900 pt) matters: Split View and Slide Over are supported.
4. Leave the interaction rules in section 5 as they are unless a rule is listed as open (section 7).

## 1. Screens

### Home (overview)
- Title "Redline" 30/heavy, global search field (max width 320), settings gear.
- Three stacked **tool shelves**, one per tool, each a card (radius 18, 1 px `line` border, 5 pt colour
  bar on the left in the tool colour). Header: 46 pt tinted icon tile (radius 12, tint at 14 %), name
  22/bold, count pill, one-line description 12.5, tool-coloured **New** button (36 pt, radius 9).
- Under the header: a horizontal rail of recent documents (tiles 190 wide; notebooks 150) ending in a
  "See all N" card; empty tools show a dashed "Create your first …" card.
- Tool colours: Markups `#e8483f`, Drawings `#AF52DE`, Notes `#34C759`.

### Markups library (tap a shelf title / See all)
- Left column 240 pt: back to Home, tool icon + "Markups", **Recents**, **Favorites**, **On My iPad ›
  Redline** as an expandable folder tree (nested folders, counts), **Locations › Browse Files…** (opens the
  system picker: iCloud Drive, OneDrive, Dropbox…), Settings at the bottom.
- Content: breadcrumb (26/heavy for the current level), search, Recent/Name segment, buttons New Folder ·
  Import PDF · New PDF (tool colour), then folder tiles and document tiles (grid, min 170).
- Document tile: first page rendered with its annotations at the page's real aspect ratio, name
  13.5/semibold, "N pages · 2h ago" 11.5, folder path in Recents/Favorites/search, star for favourites,
  × on the tile. Long-press: Add to Favorites, Move to, Rename, Open, Delete.
- Compact width: the column collapses into a location menu in the header.

### Drawings / Notes libraries
- Same header as above (back, icon, title, search, sort, New) and a simple grid of tiles. No folders yet.

### New document sheet (modal, max 560 wide)
- Name field 40 pt. Markup: "Import a PDF" dashed drop zone, or "create a new PDF" with a live page model
  (paper: Blank/Dot/Grid/Lined; colour: white `#ffffff`, cream `#f7f0dc`, grey `#e6e6ea`, blue
  `#dfe9f5`; Portrait/Landscape). Notes: template + paper pickers. Cancel / Create.

### Workspace (all three tools)
- **Top bar** 54 pt (`bar` material): back "‹ Markups", document name 13/bold, mode chip (uppercase 10/heavy),
  centre content (Markups: tab segment; Notes: Pages/Calendar segment + one/two-page toggle), then undo,
  redo, zoom −/+, ruler, share, divider, sidebar toggle (all 40 pt buttons, 44 pt hit areas).
- **Tool bar** 54 pt. Markups: Organize Pages button, **Select** (pinned), divider, then the tools of the
  active tab in a horizontally scrolling strip; on a Favorites tab a "+" opens the Favorites tray.
  Drawings/Notes: Select, Pen, Fineliner, Felt tip, Marker, (Highlighter in Notes), Eraser, Text,
  Rectangle, Ellipse, status hint on the right.
- Tool buttons 36 × 36 (44 hit), radius 9, gap 3. Active: `hov2` background with a 2 pt ring in the
  preset colour, or accent fill with white glyph for tools without colour. The glyph tints to the active
  preset colour (falls back to `ink1` when unreadable: luminance > .9 light / < .22 dark).
- **Presets dropdown**: while a tool with presets is active, its four presets (30 pt circles, gap 12) stay
  visible in a card under the button (radius 14, popover shadow). Tap = use; tap the selected one again =
  expand into the **Style editor** (250 wide + 14 padding, max height 560, scrolls).
- **Style editor** sections, top to bottom, only those relevant: presets row; target segment (shapes:
  Border/Fill; text: Text/Font/Border/Fill); colour header + 12 × 10 spectrum grid (greys row, then hues
  light → dark); Palettes disclosure card (40 pt row, dot preview, chevron; expanded: each palette as a
  12-column swatch grid, "Manage palettes in Settings…"); Font tab: font button (system font picker),
  weight segment Regular/Medium/Semibold/Bold; fill pattern (None/Solid/Hatch/Cross/Dots); thickness
  slider with value in pt; border size; line style Solid/Dashed/Dotted; opacity; preview row.
- **Canvas** (Markups): PDFKit page view, continuous vertical, 24 pt page gap, rubber-band on all sides,
  pinch zoom. Selection = 2 pt accent outline, resize handle (22 pt white circle, accent ring) at the
  bottom-right, callout tip/elbow handles, comment badge (18 pt accent circle with three dots at the
  annotation's top-right, only when it has text or replies), on-page ruler (820 × 72 page units, ticks,
  rotate handles, centre pill "12° Lock").
- **Selection bar** (top centre): "N selected", Comment (single selection only), Delete, ×.
- **Annotation popup** (300 wide, radius 14): kind + colour swatch, status menu, author/time, comment
  field, replies, reply field, Done / Properties / Delete. Properties expands the Style editor for the
  selected annotation.
- **Inline text editor**: text boxes and callouts are typed directly on the page in a field styled like
  the box (fill, border colour, corner radius 6, chosen font).
- **Sidebar** (right, 232 pt Markups / 262 pt Drawings & Notes, `bg2`): segment Comments · Bookmarks ·
  Outline (Markups), Layers · Pages (Drawings), Pages · Tags (Notes). Comment card: colour square, kind
  icon, label, page, avatar + author + time, status chip, text (2 lines), reply count. Starts closed;
  floats over the canvas at compact width.
- **Organize Pages** (full-canvas overlay): grid of page thumbnails with rotate/duplicate/delete,
  drag to reorder, "Blank Page" tile, Done.
- **Favorites tray** (600 wide) and **Stamp gallery** (296 wide, 2 columns, rotated −2°).
- **Export menu** (300 wide, top-right): Share PDF, Share flattened PDF, Image of this page, Save
  flattened to Files.

### Notes workspace
- Book view: single page or facing spread, tag rows above pages ("Page 3 · Aug 14 · tag chips · + Tag"),
  round prev/next buttons, bottom pill "3 · 12 pages · swipe to flip". Ghost page "Tap to add a page".
- Calendar view: month grid 7 × 6, Created/Modified segment, mini page thumbnails per day, today ringed.

### Settings (full screen, left nav 250)
- General: name on comments, Appearance (System/Light/Dark), Finger drawing (Auto/Always/Never),
  Markup sheets (White/Blueprint). Color palettes: list (built-in + custom) and editor (swatches 44 pt,
  hex field, 12 × 10 spectrum, Make default, duplicate, delete).

## 2. Components (names used in code)
SegmentControl (radius 9/8, selected pill `card` with shadow), BarButton, PrimaryButton, SecondaryButton,
SectionLabel (11/bold uppercase, tracking .5, `ink4`), PopoverCard, NavRow, ToastView (bottom-centre pill,
2 s), SliderRow, AvatarView (initials on a hashed colour), FieldText, SearchField, ColorGrid, PalettesDisclosure,
PatternSwatch, DocTile, FolderTile, ToolButton, PresetsRow, StylePopoverView, AnnotationPopup, FieldInspector.

## 3. Icons
SF Symbols everywhere, plus custom 24-grid outline glyphs (2 px stroke, round caps) for: Fineliner, Felt
tip, Marker, Pen, Sticky note (sticker with folded corner), Callout (text box with an arrow out of the
lower-left corner), Bucket fill, Text area field, Radio field, Rectangle, Ellipse, Polygon, Revision cloud,
Line, Double arrow, Polyline. Shape glyphs show the preset's fill through the closed path.

## 4. Type
System font (SF Pro). Sizes in use: 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 15, 17, 18, 20, 21,
22, 26, 30. Weights 500/600/700/800. Text annotations may use any font on the device.

## 5. Interaction rules (settled — please keep)
- Finger with no tool: pans (any direction, rubber-band). Two fingers pan and pinch.
- After a pen tool is picked, whichever touches first decides: finger first → fingers may ink; Pencil
  first → fingers pan. Every non-ink tool works with a finger; a moving finger with a tap tool pans and
  only a clean lift places (stamp, note, text, field, fill).
- Tap the active tool again = deselect (no tool). Presets stay visible while the tool is active.
- Pencil double-tap toggles eraser ↔ previous pen (follows the system setting).
- Select: tap selects (a mark selects its whole comment group), diagonal drag = box, curving drag = lasso;
  dragging a selected item moves it. With no tool, a clean tap also selects.
- Popup opens only on request (Comment button, badge tap, or placing a sticky note).
- Same-style pen strokes join one annotation; a new colour becomes a grouped annotation (one comment).
- Eraser cuts only ink; four preset sizes. Highlighter/underline/strike/squiggly attach to PDF text only.
- Only fingers move the ruler; Pencil strokes started beside it follow its edge; Lock snaps every stroke.
- Sidebar starts closed; opening it rescales pages to keep the same fill of the view.

## 6. Tokens (current — "warm paper" handoff applied 2026-09-30)
Light: accent `#2F6FE4`, bg `#f4f1ea`, bg2 `#ece8df`, bg3 `#e2ddd2`, card `#fbf9f4`, field `#eae6dc`, bar
`rgba(244,241,234,.94)`, pop `rgba(251,249,244,.97)`, canvas `#d9d4c8`, ink1 `#2a2622`, ink2 `#4a443d`,
ink3 `#7a736a`, ink4 `#968e84`, dis `#cfc9be`, line `rgba(60,45,30,.10)`, line2 `.22`, hov `.05`, hov2 `.09`,
chipOpen `#FBEBD3 / #9A5A12`. Paper grain: 160 pt noise tile, multiply 4 %, on bg and the canvas well only.
Dark (neutral): accent `#6C96E0`, bg `#1f1f22`, bg2 `#26262a`, bg3 `#323236`, card `#2b2b2f`, field `#323236`,
bar `rgba(38,38,42,.94)`, pop `rgba(48,48,53,.97)`, canvas `#151517`, ink1 `#ecebe8`, ink2 `#cfcecb`, ink3 `#a09f9c`,
ink4 `#84837f`, dis `#4b4b4f`, line `rgba(255,255,255,.08)`, line2 `.16`, hov `.06`, hov2 `.10`,
chipOpen `rgba(230,170,90,.16) / #E4B276`. No grain.
Identity (both): Markups `#C4554A`, Drawings `#8B6BB1`, Notes `#5B9A6B`; destructive `#C4554A`; status Accepted
`#5B9A6B` on 16 %, Rejected destructive on 14 %, Completed ink4 on hov2. Default red preset is true red `#E0332A`.
Type: titles and section labels SF Pro Rounded (title 26/700, app name 22/700, SectionLabel 11/600 tracking .4);
body SF Pro; no weight above 700; tile names and row labels 500; rail headers 600; chips 11/600; counts monospaced digits.
Radii: popovers/sheets 16, rows/buttons/fields 10, tiles 8, chips 6.
Shadows: page `0 1 2 rgba(40,30,20,.12) + 0 8 24 .10` (dark `.4/.35` black); popover `0 2 6 .08 + 0 16 40 .16`;
pill `0 1 3 rgba(0,0,0,.14)`.
Bars 54; sidebar 260 (all tools); NavColumn 240; Settings nav 250; popover 250; presets 176; modal 560;
compact threshold 900; DocTile 132 wide (page aspect); notebook tile 104 × 140; Organize Pages thumbs 160.
Notebook covers: composition-book style (marbled speckle over a cover colour from a 16-colour palette, dark spine,
white label plate with the name); the cover is a drawable page and its render is the thumbnail.
Default presets: pens `#1c1c1e #E0332A #007AFF #34C759`; marker/highlighter `#ffd60a #ff6fa8 #34C759
#007AFF`; fill/sticky note `#FFCC00 #FF3B30 #007AFF #34C759`; others `#E0332A #1c1c1e #007AFF #FF9500`.
Text box presets (text = border / fill): `#FF3B30`/white, `#1c1c1e`/`#FFF9C4`, `#007AFF`/white,
white/`#1c1c1e`; border 1.5 pt, shapes fill at 50 %. Widths: Pen 1–12, Fineliner .5–6, Felt 2–20,
Marker 6–40, Highlighter 10–40, shapes 1–16, text 1–14 (size = 10 + value pt), eraser 6/12/24/40.

## 7. Open for design
- The look of the on-page ruler, selection handles, comment badge and callout leader.
- Annotation popup layout and the Properties editor inside it.
- Empty states (empty shelf, empty folder, no annotations).
- Dark theme of the canvas chrome (popups, pills).
- Icons for Drawings and Notes shelves, app icon, launch screen.

## Screenshots to capture on the iPad (landscape unless noted)
Home overview · Markups library (folder with subfolders) · New PDF sheet · Markup workspace with a
Favorites tab and the presets dropdown open · Style editor expanded (pen) and (text box, Font tab) ·
Annotation popup with Properties open · Sidebar Comments · Organize Pages · Drawing workspace with Layers
· Notes book view (spread) · Notes calendar · Settings palettes · Home in 11" portrait · Markup in Split View.
