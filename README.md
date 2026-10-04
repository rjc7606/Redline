# Redline

iPad markup, drawing and notes app (SwiftUI, iPadOS 17+). Three document types share one
annotation engine, one toolbar behaviour, one Style Popover and one set of colour palettes:

- **Markups** — PDF annotation: Favorites / Draw / Annotate / Edit / Forms tabs, comments with
  authors, status and replies, form fields, organize pages. Import a PDF from Files (or open one
  with "Open in Redline"), or create a new PDF on blank, dot, grid or lined paper in four page colours.
  Home is a two-column file browser: the left column lists Markups (Recents, Favorites, the On My iPad ›
  Redline folder tree, Browse Files… for iCloud Drive, OneDrive, Dropbox and other Files providers) plus
  Drawings and Notes rows that expand to recent documents; the right pane shows Recents rails, a folder, or a gallery.
  PDFs picked in Files (or sent with "Open in Redline") open in place: nothing is copied, edits are written back
  where the file lives, and removing the markup from the library never deletes the file. If another app saves the
  file, Redline reloads it (while open, and when the app returns to the foreground; thumbnails refresh too) unless
  Redline has unsaved edits of its own. Replies and review states are invisible in every reader (hair-sized rects
  with a blank appearance); only the on-screen badge shows that a mark has a comment.
- **Drawings** — layered plan sets: a Base layer plus trace layers with a white "veil", lock/hide,
  flatten down / flatten all.
- **Notes** — paged notebooks: paper colours, templates, tags, single page or facing spread, and a
  calendar view.

## Layout

| Path | What |
| --- | --- |
| `Redline/` | Swift package `RedlineCore`: models, tool catalogue, style presets, palettes, stroke geometry, undo history, document operations, journal geometry, seed data, layout/theme tokens. No UI imports, so it builds and tests on any platform (`cd Redline && swift test`). |
| `App/` | The SwiftUI app: home browser, workspaces, canvas with Apple Pencil input, style popover, sidebars, settings, PDF export. Built only on macOS/CI. |
| `design/` | `DESIGN-BRIEF.md` (what exists, tokens, settled interaction rules) and `handoff/` (the Claude Design return: change list, prototypes, screenshots). |
| `project.yml` | XcodeGen spec. CI runs `xcodegen generate` to produce `Redline.xcodeproj`. |
| `.github/workflows/build-ipa.yml` | Runs the core tests, then builds an unsigned IPA on every push to `main`. |

## Building locally

```sh
brew install xcodegen
xcodegen generate
open Redline.xcodeproj
```

The core package alone:

```sh
cd Redline
swift build
swift test
```

## Notes

- Every design value (bar heights, sidebar widths, radii, colour tokens, default pen widths and
  preset colours) lives in `RedlineCore` (`Metrics`, `ThemeTokens`, `ToolStyles`) so the app and
  tests share one source of truth.
- Documents, settings, palettes and presets are saved as JSON in the app's Application Support
  directory. Imported PDFs are copied into `Documents/PDFs` and "Save to Files" exports go to
  `Documents/Exports`, both visible in the Files app under On My iPad › Redline. PDFs can also be
  opened from Files or the share sheet ("Open in Redline").
- The markup viewer is Redline's own (`PDFStackView`): a scroll view stacking the pages, page content rendered by
  PDFKit into tiles, annotations drawn per page on the main thread so edits show instantly. PDFKit still parses the
  file, renders page content, extracts text and reads / writes the annotation layer; it no longer owns scrolling,
  zooming, bounce or gestures.
- Markups are real PDFs edited through PDFKit: every tool creates a standard PDF annotation (Ink, Highlight /
  Underline / StrikeOut / Squiggly with text quads, Square, Circle, Line, FreeText, Text notes, Widgets), with author,
  date, contents, replies (`IRT`) and review state, so the file opens with its marks in any PDF app. Existing
  annotations keep their appearance until edited. New PDFs are generated on the chosen paper.
- On PDF pages the highlighter, underline, strikethrough and squiggly tools snap to the page's text
  lines (PDFKit selection); pages without text fall back to a freehand band.
- The Pen responds to Apple Pencil pressure in Drawings and Notes; Markups use Fineliner, Felt tip and Marker
  (constant-width PDF Ink annotations).
