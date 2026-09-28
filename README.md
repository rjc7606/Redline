# Redline

iPad markup, drawing and notes app (SwiftUI, iPadOS 17+). Three document types share one
annotation engine, one toolbar behaviour, one Style Popover and one set of colour palettes:

- **Markups** — PDF annotation: Favorites / Draw / Annotate / Edit / Forms tabs, comments with
  authors, status and replies, form fields, organize pages, import a real PDF or start from the
  sample plan set.
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
  directory; imported PDFs are copied next to it.
- Measure tools, edit text / insert image / link / crop, custom stamps and append/extract pages
  currently show a "coming soon" toast, matching the prototype's preview-only behaviour.
