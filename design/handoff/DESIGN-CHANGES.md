# Redline — visual refinement change list

Screen/component names match DESIGN-BRIEF.md. Section 5 interaction rules are unchanged. All values pt unless noted. "→" = old → new.

## 0. Tokens (section 6) — updated

Dark (the main change: lift every surface one step; nothing sits on pure black except the canvas well):
- bg `#000` → `#141416`
- bg2 `#1c1c1e` → `#1e1e21`
- bg3 `#2c2c2e` → `#2a2a2e`
- card `#1c1c1e` → `#232326`
- bar `rgba(28,28,30,.94)` → `rgba(30,30,33,.94)`
- pop `rgba(36,36,38,.97)` → `rgba(40,40,44,.97)`
- canvas `#0d0d0f` → `#0f0f11` (only the page well stays near-black, so the paper reads against it)
- line `rgba(255,255,255,.1)` → `rgba(255,255,255,.08)`
- line2 (new, dark) `rgba(255,255,255,.18)`
- hov `rgba(255,255,255,.07)` → `.06`; hov2 `.12` → `.10`
- dis `#48484a` → `#4a4a4f`
- ink3 `#a1a1a6` → `#a3a3a8`

Light: unchanged except `line2` `rgba(0,0,0,.25)` → `.22`.

New tokens (both themes):
- `field` (text-field background): light `#e9e8ee`, dark `#2a2a2e` — replaces the pure-black fields inside dark popups.
- `chipOpen` (status chip): light bg `#FFF1DC` / text `#B25E00`; dark bg `rgba(255,159,10,.16)` / text `#FFB340`.
- `chipResolved`: light bg `#E2F7E8` / text `#1D7A3B`; dark bg `rgba(52,199,89,.16)` / text `#4CD964`.
- Shadow `popover` dark → `0 14 44 rgba(0,0,0,.5)` (light unchanged).
- Sizes: `docTile` 190 → 132; `notebookTile` 150 → 104; `homeNav` 240 (unchanged, now used on Home too); `sidebar` Markups 232 → 260 (equal to Drawings/Notes 262 → 260).

## 1. Home (overview)

Layout becomes a two-column file browser instead of three stacked shelves.

- Page background `bg`. Left column 240 (`bg2`, 1 px `line` on the right); content column fills the rest, padding 28.
- Left column (NavRow, 36 tall, radius 9, text 14/500, icon 18 tinted `ink3`; selected: `hov2` bg, text 14/600 `ink1`, icon `accent`):
  - Title "Redline" 22/heavy at top (y 20, x 20) with settings gear (BarButton 40) right-aligned.
  - SearchField 34 tall, radius 9, `field` bg, inset 12/12 — replaces the 320-wide header search.
  - SectionLabel "MARKUPS" (11/bold, tracking .5, `ink4`, colour `#e8483f` for the 8 pt dot before it) then: Recents, Favorites, On My iPad › Redline as an expandable tree (disclosure chevron 12, indent 16 per level, folder count 11.5/500 `ink4` right-aligned), Browse Files…
  - SectionLabel "DRAWINGS" (dot `#AF52DE`): a flat list of drawings, each NavRow with a 16 × 20 page-stack glyph and name; last row "All drawings ›".
  - SectionLabel "NOTES" (dot `#34C759`): list of notebooks, each NavRow with a 14 × 18 cover swatch (paper colour) and name; last row "All notebooks ›".
  - Max 6 rows per list before "All … ›"; sections scroll together.
- Content column header: breadcrumb 26/heavy (`ink1`; parent crumbs 15/500 `accent`), right side: Recent/Name SegmentControl (radius 9, 32 tall, text 13/600) and the action buttons New Folder · Import PDF (SecondaryButton 36, radius 9, `bg3`, text 14/600 `ink1`) · New PDF (PrimaryButton 36, radius 9, `#e8483f`, white 14/600). The tool-coloured **New** buttons move here; the "+ New" on each shelf is removed.
- Remove: tool shelf cards, 5 pt colour bars, 46 pt icon tiles, one-line descriptions, count pills.
- Grid: FolderTile and DocTile, `LazyVGrid(adaptive min 132, max 148)`, spacing 20 h / 24 v.
- DocTile: thumbnail width 132, height by page aspect (Letter → 171), radius 8, 1 px `line` border, shadow `pill`. Page-count badge removed from the tile face; PDF badge removed. Below: name 13/600 `ink1` (1 line, middle truncation), meta "1 page · 22m ago" 11.5/500 `ink4`. × moves to a long-press/⋯ hover action (16 pt, top-right, `ink3` on `card` circle 24) — hidden by default.
- FolderTile: 132 × 96 area, SF `folder.fill` 44 pt `accent`, no dashed border (dashed is reserved for drop targets/empty states); name 13/600, "0 files" 11.5 `ink4`.
- Compact width (< 900): left column collapses to a location menu button in the header (folder icon + current name, SecondaryButton 36) — same rule as Markups library; Drawings/Notes lists appear in that menu under their SectionLabels.