- With no tool selected a finger moves the page in any direction (two fingers pan and pinch to zoom). After a pen is picked, the first touch decides: a finger first lets fingers ink; the Pencil
  first makes fingers pan. Every other tool works with a finger; with a tap tool (stamp, note, text, field,
  fill) a finger that moves pans instead, and the tap only fires on a clean lift. Settings › Finger drawing overrides this
  (Auto / Always / Never). Only fingers move or rotate the ruler; Pencil touches over it draw.
  The Select tool (pinned beside Organize Pages) selects with a tap, a diagonal box drag, or a lasso.
- Text boxes, callouts and stamps have their own look (rounded corners, any installed font, real border colour).
  It is drawn on screen by a PDFAnnotation subclass and written into the PDF as an appearance stream (a form
  XObject with the font embedded) through a small incremental-update writer, so every reader shows it identically.
  Nothing is rewritten when a document loads: every annotation renders from the appearance stream the file carries,
  and Redline only takes over drawing one of its own annotations once you select and edit it. Moving an annotation
  or editing its comment keeps its appearance stream; it is regenerated only when the rendering has to change
  (restyle, resize, text on the page), and undo puts the original stream back.
- Edits save themselves: PDF changes are written shortly after each edit, and everything pending is flushed when
  you switch tabs, go Home, close a tab, or the app leaves the foreground.
- Text on the page (text boxes, callouts, stamps) defaults to Source Sans 3, bundled in `App/Fonts` under the SIL
  Open Font License so a future Windows build can ship the same file; any installed font can replace it.
- Text boxes and callouts have a Font tab with Redline's own font list (every family on the device, including
  bundled and user-installed ones, each name set in its own face); the Weight segment picks the face, plus size and
  colour. A new text box starts empty-sized and grows as you type; tapping
  outside closes it. Once selected, its bottom-right handle sets the box's width and height while the text keeps
  its size and rewraps. Placing a sticky note (drawn as the sticker glyph, with its own appearance stream) opens
  its comment for typing.
- With a finger, a clean tap on any annotation selects it whatever tool is active, and dragging a selected
  annotation moves it instead of panning.
- Selecting an annotation shows a bar beside it (N selected · Comment · Properties · Delete · ×). Properties drops
  the style editor under the bar and restyles the selection itself; Comment (or a badge tap, or placing a sticky
  note) opens the comment popup: text, status, replies (the reply field appears after tapping Reply).
- Pen and marker ink, and highlights, underlines, strikeouts and squiggles, are drawn by Redline at their real
  opacity (PDFKit paints them solid, and doubles up where strokes overlap); an annotation's strokes are composited
  in one layer so joins and overlaps stay even, markers multiply over the page, and the look is written as the
  appearance stream (rebuilt only for annotations changed since the last save). They are anchored to the
  page text: selectable and restylable, never moved or resized. Annotations with comment text or replies show a speech-bubble
  badge in their own colour just above the ink; tapping it opens the popup. Sidebar rows expand in place to show the
  full text, Edit / Delete and replies.
- Several documents can be open at once: a tabs row under the tool bar lists them (tap to switch, × to close).
  They stay open across Home until closed, and opening from anywhere adds a tab. Each open document keeps its
  tool, page, zoom and undo history while open.
- Snapping (on by default; tool bar button or Settings): everything except pens snaps while being placed, drawn,
  moved or resized — edges and centres align with other annotations and the page (dashed guide), edges touch
  (solid guide), and gaps match a neighbouring pair's spacing (bracketed guides).
- Outside the Forms tab, form fields are used, not selected: tap to flip a checkbox or toggle, pick a radio (its
  group clears), fill a text / date / signature field in place, or choose from a dropdown. The Forms tab edits them.
- Form fields have their own look (tinted rounded boxes with placeholder names, real check / radio / switch
  glyphs, a signature line); text-type fields also carry that look as an appearance stream, and the same tint and
  border go into the field's /MK colours for readers that draw fields themselves.
- Markup and drawing pages stack in a native vertical scroll: free panning in any direction with rubber-band
  bounce along any axis where the content is larger than the view (a page that fits stays put), finger pinch-zoom; the Pencil
  never scrolls. Zoomed-out pages are centred with the larger margins that leaves.
- PDF pages render on a background queue; a neutral placeholder shows until each page image is ready.
- Organize Pages: drag a tile (press, then move) and the others slide aside to show where it will land;
  bookmarked pages carry a bookmark badge. The Outline tab edits the PDF's own outline (nothing is added
  automatically): Add puts a level-1 entry for the current page at the end, names edit in place, Reorder turns on
  drag handles with a live preview, and the long-press menu nests (child / indent / outdent), re-points and deletes.
