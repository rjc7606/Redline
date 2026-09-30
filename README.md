# Redline

iPad markup, drawing and notes app (SwiftUI, iPadOS 17+). Three document types share one
annotation engine, one toolbar behaviour, one Style Popover and one set of colour palettes:

- **Markups** — PDF annotation: Favorites / Draw / Annotate / Edit / Forms tabs, comments with
  authors, status and replies, form fields, organize pages. Import a PDF from Files (or open one
  with "Open in Redline"), or create a new PDF on blank, dot, grid or lined paper in four page colours.
  The Markups library has Recents, Favorites, a folder tree (On My iPad › Redline) and a Browse Files…
  entry that opens the system picker for iCloud Drive, OneDrive, Dropbox and other Files providers.
- **Drawings** — layered plan sets: a Base layer plus trace layers with a white "veil", lock/hide,
  flatten down / flatten all.
- **Notes** — paged notebooks: paper colours, templates, tags, single page or facing spread, and a
  calendar view.

## Layout

| Path | What |
| --- | --- |
| `Redline/` | Swift package `RedlineCore`: models, tool catalogue, style presets, palettes, stroke geometry, undo history, document operations, journal geometry, seed data, layout/theme tokens. No UI imports, so it builds and tests on any platform (`cd Redline && swift test`). |
| `App/` | The SwiftUI app: home shelves, workspaces, canvas with Apple Pencil input, style popover, sidebars, settings, PDF export. Built only on macOS/CI. |
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
- Text boxes and callouts have a Font tab (any font on the device via the system font picker, including
  user-installed fonts; weight, size, colour); placing a sticky note opens its comment for typing.
- Tapping an annotation (or its comment in the sidebar) opens a popup beside it with the comment, status, replies
  and a Properties editor that restyles the annotation itself. Annotations with comment text show a small badge.
- Markup and drawing pages stack in a native vertical scroll: free panning in any direction with rubber-band
  bounce (vertically always, horizontally when the page is wider than the view), finger pinch-zoom; the Pencil
  never scrolls. Zoomed-out pages are centred with the larger margins that leaves.
- PDF pages render on a background queue; a neutral placeholder shows until each page image is ready.
- The eraser cuts only the touched part out of ink strokes; its four presets are sizes.
- Bucket fill works on shape-tool shapes and on pen strokes that close on themselves. Double-tapping an Apple Pencil switches
  to the eraser and back (it follows the system Pencil "Double Tap" setting).
- Measure tools, edit text / insert image / link / crop, custom stamps and append/extract pages
  currently show a "coming soon" toast, matching the prototype's preview-only behaviour.
