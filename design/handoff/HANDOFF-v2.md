# Redline — handoff v2 (visual refinement + Markup chrome)

Companion to `DESIGN-CHANGES.md` (exact pt/hex values per screen). This file lists what changed since the app screenshots you sent, in the order to implement. Screen/component names match `DESIGN-BRIEF.md`. Section 5 interaction rules are unchanged unless marked **(rule clarified)**.

Reference prototype: `Redline Studio.dc.html` (open in a browser; long-press a tool, tap a comment, etc.). Shared editor: `StylePopover.dc.html`. `PDF Annotator.dc.html` is retired — everything now lives in Redline Studio.

---

## 1. Tokens

Dark (final values — replace those in DESIGN-CHANGES.md §0):
- bg `#1c1c1f`
- bg2 `#232327`
- bg3 `#2f2f34`
- card `#2a2a2e`
- bar `rgba(35,35,39,.94)`
- pop `rgba(46,46,51,.97)`
- canvas `#121214` (page well only)
- field `#2f2f34`
- line `rgba(255,255,255,.08)`, line2 `rgba(255,255,255,.18)`
- hov `rgba(255,255,255,.06)`, hov2 `rgba(255,255,255,.10)`
- ink3 `#a3a3a8`, dis `#4a4a4f`

Light: unchanged; add `field #e9e8ee`.

New (both): `chipOpen` bg/fg — light `#FFF1DC / #B25E00`, dark `rgba(255,159,10,.16) / #FFB340`. `chipResolved` — light `#E2F7E8 / #1D7A3B`, dark `rgba(52,199,89,.16) / #4CD964`.

## 2. Home ("Recents")

Two-column. Left `NavColumn` 240 pt, `bg2`, 1 px `line` right, padding 18/12. Right pane padding 28.

NavColumn, top → bottom:
- Row 40: "Redline" 22/heavy + Settings gear (BarButton 40, `ink3`) right.
- SearchField 34 tall, radius 9, `field`, margin 10 top / 14 bottom.
- SectionLabel "MARKUPS" (11/bold, tracking .5, `ink4`, 8 pt dot `#e8483f`): NavRows Recents (`clock`), Favorites (`star`), On My iPad (`ipad`), ↳ Redline (`folder`, indent 26, count right 11.5/500 `ink4`), Browse Files… (`folder.badge.plus`).
- Blank 14 pt, then two **tool rows** (no section label): "Drawings" (dot `#AF52DE`) and "Notes" (dot `#34C759`). Each: 8 pt dot · label 14/500 · count 11.5 `ink4` · 28 pt chevron button. Tap row → gallery; tap chevron → row expands (chevron rotates 90°) to list up to 6 most-recent docs indented 26, each 36 tall (drawings: `square.stack` 18 pt glyph; notebooks: 14 × 18 cover swatch in paper colour). No "All…" rows.
- NavRow: 36 tall, radius 9, 14/500 `ink2`; selected `hov2` bg, 14/600 `ink1`, glyph `accent`.

Right pane, `shelf == home`:
- Title "Recents" 26/heavy. **No** sort control, New Folder, Import PDF or New PDF here.
- Three **rails** in a column, each: header (8 pt dot · label 15/700 · spacer · "New" SecondaryButton 30 tall radius 8 `bg3` 13/600 · "See all ›" 13/600 `accent`), then a horizontal scroll of up to 8 DocTiles (gap 20). Rails: Recent markups (`#e8483f`), Recent drawings (`#AF52DE`), Recent notebooks (`#34C759`). Padding 24 top / 28 bottom, 1 px `line` under **every** rail. Empty rail shows a 132 × 100 dashed tile "No … yet" that opens the New sheet.
- "See all" → that tool's library; "New" → New document sheet pre-set to the tool.

## 3. Markups library (folder view)
Breadcrumb "On My iPad › **Redline**" (parent 15/500 `accent`, chevron 12 `ink4`, current 26/heavy). Header right: Recent | Name SegmentControl (32 tall radius 9 13/600) · New Folder · Import PDF (SecondaryButton 36) · New PDF (PrimaryButton 36 `#e8483f`). Grid `adaptive(min 132, max 148)`, spacing 20 h / 24 v. Empty state: `doc.text` 40 `ink4`, copy 14/500 `ink3`.

DocTile 132 wide; page aspect (Letter .77); radius 8; 1 px `line`; shadow `pill`. No PDF / count badges on the face. Name 13/600 (1 line), meta 11.5/500 `ink4`. Delete × 24 pt hidden until hover/long-press. Notebook tile 104 × 140, 4 pt spine `rgba(0,0,0,.12)`, title on cover 12/700.

