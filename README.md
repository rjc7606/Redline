# Redline

iPad markup, drawing and notes app (SwiftUI, iPadOS 17+). Three document types share one
annotation engine, one toolbar behaviour, one Style Popover and one set of colour palettes:

- **Markups** — PDF annotation: Favorites / Draw / Annotate / Edit / Forms tabs, comments with
  authors, status and replies, form fields, organize pages. Import a PDF from Files (or open one
  with "Open in Redline"), or create a new PDF on blank, dot, grid or lined paper.
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
- On PDF pages the highlighter, underline, strikethrough and squiggly tools snap to the page's text
  lines (PDFKit selection); pages without text fall back to a freehand band.
- The Pen responds to Apple Pencil pressure; Fineliner, Felt tip and Marker draw at a constant width.
- A finger moves the page (pan, or flip in notebooks) and can place tap tools; the Apple Pencil draws.
  The Select tool (pinned beside Organize Pages) selects with a tap, a diagonal box drag, or a lasso.
- The eraser cuts only the touched part out of ink strokes. Double-tapping an Apple Pencil switches
  to the eraser and back (it follows the system Pencil "Double Tap" setting).
- Measure tools, edit text / insert image / link / crop, custom stamps and append/extract pages
  currently show a "coming soon" toast, matching the prototype's preview-only behaviour.