## 2. Markups library

- Becomes identical to Home content column (Home *is* the library at root). Breadcrumb "Redline › Test": parent 15/500 `accent`, chevron 12 `ink4`, current 26/heavy.
- Drop the 40 pt "‹ Home" row; left column handles navigation. Location menu (compact) unchanged.
- Empty folder: icon `doc.text` 40 pt `ink4`, text 14/500 `ink3`, centred, plus a SecondaryButton "Import PDF" below (gap 14).

## 3. Drawings / Notes libraries
- Same header/grid; tile widths 132 (drawing, page-stack thumbnail 3 layers offset 3 pt each, radius 6) and 104 × 140 (notebook cover, radius 6 left / 10 right, 4 pt spine `rgba(0,0,0,.12)`). Remove "0 layers"/"0 tags" pills from tile faces; move to meta line: "1 page · 0 layers · 23m ago".

## 4. New document sheet
- Sheet width max 560, `bg2`, radius 16. Fields use `field` bg (dark `#2a2a2e`), 40 tall, radius 9.
- Page model preview max height 260 (was ~420) so the sheet fits 11" portrait without scrolling.
- Paper swatch selection ring 2 pt `accent`, radius 8; colour dots 36 with 2 pt ring.

## 5. Workspace — chrome

- Top bar / Tool bar `bar` token (now `rgba(30,30,33,.94)`), 1 px `line` bottom.
- Tab SegmentControl in top bar: 30 tall, radius 8, text 13/600, selected pill `card` with `pill` shadow.
- Selection bar: min width 320, height 40, radius 12, `pop`; items on one line — "1 selected" 13/600 `ink2` · Comment · Delete (13/600 `#FF453A`, icon 15) · × (28 pt hit) — fix the wrapping "Delet/e" by giving the bar `fixedSize(horizontal: true)` and 12 pt gaps.
- ToolButton unchanged (36, radius 9, gap 3, 2 pt ring). Organize Pages active: accent fill with white glyph (as is).

## 6. Annotation popup (open item, section 7)

Shows only the comment and, when opened, the properties. Width 300, radius 14, `pop`, padding 14, shadow `popover`.

Rows top → bottom:
1. Header 24 tall: colour square 12 (radius 3) · kind icon 14 `ink3` · "Callout" 15/600 `ink1` · spacer · status chip (`chipOpen`, 11/700, 22 tall, radius 6, padding 8) · × BarButton 28.
2. Meta 8 below header: AvatarView 20 · author 12.5/600 `ink2` · time 12.5/500 `ink4`.
3. Comment field 12 below: FieldText, `field` bg, radius 9, min 44 tall, text 14/500 `ink1`, placeholder "Add a comment…" `ink4`. **Remove** the separate "Edit text…" row — inline text editing is on the page (brief §1 Inline text editor). No pencil icon.
4. Replies (only if count > 0): each 12.5/500 `ink2`, author 12/600, indent 28, max 3 then "N more replies" 12/600 `accent`. Reply field appears only after tapping "Reply" (12.5/600 `accent` text button in the footer).
5. Footer 12 below, 32 tall: left "Properties" (SecondaryButton 32, radius 8, `bg3`, icon `slider.horizontal.3` 14, text 13/600, chevron 10 rotates 180° when open) · right "Reply" text button · "Delete" moves to the ⋯ in the header? No — keep Delete but as an icon-only BarButton 32 (`trash`, `#FF453A`) at far right. Remove the filled blue "Reply" PrimaryButton.
6. Properties (expanded): 1 px `line` divider, 14 above/below, then the Style editor **without** the presets row (a placed annotation has no presets) and **without** the preview row; spectrum grid 12 × 10 at 20 pt cells (272 wide), Palettes disclosure 40, sliders. Popup max height 560, inner ScrollView; the header stays pinned.