## 4. Markup workspace — chrome (all tabs and buttons kept)
- Top bar tab segment centred: ★ · Draw · Anno · Edit · Form · + — 30 tall, radius 9, 13/600, selected pill `card` + `pill` shadow.
- Tool bar order: **Organize Pages** (44) · Select · divider · tab tools · divider · Ruler. Draw tab tools: Rollerball, Fineliner, Marker, Highlighter, Eraser — **Pen (felt tip) removed from Markup**: PDF ink annotations are constant-width. Anno: Text, Rect, Ellipse, Highlighter, Revision cloud, Arrow, Stamp. Edit: Crop, Redact, Insert image, Link (stubs). Form: field types. ★: pinned set + "+".
- Sidebar segments: Comments · Bookmarks · Outline; a fourth "Forms" segment only while the Form tab is active. Bookmarks panel: "Bookmark this page" SecondaryButton 36 then rows 44 (`bookmark.fill` `accent`, "Page n", p.n). Outline: page rows 44.
- Selection bar 40 tall radius 12 `pop`, `fixedSize(horizontal: true)`, items "1 selected" · Comment · Delete · × on one line, gaps 12.
- Organize Pages: 160 pt thumbnails, action pill below selected page, "Blank Page" dashed tile.

## 5. Presets & Style editor **(rule clarified)**
- Tapping a tool that has presets **selects it and immediately shows its preset popover** (4 × 30 pt circles, 176 wide, anchored under the tool). Tapping the already-active tool deselects it (unchanged). Long-press also opens presets (unchanged). Tapping the selected preset toggles the full StylePopover in the same anchor. Presets are **never** shown inline in the toolbar.
- Constant / Pressure ("Line weight" segment) appears **only for the Pen (felt tip)** — Drawing and Notes only. Rollerball, Fineliner, Marker, Highlighter, shapes and text have no pressure option.
- StylePopover gains an `embedded` mode: no card background/shadow/border, no presets row, no Preview row. Everything else identical (colour header, 12 × 10 spectrum, Palettes disclosure, thickness, opacity, Border/Fill or Text/Border/Fill segments, fill pattern, border style).

## 6. Annotation popup (open annotation)
Width 300, radius 14, `pop`, padding 14, gap 12, max height 560 (inner scroll).
1. Header 24: colour square 12 r3 · kind glyph 14 `ink3` · kind 15/600 · status chip (22 tall, 11/700, r6, `chipOpen`) · × 28.
2. Author line: AvatarView 20 · author 12.5/600 `ink2` · time 12.5/500 `ink4`.
3. Comment field: `field` bg, r9, min 44, 14/500, placeholder "Add a comment…". No "Edit text…" row, no pencil.
4. Replies (if any): indent 28, author 12/600 + time 11 `ink4`, text 12.5/500 `ink2`.
5. Reply field (36, `field`) appears only after tapping "Reply".
6. Footer 32: "Properties ⌄" SecondaryButton (r8 `bg3` 13/600, `slider.horizontal.3` 14, chevron rotates 180° when open) · spacer · "Reply" 12.5/600 `accent` text · trash BarButton 32 `#FF453A`. No filled blue buttons.
7. Properties open: 1 px `line` divider + 14, then **StylePopover embedded**, bound to the annotation's strokes (colour, thickness, opacity, fill/border for shapes, text/border/fill for text). No pressure row.

## 7. Comment badge on the page
Every annotation with text or ≥1 reply gets a 20 pt badge anchored **4 pt above the topmost point of its ink** (not the bounding box). Glyph: SF `text.bubble` (Tabler `bubble-text`) drawn as fill + stroke: stroke = annotation colour mixed 28 % toward white, fill = colour mixed 72 % toward white, stroke 2 pt, `drop-shadow(0 1 2 rgba(0,0,0,.3))`. Tap → select annotation + open popup + show Comments sidebar. Annotations without text show nothing.

## 8. Sidebar — Comments
Width 260, `bg2`, padding 12. Segment 30 tall; filter chips 26 tall (selected `ink1` on `bg`).
Rows (not cards): padding 10/12, gap 4, min 52, 1 px `line` bottom, `card` bg + 2 pt `accent` **inner** ring only when selected.
- Line 1: colour square 10 r2 · glyph 13 `ink3` · label 13.5/600 · spacer · "p.n" 11/600 `ink4`.
- Line 2: "You · 12h ago" 12/500 `ink4` (no avatar) · spacer · "2 replies" 11.5/600 `accent` (if any) · status chip 18 tall 10/700 r5 `chipOpen`.
- Collapsed: text 13/400 `ink2`, 2-line clamp.
- **Expanded (tap)**: full text 13/400 `ink1`, wraps, no clamp, no scroll, **not in edit mode**. Below: "Edit" (or "Add text") and "Delete" 12/600 links; replies list; Reply field + button. Tapping Edit swaps the text for a `field` textarea (13, r9) that commits on blur. Tapping the row again collapses it.

## 9. Left for later (unchanged from brief §7)
Measure tools, Edit-tab actions, PDF import, ruler/handles look, app icon.