- The eraser cuts only the touched part out of pen ink (shapes, arrows, clouds and leaders stay whole) and shows
  its outline while erasing; its four presets are sizes. One eraser drag is one undo step, however many strokes it
  cut or removed. Double-tap-to-zoom is off on the PDF (pinch zooms), so quick Pencil taps never zoom.
- Select taps a single stroke: one stroke of a multi-stroke pen annotation is pulled out into its own annotation
  and selected alone, so it can be moved by itself; the lasso does the same for the strokes it encloses.
- Lines and arrows stay standard Line annotations but are drawn with round caps and joins on screen and in their
  appearance stream. Solid, dashed and dotted apply to pens, lines, arrows, rectangles, ellipses and clouds (dots
  are round-capped tiny dashes, so other readers draw them too). A cloud's border can be arcs or straight; an
  unfilled rectangle or ellipse is selected on its border only, so what's inside stays selectable. The bucket fills rectangles and ellipses directly, and fills clouds, closed polylines and pen
  loops with a fill polygon grouped under the outline (moves, resizes and deletes with it; never text boxes, stamps
  or notes). Properties in the popup, or the comment's long-press menu, can remove a fill.
- Bucket fill works on shape-tool shapes and on pen strokes that close on themselves. Double-tapping an Apple Pencil switches
  to the eraser and back (it follows the system Pencil "Double Tap" setting).
- Stamps come in two sections: static (APPROVED, ✓, ✗ …) and dynamic ({date}, {time}, {author}, {initials}
  filled in when placed). You can create either kind in the gallery and long-press a stamp to pin it to a
  Favorites tab. Stamps sit at the same -2° tilt as their preview, on screen and in the appearance stream.
- Cloud, arrow and callout previews show the real shape while dragging (the callout shows its arrow, leader and
  empty box). A callout's elbow sits on the midpoint of whichever side of the box faces the arrow tip and only slides
  straight out from that side; drag it past the box to put it on another side. Dragging the box moves the box alone
  with the tip fixed (a side you chose is kept while the tip is still out on that side, otherwise the elbow faces the
  tip), dragging the leader moves the whole callout, and the tip handle re-aims the arrow. Polylines are placed point by point: tap to add a vertex, tap the last one to finish, tap the first
  to close.
- Measure tools: Distance (drag; ticks and the live length), Perimeter and Area (tap the corners; running
  totals), each committed with a grouped label that moves with it, and Calibrate (drag along a known length, enter
  what it is in feet, inches, metres or millimetres) which sets the document's scale; uncalibrated documents measure
  in the sheet's own inches. Find (magnifier in the top bar) searches the PDF text and highlights every hit.
- Copy, paste and duplicate annotations (selection bar menu, Paste in the tool bar, ⌘C ⌘V ⌘D): groups such as
  callouts, filled outlines and measurements stay grouped; pastes land centred in view on the current page of
  whichever document is open.
- Insert image (Edit tab): a photo from the library or an image file from Files, placed with a tap, resized by its
  corner; the pixels go into the appearance stream so every reader shows them. Organize Pages has Append PDF… and
  an Extract button per page (a one-page PDF added to the library). The Signature tool places your saved signature
  (draw it once in the pad; manage, reorder and delete from the Signature tool's editor).
- Lines and arrows: start and end endings (none, open, filled, dot, square) in the Properties popup; the live
  preview shows them.
- Rotate handle above text boxes, text stamps and images (snaps every 15°); More menu has rotate 90° and, for
  images, flip. Lock / Unlock (More menu, ⇧⌘L) sets the PDF "Locked" flag: no move, resize, restyle or delete,
  comments still allowed; other readers honour it too.
- Links: tapping a link with Select or no tool follows it (web or page); the Link tool (Edit tab) draws a box and
  asks for a web address or page number, shows existing links, and selects one to delete it.
- Comments sidebar: sort (page / newest / author) and show (all / open / resolved) menu, "next unresolved" (⇧⌘U).
  Export has a comment summary PDF and a CSV.
- Flatten… lets you burn in everything, only the selection, or chosen authors; the rest stay editable.
- Edit text / crop currently show a "coming soon" toast.