Closed popup height ≈ 172; with Properties ≈ 560.

## 7. Sidebar — Comments

- Width 260, `bg2`, 1 px `line` left, padding 12.
- Segment Comments · Bookmarks · Outline: 30 tall, radius 8, text 13/600, full width. Filter row All · Mine · Others: chips 26 tall, radius 13, 12/600; selected `ink1` bg / `bg` text (dark: `#f2f2f7` on `#141416`) — as is, but 8 below the segment and 12 above the list.
- Comment card → **comment row** (no card border): 1 px `line` separator between rows, `card` bg only when selected (radius 10) with a 2 pt `accent` ring *inside* the row (`.strokeBorder`), not outside, so rows don't shift.
- Row content, padding 10/12:
  - Line 1: colour square 10 (radius 2) · kind icon 13 `ink3` · label 13.5/600 `ink1` · spacer · page "p.1" 11/600 `ink4`.
  - Line 2 (4 below): author + time as one string "You · 12h ago" 12/500 `ink4` · spacer · status chip 18 tall, 10/700, radius 5, `chipOpen` (dim: `rgba(255,159,10,.16)` / `#FFB340`). **Remove AvatarView** from rows (author is already in the string; avatar returns in the popup).
  - Line 3 (only if text): 13/400 `ink2`, 2 lines, 6 below line 2. Reply count "2 replies" 11.5/600 `accent` appended on the same line as the status when > 0.
- Row min height 52 (no text) / 72 (with text). Compact: sidebar floats, same width, shadow `popover`.

## 8. Organize Pages
- Thumbnail width 160 (was ~410 on 13"), grid adaptive min 160, spacing 24; page label 12/600 `ink3`. Action pill (rotate/duplicate/delete) 36 tall, radius 10, `pop`, appears below the selected page not over it. "Blank Page" is a tile of the same size with a 1.5 pt dashed `line2` border, radius 8, `plus` 22 `accent`, label 12/600.

## 9. Drawings — Layers sidebar
- Width 260. "Add layer" as a full-width SecondaryButton 36 (solid `bg3`, no dash). Layer row 56 tall: thumbnail 48 × 34 (radius 5, `card`, 1 px `line`), name 14/600, eye 18 `ink3`, ⋯ 18 `ink3`; selected: `card` bg, 2 pt `accent` inner ring. Helper copy 12/400 `ink4`, 12 below the list.

## 10. Notes
- Pages sidebar rows 64 tall: thumbnail 40 × 52 radius 4; name 14/600, meta 12/500 `ink4`; × only on swipe/long-press. Selected: `card` bg + inner ring (replaces the blue-tinted fill `#0f2440`-ish shown today). "Add page" SecondaryButton 36, solid.
- Book view header "COVER · SEP 30, 2026" stays 11/700 tracking .5 `ink4`; Tag chip 26 tall, 1 pt `line2` border, radius 13 (solid, not dashed).
- Calendar: day cell `card` bg (`#232326`), 1 px `line`, radius 10; today ring 2 pt `accent` inner; day number 13/600 `ink2`, today `accent`. Mini page thumbnails 28 × 36 radius 3. Row height ≤ 150 so 6 rows fit 1024 without scrolling.

## 11. Settings — Color palettes
- Background `bg` (`#141416`), nav 250 `bg2` with 1 px `line`. Palette row `card` bg radius 12, 1 px `line`; selected 2 pt `accent` inner ring; swatches 28 radius 6 gap 4. Badges DEFAULT/BUILT IN 10/700 tracking .3, 20 tall, radius 5 (`accent` at 16 % / `accent`; `bg3` / `ink3`). Editor swatches 44 radius 10 gap 10 (unchanged).

## 12. Presets dropdown / Style editor (unchanged sizes; dark tokens only)
- Card bg `pop`; sliders track `bg3`, thumb 26 white with `pill` shadow; SectionLabel `ink4`. Weight segment: allow 4 equal columns with 12/600 to stop "Semibol/d" wrapping — set `minimumScaleFactor(.85)` and `lineLimit(1)`.

## Open items still to design (unchanged from §7)
Ruler/handles/badge/leader look; empty states beyond the folder case above; app icon/launch screen.
