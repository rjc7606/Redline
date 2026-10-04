import SwiftUI
import UIKit
import PDFKit
import RedlineCore

enum SideTab: String, CaseIterable, Hashable {
    case comments, bookmarks, outline, forms, pages, layers, tags
    var label: String { rawValue.capitalized }
}

/// On-page ruler (page coordinates).
struct RulerState: Equatable {
    var on = false
    var x = 500.0
    var y = 360.0
    /// Degrees, 0 ..< 180.
    var angle = 0.0
    var lock = false
}

enum MarkupTab: Hashable {
    case favorites(Int)
    case tab(String)
}

enum WorkspacePopover: Equatable { case tray, stamps, export }
enum JournalView: String, CaseIterable { case book, calendar }
enum AuthorFilter: String, CaseIterable { case all = "All", mine = "Mine", others = "Others" }
enum CommentSort: String, CaseIterable { case page = "Page order", newest = "Newest first", author = "By author" }
enum CommentShow: String, CaseIterable { case all = "All", open = "Open", resolved = "Resolved" }

struct CommentItem: Identifiable {
    var comment: Comment
    var pageIndex: Int
    var strokeCount: Int
    var id: ID { comment.id }
}

/// An in-progress inline text edit (new text box, or editing an existing text box / leader).
struct TextEdit: Equatable {
    var page: Int
    var anchor: Point
    var existingID: ID?
    var isLeader: Bool
}

/// Drag state for the PDFKit markup canvas (page space).
enum MkDrag {
    case draw
    case marquee(start: CGPoint)
    /// `boxOnly`: a callout box dragged by itself — the leader (also in `snaps` for undo) re-lays out around its fixed tip.
    case move(start: CGPoint, snaps: [(PDFAnnotation, AnnotationSnapshot)], boxOnly: Bool)
    case resize(center: CGPoint, d0: CGFloat, snaps: [(PDFAnnotation, AnnotationSnapshot)])
    case handle(leader: PDFAnnotation, index: Int, snap: AnnotationSnapshot)
    /// Rotate handle on a text box / stamp / image: angle at touch-down and the rotation it started from.
    case rotate(a: PDFAnnotation, center: CGPoint, a0: CGFloat, r0: CGFloat, snap: AnnotationSnapshot)
    case erase
    case rulerMove(start: CGPoint, base: CGPoint)
    case rulerRotate(a0: CGFloat, r0: Double)
    case rulerTap
    case pan
    /// Polyline: each clean tap places a vertex.
    case polyTap(start: CGPoint)
}
enum MkDrawMode { case free, edge(offset: CGFloat, along0: CGFloat), lock }

struct FlattenRequest: Equatable {
    /// nil → flatten all layers.
    var layerID: ID?
}

struct PointerSample {
    var location: CGPoint      // in the page's scaled view coordinates
    var pressure: Double
    var isPencil: Bool
    /// Location in window coordinates (stable while the page itself is being panned).
    var window: CGPoint = .zero
}

/// Editing state for one open document (tool, page, zoom, selection, in-progress input).
@MainActor
@Observable
final class WorkspaceModel {
    unowned let app: AppModel
    let docID: ID

    var pageIndex = 0
    /// PDFKit-backed state for Markups (unused for Drawings / Notes).
    let mk = MarkupState()
    var mkDrag: MkDrag? = nil
    var mkDragMoved = false
    var mkDrawMode: MkDrawMode = .free
    var mkLassoMode = false
    /// Page the scroll view should bring into view (set by navigation, cleared once done).
    var scrollRequest: Int? = nil
    var tool: Tool
    var zoom: Double = Metrics.defaultZoom
    var pan: CGSize = .zero
    var sidebarOpen = false
    var sideTab: SideTab
    var markupTab: MarkupTab = .favorites(0)

    var selection: Set<ID> = []
    var selectedComment: ID? = nil
    var session: ID? = nil
    var activeLayer: ID? = nil
    var selectedField: ID? = nil

    var live: Stroke? = nil
    var lasso: [Point]? = nil
    var marquee: Rect? = nil
    var eraseHits: Set<ID> = []
    /// Tool to return to after a Pencil double-tap switched to the eraser.
    var toolBeforeEraser: Tool? = nil
    /// Decided by the first touch after an ink tool is picked: finger first → fingers may ink; Pencil first → fingers pan.
    /// nil until that first touch. Reset when the tool changes (not when presets change).
    var fingerInkAllowed: Bool? = nil
    private var previousTool: Tool = .pen
    private var eraseSnapshotPending = false

    var presetsTool: Tool? = nil
    var styleExpanded = false
    var styleTarget: StylePreset.Target = .color
    var palettesExpanded = false
    var popover: WorkspacePopover? = nil
    var organizeOpen = false
    /// The stamp the Stamps tool places (static or dynamic).
    var stamp: StampDef = ToolCatalog.builtInStamps[0]
    var ruler = RulerState()
    static let rulerLength = 820.0
    static let rulerHeight = 72.0
    private enum DrawMode { case free, edge(offset: Double, along0: Double), lock }
    private var drawMode: DrawMode = .free
    var flatten: FlattenRequest? = nil
    var textPrompt: Point? = nil
    var textPromptPage = 0
    var textDraft = ""
    var textEdit: TextEdit? = nil
    /// Comment popup beside the selected annotation, and its expanded Properties editor.
    var annotationPopup = false
    var annotationProps = false
    /// Focus the popup's comment field when it opens (sticky note just placed).
    var annotationFocusComment = false
    private var annotationStyleSnapshot = false
    private var pendingTextEditID: ID? = nil
    private var handleDrag: (id: ID, index: Int)? = nil
    var textAlertVisible = false
    var layerRenameVisible = false
    var favRenameVisible = false
    var layerMenu: ID? = nil
    var renameLayerID: ID? = nil
    var renameDraft = ""
    var renameFavIndex: Int? = nil
    var shareURL: URL? = nil

    // journal
    var journalView: JournalView = .book
    var spread = false
    var calOffset = 0
    var dateMode: DateMode = .created
    var tagFilter: String? = nil
    var tagQuery = ""
    var tagDraft = ""
    var tagPopoverPage: Int? = nil
    var flipDx: Double = 0

    // comments
    var authorFilter: AuthorFilter = .all
    var commentSort: CommentSort = .page
    var commentShow: CommentShow = .all
    var replyDraft = ""

    /// Set by the view from its width.
    var isCompact = false

    private enum Drag {
        case draw, marquee(Point), lasso, move(start: Point, base: [Stroke]), scale(center: Point, d0: Double, base: [Stroke]), erase, flip(x0: Double), pan(start: CGPoint, last: CGPoint, axis: PanAxis?)
        case rulerMove(start: Point, baseX: Double, baseY: Double), rulerRotate(a0: Double, r0: Double), rulerTap
    }
    /// Single-finger panning locks to the direction of the first movement.
    private enum PanAxis { case horizontal, vertical }
    private var drag: Drag? = nil
    private var dragMoved = false
    /// Points of the current selection drag; becomes a lasso once the path stops being a straight diagonal.
    private var selectPath: [Point] = []
    private var lassoMode = false
    /// Page index the in-progress pointer interaction belongs to (spreads draw on either page).
    var dragPage = 0

    init(app: AppModel, docID: ID) {
        self.app = app
        self.docID = docID
        let d = app.store.document(docID)!
        switch d.type {
        case .markup: tool = .none; sideTab = .comments
        case .drawing: tool = .pen; sideTab = .layers
        case .journal: tool = .pen; sideTab = .pages
        }
        if d.type == .drawing { activeLayer = d.pages.first?.layers.last?.id }
        if d.type == .markup { mkLoad() }
    }

    // MARK: - Document access

    var doc: Document { app.store.document(docID) ?? Document(type: .markup, name: "", pages: [.markup()]) }
    var type: DocumentType { doc.type }
    var canvas: Size { doc.canvasSize }
    var page: Page { doc.pages[min(pageIndex, max(0, doc.pages.count - 1))] }
    var pageCount: Int { isPDF ? mk.pageCount : doc.pages.count }

    var strokeContext: StrokeContext { StrokeContext(pageIndex: pageIndex, layerID: activeLayer) }
    func context(page i: Int) -> StrokeContext { StrokeContext(pageIndex: i, layerID: activeLayer) }

    /// Strokes the current tool acts on (active layer for drawings).
    var currentStrokes: [Stroke] { doc.strokes(at: strokeContext) }

    var canUndo: Bool { isPDF ? !mk.undoStack.isEmpty : app.store.canUndo(docID) }
    var canRedo: Bool { isPDF ? !mk.redoStack.isEmpty : app.store.canRedo(docID) }

    var sideTabs: [SideTab] {
        switch type { case .markup: [.comments, .bookmarks, .outline]; case .drawing: [.layers, .pages]; case .journal: [.pages, .tags] }
    }
    var onFormsTab: Bool { markupTab == .tab("forms") }
    var sidebarWidth: Double { type == .markup ? Metrics.sidebarMarkup : Metrics.sidebarStudio }

    var favorites: [FavoritesTab] { app.settings.favorites }

    /// Tools shown in the toolbar strip.
    var stripTools: [Tool] {
        switch type {
        case .drawing: return ToolCatalog.drawingTools
        case .journal: return ToolCatalog.notesTools
        case .markup:
            switch markupTab {
            case .favorites(let i): return favorites.indices.contains(i) ? favorites[i].tools : ToolCatalog.defaultFavorites
            case .tab(let id): return ToolCatalog.markupTabs.first { $0.id == id }?.tools ?? []
            }
        }
    }

    var onFavoritesTab: Bool { if case .favorites = markupTab { true } else { false } }
    var favoritesIndex: Int { if case .favorites(let i) = markupTab { i } else { 0 } }

    func style(for t: Tool) -> StylePreset { app.styles.current(for: t) }
    var currentStyle: StylePreset { style(for: tool.hasPresets ? tool : .pen) }

    /// Tool whose presets the Style Popover edits.
    var styleTool: Tool { presetsTool ?? (tool.hasPresets ? tool : .pen) }

    var activeLayerObject: Layer? { page.layers.first { $0.id == activeLayer } ?? page.layers.last }

    var statusHint: String {
        switch type {
        case .markup:
            return mk.activeInk != nil ? "Pen strokes are joining one annotation" : "Next pen stroke starts a new annotation"
        case .drawing:
            return "Drawing on: " + (activeLayerObject?.name ?? "Base")
        case .journal:
            return ruler.on ? (ruler.lock ? "Ruler locked: straight lines at the ruler angle" : "Draw along the ruler edge") : "Swipe with Select to flip pages"
        }
    }

    // MARK: - Frame / transforms

    /// Unscaled frame size for a page (swapped for 90°/270° rotation).
    func frameSize(page i: Int) -> CGSize {
        let r = doc.pages.indices.contains(i) ? doc.pages[i].rotation : 0
        return r % 180 == 0 ? CGSize(width: canvas.w, height: canvas.h) : CGSize(width: canvas.h, height: canvas.w)
    }
    var frameSize: CGSize { frameSize(page: pageIndex) }

    /// Page coordinates → unscaled frame coordinates.
    func pageTransform(page i: Int) -> CGAffineTransform {
        let r = doc.pages.indices.contains(i) ? doc.pages[i].rotation : 0
        let f = frameSize(page: i)
        return CGAffineTransform(translationX: f.width / 2, y: f.height / 2)
            .rotated(by: CGFloat(r) * .pi / 180)
            .translatedBy(x: -canvas.w / 2, y: -canvas.h / 2)
    }

    func pagePoint(fromView v: CGPoint, page i: Int) -> Point {
        let f = CGPoint(x: v.x / zoom, y: v.y / zoom).applying(pageTransform(page: i).inverted())
        return Point(f.x, f.y)
    }

    func viewPoint(fromPage p: Point, page i: Int) -> CGPoint {
        let f = CGPoint(x: p.x, y: p.y).applying(pageTransform(page: i))
        return CGPoint(x: f.x * zoom, y: f.y * zoom)
    }

    func fitZoom(available: CGSize) {
        zoom = Metrics.fitZoom(canvas: canvas, available: Size(available.width, available.height), spread: type == .journal && spread)
        pan = .zero
    }
    func zoomIn() {
        if isPDF, let v = mk.pdfView { v.scaleFactor = min(v.maxScaleFactor, v.scaleFactor * 1.2); return }
        zoom = min(Metrics.maxZoom, ((zoom + 0.1) * 100).rounded() / 100)
    }
    func zoomOut() {
        if isPDF, let v = mk.pdfView { v.scaleFactor = max(v.minScaleFactor, v.scaleFactor / 1.2); return }
        zoom = max(Metrics.minZoom, ((zoom - 0.1) * 100).rounded() / 100)
    }
    func pinch(by factor: Double) { zoom = min(Metrics.maxZoom, max(Metrics.minZoom, zoom * factor)) }
    func panBy(_ d: CGSize) {
        if isPDF { mk.activeInk = nil; mk.activeInkRoot = nil; return }
        pan = CGSize(width: pan.width + d.width, height: pan.height + d.height)
        session = nil
    }

    // MARK: - Tools

    func pick(_ t: Tool) {
        let info = t.info
        closePopovers()
        if isPDF { mkFinishPolyline() }
        if info.kind == .flash { tool = t; presetsTool = nil; app.flash(info.message ?? ""); return }
        if info.kind == .pageAction { rotatePage(at: pageIndex); return }
        if info.kind == .stampGallery {
            tool = .stamps
            presetsTool = nil
            popover = popover == .stamps ? nil : .stamps
            selection = []
            return
        }
        if tool == t {
            // Tapping the active tool deselects it and closes its presets; no tool = pan with a finger or Pencil.
            tool = .none
            session = nil
            presetsTool = nil
            styleExpanded = false
            return
        }
        if isPDF, t == .image { mk.imagePickerOn = true }
        if isPDF, t == .signature, (app.settings.signatures ?? []).isEmpty { mk.signaturePadOn = true }
        let keepSession = t.isPen && (tool.isPen || tool == .eraser || tool == .none)
        previousTool = tool
        tool = t
        fingerInkAllowed = nil
        if !keepSession { mk.activeInk = nil; mk.activeInkRoot = nil }
        if t != .eraser { toolBeforeEraser = nil }
        if !keepSession { session = nil }
        if t != .select && t != .lasso { selection = []; selectedField = nil }
        // Tools with presets keep their four presets visible under the button while selected.
        presetsTool = t.hasPresets ? t : nil
        styleExpanded = false
        styleTarget = .color
        if let h = ToolCatalog.pickHint(for: t, rulerLocked: ruler.on && ruler.lock) { app.flash(h) }
    }

    /// Closes transient popovers. The presets row under the active tool stays; only the expanded editor collapses.
    func closePopovers() {
        styleExpanded = false
        popover = nil
        layerMenu = nil
        tagPopoverPage = nil
    }

    /// Hides the presets row too (tool deselected or switched to a tool without presets).
    func closeAllPopovers() {
        closePopovers()
        presetsTool = nil
    }

    /// Tap on a preset: use it (the row stays). Tapping the already-selected preset toggles the style editor.
    func selectPreset(_ i: Int) {
        let t = styleTool
        if app.styles.selectedIndex(for: t) == i {
            styleExpanded.toggle()
            if styleExpanded { styleTarget = .color }
        } else {
            app.styles.select(i, for: t)
            // Markups keep the pen chain open: a new colour becomes a grouped Ink annotation.
            if !isPDF { session = nil }
        }
    }

    func updateStyle(_ body: (inout StylePreset) -> Void) {
        app.styles.update(styleTool, body)
    }

    /// Pencil double-tap: eraser ⇄ the pen you were using (or previous tool, per the system setting).
    func pencilDoubleTap() {
        closePopovers()
        let defaultPen: Tool = type == .markup ? .fineliner : .pen
        if UIPencilInteraction.preferredTapAction == .switchPrevious {
            let p = previousTool
            previousTool = tool
            tool = p == .none ? defaultPen : p
            app.flash(tool.label)
            return
        }
        if tool == .eraser {
            let back = toolBeforeEraser ?? (previousTool == .eraser ? defaultPen : previousTool)
            toolBeforeEraser = nil
            previousTool = .eraser
            tool = back == .none ? defaultPen : back
            fingerInkAllowed = nil
            app.flash(tool.label)
        } else {
            toolBeforeEraser = tool
            previousTool = tool
            tool = .eraser
            fingerInkAllowed = nil
            app.flash("Eraser — double-tap again to go back to \(toolBeforeEraser?.label ?? "pen")")
        }
    }

    func toggleRuler() {
        if isPDF { mkToggleRuler(); return }
        ruler.on.toggle()
        if ruler.on {
            // Bring it onto the current page centre.
            ruler.x = canvas.w / 2
            ruler.y = canvas.h / 2
            app.flash("Drag the ruler to move · turn the end handles to rotate")
        } else {
            app.flash("Ruler hidden")
        }
    }

    func toggleRulerLock() {
        ruler.lock.toggle()
        mk.renderTick += 1
        app.flash(ruler.lock ? "Locked — lines draw parallel or perpendicular to the ruler, anywhere on the page" : "Unlocked — draw along the ruler edge")
    }

    /// Ruler centre, direction and normal in page coordinates.
    private func rulerAxes() -> (c: Point, d: Point, n: Point) {
        let a = ruler.angle * .pi / 180
        return (Point(ruler.x, ruler.y), Point(cos(a), sin(a)), Point(-sin(a), cos(a)))
    }

    private enum RulerHit { case body, handle, lock }

    /// Which part of the ruler a page point is on, if any (hit sizes are in screen points).
    private func rulerHit(_ p: Point) -> RulerHit? {
        guard ruler.on else { return nil }
        let A = rulerAxes()
        let vx = p.x - A.c.x, vy = p.y - A.c.y
        let along = vx * A.d.x + vy * A.d.y, across = vx * A.n.x + vy * A.n.y
        let halfL = WorkspaceModel.rulerLength / 2, halfH = WorkspaceModel.rulerHeight / 2
        guard abs(along) <= halfL, abs(across) <= halfH else { return nil }
        let handleR = 22 / zoom
        let handleX = halfL - 30 / zoom
        if abs(abs(along) - handleX) <= handleR && abs(across) <= handleR { return .handle }
        if abs(along) <= 72 / zoom && abs(across) <= 16 / zoom { return .lock }
        return .body
    }

    /// May a finger ink right now? First touch after picking an ink tool decides in Auto mode.
    private func fingerMayInk(deciding isPencil: Bool) -> Bool {
        switch app.settings.fingerDrawingMode {
        case .always: return true
        case .never: return false
        case .auto:
            if fingerInkAllowed == nil { fingerInkAllowed = !isPencil }
            return fingerInkAllowed ?? true
        }
    }

    // MARK: - Undo / pages

    func undo() { if isPDF { mkUndo(); return }; app.store.undo(docID); session = nil; selection = []; clampPage(); app.scheduleSave() }
    func redo() { if isPDF { mkRedo(); return }; app.store.redo(docID); session = nil; selection = []; clampPage(); app.scheduleSave() }
    private func clampPage() { pageIndex = min(pageIndex, max(0, pageCount - 1)) }

    func setPage(_ i: Int) {
        let n = max(0, min(pageCount - 1, i))
        scrollRequest = n
        if isPDF { mk.scrollToPage = n; mk.activeInk = nil; mk.activeInkRoot = nil }
        guard n != pageIndex else { return }
        pageIndex = n
        session = nil
        selection = []
        selectedField = nil
        tagPopoverPage = nil
        if type == .drawing, !page.layers.contains(where: { $0.id == activeLayer }) { activeLayer = page.layers.last?.id }
    }
    func prevPage() {
        if type == .journal { let g = book; if g.canBack { setPage(g.prevIndex) } } else { setPage(pageIndex - 1) }
    }
    func nextPage() {
        if type == .journal { let g = book; if g.nextExists { setPage(g.nextIndex) } else { addJournalPage() } } else { setPage(pageIndex + 1) }
    }

    var book: BookGeometry { BookGeometry(pageCount: pageCount, pageIndex: pageIndex, spread: spread) }

    func addPage() {
        if isPDF { mkInsertBlankPage(after: pageIndex); return }
        if type == .journal { addJournalPage(); return }
        var at = pageIndex
        app.mutate(docID) { at = $0.insertPage(after: self.pageIndex) }
        if type == .drawing { activeLayer = doc.pages[at].layers.first?.id }
        pageIndex = at
        app.flash(type == .markup ? "Blank page inserted after this page" : "Page added")
    }
    func addJournalPage() {
        var at = pageIndex
        app.mutate(docID) { at = $0.appendJournalPage() }
        pageIndex = at
        session = nil
        app.flash("New page added")
    }
    func deletePage(at i: Int) {
        if isPDF { mkDeletePage(i); return }
        guard pageCount > 1 else { app.flash("A document needs at least one page"); return }
        app.mutate(docID) { $0.deletePage(at: i) }
        clampPage()
        app.flash("Page deleted")
    }
    func duplicatePage(at i: Int) { if isPDF { mkDuplicatePage(i); return }; app.mutate(docID) { $0.duplicatePage(at: i) }; app.flash("Page duplicated") }
    func rotatePage(at i: Int) { if isPDF { mkRotatePage(i); return }; app.mutate(docID) { $0.rotatePage(at: i) }; app.flash("Page rotated 90°") }
    func movePage(from: Int, to: Int) {
        let curID = page.id
        app.mutate(docID) { $0.movePage(from: from, to: to) }
        if let i = doc.pageIndex(of: curID) { pageIndex = i }
    }
    func toggleBookmark() {
        if isPDF {
            let key = "page:\(pageIndex)"
            app.mutate(docID) { d in if d.bookmarks.contains(key) { d.bookmarks.removeAll { $0 == key } } else { d.bookmarks.append(key) } }
            return
        }
        app.mutate(docID) { $0.toggleBookmark(pageIndex: self.pageIndex) }
    }

    // MARK: - Selection

    var selectionBounds: Rect? {
        let sel = currentStrokes.filter { selection.contains($0.id) }
        guard !sel.isEmpty else { return nil }
        var r = StrokeGeometry.bounds(of: sel[0])
        for s in sel.dropFirst() {
            let b = StrokeGeometry.bounds(of: s)
            let x0 = min(r.minX, b.minX), y0 = min(r.minY, b.minY), x1 = max(r.maxX, b.maxX), y1 = max(r.maxY, b.maxY)
            r = Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
        }
        return r
    }

    func clearSelection() { selection = []; selectedComment = nil; selectedField = nil; closeAnnotationPopup(); if isPDF { mkClearSelection() } }

    func openAnnotationPopup() {
        guard type == .markup, selectedComment != nil else { return }
        annotationPopup = true
        annotationProps = false
        annotationStyleSnapshot = false
        replyDraft = ""
    }
    func closeAnnotationPopup() { annotationPopup = false; annotationProps = false; annotationStyleSnapshot = false }

    // MARK: - Annotation properties (edits the selected marks themselves)

    var selectedStrokeTool: Tool? { currentStrokes.first { selection.contains($0.id) }?.tool }

    static func preset(of s: Stroke) -> StylePreset {
        StylePreset(color: s.color, width: s.width ?? ToolStyles.base(for: s.tool).width, opacity: s.opacity, lineStyle: s.lineStyle, pressure: nil,
                    fill: s.fill, fillPattern: s.fillPattern, fillOpacity: s.fillOpacity, background: s.background, backgroundOpacity: s.backgroundOpacity,
                    borderColor: s.borderColor, borderOpacity: s.borderOpacity, borderWidth: s.borderWidth, font: s.font, fontWeight: s.fontWeight)
    }
    static func apply(_ p: StylePreset, to s: inout Stroke) {
        s.color = p.color; s.width = p.width; s.opacity = p.opacity; s.lineStyle = p.lineStyle
        s.fill = p.fill; s.fillPattern = p.fillPattern; s.fillOpacity = p.fillOpacity
        s.background = p.background; s.backgroundOpacity = p.backgroundOpacity
        s.borderColor = p.borderColor; s.borderOpacity = p.borderOpacity; s.borderWidth = p.borderWidth
        s.font = p.font; s.fontWeight = p.fontWeight
    }

    func selectedPreset() -> StylePreset? {
        currentStrokes.first { selection.contains($0.id) }.map { WorkspaceModel.preset(of: $0) }
    }

    /// Applies a style change to every selected mark (one undo step per popup session).
    func updateSelectedStyle(_ body: (inout StylePreset) -> Void) {
        guard !selection.isEmpty else { return }
        if !annotationStyleSnapshot { app.mutate(docID) { _ in }; annotationStyleSnapshot = true }
        let ids = selection
        let ctx = strokeContext
        let cid = selectedComment
        app.patch(docID) { d in
            var color: String? = nil
            d.updateStrokes(ids: ids, at: ctx) { s in
                var p = WorkspaceModel.preset(of: s)
                body(&p)
                WorkspaceModel.apply(p, to: &s)
                if color == nil { color = s.color }
            }
            if let cid, let color { d.editComment(cid) { $0.color = color } }
        }
    }

    func deleteSelection() {
        if isPDF { mkDeleteSelection(); return }
        guard !selection.isEmpty else { return }
        let n = selection.count
        app.mutate(docID) { $0.removeStrokes(ids: self.selection, at: self.strokeContext) }
        selection = []
        app.flash(n > 1 ? "\(n) annotations deleted" : "Annotation deleted")
    }

    func duplicateSelection() {
        if isPDF { mkDuplicateSelection(); return }
        guard !selection.isEmpty else { return }
        var ids: [ID] = []
        let ordered = currentStrokes.filter { selection.contains($0.id) }.map(\.id)
        app.mutate(docID) { ids = $0.duplicateStrokes(ids: ordered, at: self.strokeContext) }
        selection = Set(ids)
    }

    func selectAll() {
        selection = Set(currentStrokes.map(\.id))
        if type == .markup { tool = .select }
    }

    // MARK: - Comments

    var visibleComments: [CommentItem] {
        let me = app.author
        return doc.comments.compactMap { c -> CommentItem? in
            guard let pi = doc.pageIndex(of: c.pageID) else { return nil }
            switch authorFilter {
            case .all: break
            case .mine: if c.author != me { return nil }
            case .others: if c.author == me { return nil }
            }
            return CommentItem(comment: c, pageIndex: pi, strokeCount: doc.strokeIDs(for: c.id).count)
        }.sorted { a, b in a.pageIndex != b.pageIndex ? a.pageIndex < b.pageIndex : a.comment.time > b.comment.time }
    }

    func selectComment(_ id: ID) {
        if selectedComment == id { selectedComment = nil; selection = []; return }
        guard let c = doc.comments.first(where: { $0.id == id }), let pi = doc.pageIndex(of: c.pageID) else { return }
        setPage(pi)
        selectedComment = id
        replyDraft = ""
        selection = Set(doc.strokeIDs(for: id))
        closePopovers()
        openAnnotationPopup()
    }
    func setStatus(_ id: ID, _ s: CommentStatus) { app.mutate(docID) { $0.editComment(id) { $0.status = s } } }
    func setCommentText(_ id: ID, _ text: String) { app.patch(docID) { $0.editComment(id) { $0.text = text } } }
    func deleteComment(_ id: ID) {
        app.mutate(docID) { $0.deleteComment(id) }
        if selectedComment == id { selectedComment = nil }
        if session == id { session = nil }
        selection = []
    }
    func addReply(_ id: ID) {
        let t = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        app.mutate(docID) { $0.addReply(to: id, author: self.app.author, text: t) }
        replyDraft = ""
    }

    // MARK: - Forms

    func placeField(_ ft: FieldType, at p: Point, page i: Int) {
        var f: FormField? = nil
        app.mutate(docID) { f = $0.placeField(ft, at: p, pageIndex: i) }
        selectedField = f?.id
        tool = .select
    }
    func editField(_ id: ID, undoable: Bool = false, _ body: @escaping (inout FormField) -> Void) {
        if undoable { app.mutate(docID) { $0.editField(id, pageIndex: self.pageIndex, body) } } else { app.patch(docID) { $0.editField(id, pageIndex: self.pageIndex, body) } }
    }
    func deleteField(_ id: ID) {
        app.mutate(docID) { $0.deleteField(id, pageIndex: self.pageIndex) }
        if selectedField == id { selectedField = nil }
    }

    // MARK: - Layers

    func addLayer() {
        var id: ID? = nil
        app.mutate(docID) { id = $0.addTraceLayer(pageIndex: self.pageIndex, above: self.activeLayer) }
        activeLayer = id
    }
    func editLayer(_ id: ID, undoable: Bool = true, _ body: @escaping (inout Layer) -> Void) {
        if undoable { app.mutate(docID) { $0.editLayer(id, pageIndex: self.pageIndex, body) } } else { app.patch(docID) { $0.editLayer(id, pageIndex: self.pageIndex, body) } }
    }
    func doFlatten(_ mode: FlattenMode) {
        guard let f = flatten else { return }
        var active: ID? = nil
        app.mutate(docID) { active = $0.flatten(pageIndex: self.pageIndex, layerID: f.layerID, mode: mode) }
        if let a = active { activeLayer = a }
        flatten = nil
    }
    func commitLayerRename() {
        guard let id = renameLayerID else { return }
        let n = renameDraft.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { editLayer(id) { $0.name = n } }
        renameLayerID = nil
    }

    // MARK: - Journal

    func addTag(_ name: String, page i: Int) {
        app.mutate(docID) { $0.addTag(name, pageIndex: i) }
        tagDraft = ""
    }
    func removeTag(_ name: String, page i: Int) { app.mutate(docID) { $0.removeTag(name, pageIndex: i) } }
    func setSpread(_ v: Bool, available: CGSize) {
        spread = v
        tagPopoverPage = nil
        fitZoom(available: available)
    }

    // MARK: - Favorites

    func addFavoritesTab() {
        var s = app.settings
        guard s.favorites.count < 4 else { return }
        s.favorites.append(FavoritesTab(name: "★ \(s.favorites.count + 1)", pins: ["fineliner"]))
        app.settings = s
        markupTab = .favorites(s.favorites.count - 1)
        renameFavIndex = s.favorites.count - 1
        renameDraft = s.favorites.last?.name ?? ""
        favRenameVisible = true
    }
    func removeFavoritesTab(_ i: Int) {
        var s = app.settings
        guard s.favorites.count > 1, s.favorites.indices.contains(i) else { return }
        s.favorites.remove(at: i)
        app.settings = s
        markupTab = .favorites(max(0, i - 1))
    }
    func commitFavRename() {
        guard let i = renameFavIndex else { return }
        var s = app.settings
        let n = renameDraft.trimmingCharacters(in: .whitespaces)
        if s.favorites.indices.contains(i), !n.isEmpty { s.favorites[i].name = n }
        app.settings = s
        renameFavIndex = nil
    }
    func togglePin(_ t: Tool) {
        var s = app.settings
        let i = favoritesIndex
        guard s.favorites.indices.contains(i) else { return }
        if let idx = s.favorites[i].pins.firstIndex(of: t.rawValue) {
            s.favorites[i].pins.remove(at: idx)
        } else {
            s.favorites[i].pins.append(t.rawValue)
        }
        app.settings = s
    }
    func removePin(at index: Int) {
        var s = app.settings
        let i = favoritesIndex
        guard s.favorites.indices.contains(i), s.favorites[i].pins.indices.contains(index) else { return }
        s.favorites[i].pins.remove(at: index)
        app.settings = s
    }
    func movePin(from: Int, to: Int) {
        var s = app.settings
        let i = favoritesIndex
        guard s.favorites.indices.contains(i), s.favorites[i].pins.indices.contains(from), s.favorites[i].pins.indices.contains(to) else { return }
        let p = s.favorites[i].pins.remove(at: from)
        s.favorites[i].pins.insert(p, at: to)
        app.settings = s
    }
    func pinCount(_ t: Tool) -> Int {
        guard favorites.indices.contains(favoritesIndex) else { return 0 }
        return favorites[favoritesIndex].tools.filter { $0 == t }.count
    }

    // MARK: stamps

    /// Picks a stamp and arms the Stamps tool.
    func useStamp(_ s: StampDef) {
        stamp = s
        if tool != .stamps { previousTool = tool; tool = .stamps }
        presetsTool = nil
        popover = nil
        selection = []
        fingerInkAllowed = nil
        app.flash("Tap the page to place \"\(s.resolved(author: app.author))\"")
    }

    /// Adds a specific stamp to the current Favorites tab (or the first one).
    func pinStamp(_ s: StampDef) {
        var st = app.settings
        let i = onFavoritesTab ? favoritesIndex : 0
        guard st.favorites.indices.contains(i) else { return }
        let key = "stamp:" + s.id
        if !st.favorites[i].pins.contains(key) { st.favorites[i].pins.append(key) }
        app.settings = st
        app.flash("\"\(s.text)\" added to \(st.favorites[i].name)")
    }

    /// The stamp pinned at a strip position, when that pin is a stamp.
    func pinnedStamp(at i: Int) -> StampDef? {
        guard onFavoritesTab, favorites.indices.contains(favoritesIndex), let id = favorites[favoritesIndex].stampID(at: i) else { return nil }
        return app.settings.allStamps.first { $0.id == id }
    }

    // MARK: - Pointer input (page-scaled view coordinates)

    private func newStroke(_ t: Tool, at p: Point, pressure: Double, isPencil: Bool) -> Stroke {
        let st = style(for: t)
        // Pen responds to Pencil pressure; Fineliner, Felt tip and Marker keep a constant width.
        var s = Stroke(tool: t, color: st.color, points: [StrokePoint(p.x, p.y, isPencil ? pressure : 0.5)], width: st.width,
                       weight: t == .pen && isPencil ? .pressure : .constant, opacity: st.opacity, lineStyle: st.lineStyle)
        if t.isShape { s.fill = st.fill ?? st.color; s.fillPattern = st.fillPattern ?? FillPattern.none; s.fillOpacity = st.fillOpacity ?? 0.5 }
        if t == .callout { s.fill = st.fill; s.fillPattern = st.fillPattern ?? FillPattern.none; s.fillOpacity = st.fillOpacity ?? 0.5 }
        if t == .redact { s.color = "#1c1c1e" }
        return s
    }

    func topStroke(at p: Point, page i: Int) -> Stroke? {
        doc.strokes(at: context(page: i)).last { Hit.strokeTouches($0, point: p, radius: 6 / zoom) }
    }

    func pointerDown(_ s: PointerSample, page i: Int) {
        let p = pagePoint(fromView: s.location, page: i)
        dragMoved = false
        dragPage = i
        // Touching another page in the vertical scroll makes it current (no scrolling).
        if i != pageIndex, doc.pages.indices.contains(i) {
            pageIndex = i
            session = nil
            selection = []
            selectedField = nil
            closeAnnotationPopup()
        }
        closePopovers()
        commitTextEdit()
        let info = tool.info
        // Any touch with a non-select tool deselects the current comment / selection.
        if info.kind != .select && info.kind != .lasso { selectedComment = nil; selection = []; selectedField = nil; closeAnnotationPopup() }
        // Finger on the ruler: move it, rotate it (end handles) or toggle Lock (centre). The Pencil passes through.
        if !s.isPencil, let hit = rulerHit(p) {
            switch hit {
            case .body: drag = .rulerMove(start: p, baseX: ruler.x, baseY: ruler.y)
            case .handle: drag = .rulerRotate(a0: atan2(p.y - ruler.y, p.x - ruler.x) * 180 / .pi, r0: ruler.angle)
            case .lock: drag = .rulerTap
            }
            return
        }
        // No tool = move the page. Whoever touches first after picking an ink tool decides whether fingers ink or pan.
        let fingerBlocked = !s.isPencil && info.kind == .ink && !fingerMayInk(deciding: false)
        if s.isPencil, info.kind == .ink { _ = fingerMayInk(deciding: true) }
        // A finger with a tap-only tool (stamp, note, text, field, fill) pans if it moves; the tap happens only on a clean lift.
        let fingerTapTool = !s.isPencil && (info.isTap || info.kind == .fill)
        if info.kind == .none || fingerBlocked || fingerTapTool {
            // Panning with a finger ends the current ink comment chain.
            session = nil
            if type == .journal && journalView == .book { drag = .flip(x0: Double(s.window.x)); flipDx = 0 } else { drag = .pan(start: s.window, last: s.window, axis: nil) }
            return
        }
        if type == .drawing, info.isDrag || info.isTap, let L = activeLayerObject, L.locked || !L.visible {
            app.flash(L.locked ? "Active layer is locked" : "Active layer is hidden")
            drag = nil
            return
        }
        switch info.kind {
        case .none:
            drag = .pan(start: s.window, last: s.window, axis: nil)
        case .select, .lasso:
            if type == .markup, let f = page.fields.last(where: { $0.frame.contains(p) }), i == pageIndex {
                selectedField = f.id
                if f.type.isToggleLike { app.mutate(docID) { $0.editField(f.id, pageIndex: i) { $0.value = $0.isOn ? "" : "on" } } }
                drag = nil
                return
            }
            if i == pageIndex, let hit = topStroke(at: p, page: i) {
                // Tap selects first; a drag only moves something that is already selected.
                if selection.contains(hit.id) {
                    drag = .move(start: p, base: currentStrokes)
                    pendingTextEditID = (hit.tool == .textbox || hit.tool == .callout) ? hit.id : nil
                } else {
                    // A mark that belongs to a comment selects the whole comment (all its marks move together).
                    if let cid = hit.commentID { selection = Set(doc.strokeIDs(for: cid)); selectedComment = cid; openAnnotationPopup() }
                    else { selection = [hit.id]; selectedComment = nil; closeAnnotationPopup() }
                    drag = nil
                }
            } else {
                // Drag on empty space: a straight diagonal drag is a box; a curving drag becomes a lasso.
                drag = .marquee(p)
                marquee = nil
                selectPath = [p]
                lassoMode = false
            }
        case .ink, .highlight, .textMarkup, .shape:
            live = newStroke(tool, at: p, pressure: s.pressure, isPencil: s.isPencil)
            drag = .draw
            selection = []
            drawMode = .free
            if tool.kind == .ink, ruler.on {
                let A = rulerAxes()
                let vx = p.x - A.c.x, vy = p.y - A.c.y
                let along = vx * A.d.x + vy * A.d.y, across = vx * A.n.x + vy * A.n.y
                if ruler.lock {
                    drawMode = .lock
                } else if abs(along) <= WorkspaceModel.rulerLength / 2,
                          abs(across) >= WorkspaceModel.rulerHeight / 2 - 2, abs(across) <= WorkspaceModel.rulerHeight / 2 + 40 {
                    let sw = style(for: tool).width
                    drawMode = .edge(offset: (across < 0 ? -1 : 1) * (WorkspaceModel.rulerHeight / 2 + sw / 2 + 1), along0: along)
                }
            }
        case .eraser:
            eraseSnapshotPending = true
            drag = .erase
            eraseAt(p, page: i)
        case .place, .text, .stampGallery, .stampPreset, .form, .fill:
            drag = .draw // tap tools finish on up
        default:
            drag = nil
        }
    }

    func pointerMove(_ s: PointerSample, page i: Int) {
        guard let d = drag else { return }
        let p = pagePoint(fromView: s.location, page: i)
        switch d {
        case .draw:
            guard var st = live else { return }
            let last = st.points.last!
            if Point(last.x, last.y).distance(to: p) < 1.2 && st.tool.kind == .ink { return }
            dragMoved = true
            let pt = StrokePoint(p.x, p.y, s.isPencil ? s.pressure : 0.5)
            switch st.tool.kind {
            case .ink:
                switch drawMode {
                case .free:
                    st.points.append(pt)
                case .edge(let offset, let along0):
                    let A = rulerAxes()
                    let half = WorkspaceModel.rulerLength / 2
                    let along = max(-half, min(half, (p.x - A.c.x) * A.d.x + (p.y - A.c.y) * A.d.y))
                    func at(_ q: Double) -> StrokePoint {
                        StrokePoint(A.c.x + A.d.x * q + A.n.x * offset, A.c.y + A.d.y * q + A.n.y * offset, pt.p)
                    }
                    st.points = [at(along0), at(along)]
                case .lock:
                    let A = rulerAxes()
                    let a = st.points[0]
                    let vx = p.x - a.x, vy = p.y - a.y
                    let pd = vx * A.d.x + vy * A.d.y, pn = vx * A.n.x + vy * A.n.y
                    let u = abs(pd) >= abs(pn) ? Point(A.d.x * pd, A.d.y * pd) : Point(A.n.x * pn, A.n.y * pn)
                    st.points = [a, StrokePoint(a.x + u.x, a.y + u.y, pt.p)]
                }
            case .highlight, .textMarkup:
                // Text markup only ever attaches to the PDF's text lines.
                st.points = [st.points[0], pt]
                if let f = doc.pdfFile {
                    let rects = app.pdf.textLineRects(file: f, index: doc.pages[i].pdfPageIndex ?? i, from: st.points[0].point, to: p, canvas: canvas)
                    st.rects = rects.isEmpty ? nil : rects
                } else {
                    st.rects = nil
                }
            case .shape:
                if st.tool == .polyline || st.tool == .polygon { st.points.append(pt) } else { st.points = [st.points[0], pt] }
            default: break
            }
            live = st
        case .marquee(let start):
            dragMoved = true
            if selectPath.last.map({ $0.distance(to: p) >= 2 }) ?? true { selectPath.append(p) }
            if !lassoMode {
                let deviation = selectPath.map { Hit.distance($0, toSegment: start, p) }.max() ?? 0
                if deviation > 14 / zoom { lassoMode = true; marquee = nil }
            }
            if lassoMode { lasso = selectPath } else { marquee = Rect.from(start, p) }
        case .lasso:
            dragMoved = true
            if let l = lasso?.last, l.distance(to: p) >= 2 { lasso?.append(p) }
        case .move(let start, let base):
            if !dragMoved {
                if start.distance(to: p) < 2 / zoom { return }
                dragMoved = true
                app.mutate(docID) { _ in }
            }
            let dx = p.x - start.x, dy = p.y - start.y
            let sel = selection
            let ctx = strokeContext
            app.patch(docID) { d in
                d.editStrokes(at: ctx) { arr in arr = base.map { sel.contains($0.id) ? $0.shifted(dx: dx, dy: dy) : $0 } }
            }
        case .scale(let c, let d0, let base):
            if !dragMoved { dragMoved = true; app.mutate(docID) { _ in } }
            let f = max(0.05, p.distance(to: c) / d0)
            let sel = selection
            let ctx = strokeContext
            app.patch(docID) { d in
                d.editStrokes(at: ctx) { arr in arr = base.map { sel.contains($0.id) ? $0.scaled(by: f) : $0 } }
            }
        case .erase:
            eraseAt(p, page: i)
        case .flip(let x0):
            dragMoved = true
            flipDx = Double(s.window.x) - x0
        case .rulerMove(let start, let baseX, let baseY):
            dragMoved = true
            ruler.x = baseX + (p.x - start.x)
            ruler.y = baseY + (p.y - start.y)
        case .rulerRotate(let a0, let r0):
            dragMoved = true
            let ang = atan2(p.y - ruler.y, p.x - ruler.x) * 180 / .pi
            var na = ang - a0 + r0
            na = (na.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
            let snapped = (na / 15).rounded() * 15
            if abs(na - snapped) < 2.5 { na = snapped.truncatingRemainder(dividingBy: 180) }
            ruler.angle = na
        case .rulerTap:
            break
        case .pan(let start, let last, let axisIn):
            var axis = axisIn
            if axis == nil {
                // Lock to the first clear direction the finger moves in.
                let tx = s.window.x - start.x, ty = s.window.y - start.y
                if abs(tx) + abs(ty) < 4 { return }
                axis = abs(tx) >= abs(ty) ? .horizontal : .vertical
            }
            let dx = axis == .horizontal ? s.window.x - last.x : 0
            let dy = axis == .vertical ? s.window.y - last.y : 0
            if dx != 0 || dy != 0 {
                dragMoved = true
                // Sheets scroll natively (the scroll view cancels this touch once it takes over); notebooks flip.
                if type == .journal { panBy(CGSize(width: dx, height: dy)) }
            }
            drag = .pan(start: start, last: s.window, axis: axis)
        }
    }

    func pointerUp(_ s: PointerSample, page i: Int) {
        guard let d = drag else { return }
        drag = nil
        let p = pagePoint(fromView: s.location, page: i)
        switch d {
        case .draw:
            if let st = live {
                live = nil
                if dragMoved || st.tool.kind == .ink { commit(st, page: i) }
                return
            }
            if !dragMoved { tap(at: p, page: i) }
        case .marquee:
            let r = marquee
            let poly = selectPath
            marquee = nil
            lasso = nil
            selectPath = []
            if lassoMode, dragMoved, poly.count >= 3 {
                selection = Set(doc.strokes(at: context(page: i)).filter { Hit.polygon(poly, contains: StrokeGeometry.bounds(of: $0).center) }.map(\.id))
                if !selection.isEmpty { app.flash("\(selection.count) selected") }
            } else if let r, dragMoved {
                selection = Set(doc.strokes(at: context(page: i)).filter { r.contains(StrokeGeometry.bounds(of: $0).center) }.map(\.id))
                if !selection.isEmpty { app.flash("\(selection.count) selected") }
            } else {
                clearSelection()
            }
            lassoMode = false
        case .lasso:
            let poly = lasso ?? []
            lasso = nil
            if dragMoved, poly.count >= 3 {
                selection = Set(doc.strokes(at: context(page: i)).filter { Hit.polygon(poly, contains: StrokeGeometry.bounds(of: $0).center) }.map(\.id))
                if !selection.isEmpty { app.flash("\(selection.count) selected") }
            } else {
                clearSelection()
            }
        case .move, .scale:
            // A tap (no drag) on an already-selected text box / leader edits its text in place.
            if !dragMoved, let id = pendingTextEditID, let s = currentStrokes.first(where: { $0.id == id }) { editExisting(s, page: i) }
            pendingTextEditID = nil
        case .erase:
            eraseSnapshotPending = false
        case .flip:
            let dx = flipDx
            flipDx = 0
            let g = book
            let threshold = canvas.w * zoom * 0.3
            if dx < -threshold { if g.nextExists { setPage(g.nextIndex) } else if dx < -threshold * 1.8 { addJournalPage() } }
            else if dx > threshold, g.canBack { setPage(g.prevIndex) }
            else if !dragMoved, tool.info.isTap || tool.kind == .fill { tap(at: p, page: i) }
        case .pan:
            // A finger tap (no movement) still places tap tools.
            if !dragMoved, tool.info.isTap || tool.kind == .fill { tap(at: p, page: i) }
        case .rulerTap:
            toggleRulerLock()
        case .rulerMove, .rulerRotate:
            break
        }
    }

    func pointerCancel() {
        if case .flip = drag { flipDx = 0 }
        drag = nil
        live = nil
        lasso = nil
        marquee = nil
        selectPath = []
        lassoMode = false
        eraseHits = []
    }

    func beginScale(page i: Int, handle: CGPoint) {
        guard let b = selectionBounds else { return }
        let c = b.center
        let p = pagePoint(fromView: handle, page: i)
        drag = .scale(center: c, d0: max(4, p.distance(to: c)), base: currentStrokes)
        dragMoved = false
        dragPage = i
    }

    /// Partial erase: cuts the touched part out of ink strokes with the preset's size.
    private func eraseAt(_ p: Point, page i: Int) {
        let r = max(2, style(for: .eraser).width / 2)
        let ctx = context(page: i)
        guard doc.strokes(at: ctx).contains(where: { $0.tool.kind == .ink && Hit.strokeTouches($0, point: p, radius: r) }) else { return }
        if eraseSnapshotPending { app.mutate(docID) { _ in }; eraseSnapshotPending = false }
        app.patch(docID) { $0.erase(at: p, radius: r, at: ctx) }
    }

    private func commit(_ strokeIn: Stroke, page i: Int) {
        var st = strokeIn
        if st.tool.kind == .highlight || st.tool.kind == .textMarkup {
            guard st.isTextAnchored else { app.flash(doc.pdfFile == nil ? "\(st.tool.label) works on PDF text" : "No text under the \(st.tool.label.lowercased())"); return }
        }
        if st.tool == .polyline || st.tool == .polygon {
            let simplified = Hit.simplify(st.points.map(\.point), tolerance: 6)
            st.points = simplified.map { StrokePoint($0.x, $0.y, 0.5) }
        }
        if st.tool.kind == .shape, st.points.count >= 2, st.tool != .polyline, st.tool != .polygon {
            let a = st.points[0], b = st.points[1]
            if abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2 { return }
        }
        if st.tool == .callout, st.points.count == 2 {
            // Leader: tip = drag start, text at drag end, elbow auto-placed on the side facing the tip.
            let tip = st.points[0].point, anchor = st.points[1].point
            let elbow = StrokeGeometry.defaultElbow(tip: tip, anchor: anchor, text: "", width: st.width)
            st.points = [st.points[0], StrokePoint(elbow.x, elbow.y), StrokePoint(anchor.x, anchor.y)]
            st.text = ""
            let tb = style(for: .textbox)
            st.background = tb.background; st.backgroundOpacity = tb.backgroundOpacity ?? 1
            st.borderColor = tb.borderColor ?? st.color; st.borderOpacity = tb.borderOpacity ?? 1; st.borderWidth = tb.borderWidth ?? 1.5
            st.font = tb.font; st.fontWeight = tb.fontWeight
            let author = app.author
            app.mutate(docID) { _ = $0.addStroke(st, at: self.context(page: i), author: author, session: nil) }
            session = nil
            editExisting(st, page: i)
            return
        }
        let author = app.author
        let sess = session
        var cid: ID? = nil
        app.mutate(docID) { cid = $0.addStroke(st, at: self.context(page: i), author: author, session: sess) }
        if type == .markup {
            // Ink strokes chain into one comment; the comment is not selected while you draw.
            if st.tool.kind == .ink { session = cid } else { session = nil }
            // A sticky note's content is its comment: open it for typing right away.
            if st.tool == .note, let cid {
                selection = [st.id]
                selectedComment = cid
                openAnnotationPopup()
                annotationFocusComment = true
            }
        }
    }

    private func tap(at p: Point, page i: Int) {
        let info = tool.info
        switch info.kind {
        case .place:
            if tool == .image || tool == .signature { app.flash("\(tool.info.label.components(separatedBy: " — ")[0]) works in PDF markups"); return }
            commit(newStroke(tool, at: p, pressure: 0.5, isPencil: false), page: i)
        case .text:
            beginTextEdit(at: p, page: i)
        case .stampGallery:
            var s = newStroke(.stamps, at: p, pressure: 0.5, isPencil: false)
            s.color = stamp.color; s.text = stamp.resolved(author: app.author)
            commit(s, page: i)
        case .stampPreset:
            var s = newStroke(tool, at: p, pressure: 0.5, isPencil: false)
            s.color = info.stampColor ?? "#FF3B30"
            s.text = tool == .datestamp ? "RECEIVED \(Formatting.shortDate(Date()))" : (tool == .initials ? Avatar.initials(app.author) + "." : info.stampText)
            commit(s, page: i)
        case .form:
            if let ft = info.fieldType { placeField(ft, at: p, page: i) }
        case .fill:
            let st = style(for: .fill)
            let strokes = doc.strokes(at: context(page: i))
            // Closed shapes, or pen strokes that close on themselves and contain the tap.
            let target = strokes.last { s in
                if s.tool.isShape { return StrokeGeometry.bounds(of: s).contains(p) }
                return Hit.isClosedInk(s) && Hit.polygon(s.points.map(\.point), contains: p)
            }
            if let target {
                app.mutate(docID) { $0.updateStrokes(ids: [target.id], at: self.context(page: i)) { $0.fill = st.color; $0.fillPattern = .solid; $0.fillOpacity = st.opacity ?? 0.5 } }
                app.flash("Filled")
            } else {
                app.flash("Tap inside a closed shape — drawn with a pen or a shape tool")
            }
        default:
            break
        }
    }

    // MARK: - Inline text editing

    func beginTextEdit(at p: Point, page i: Int) {
        commitTextEdit()
        textDraft = ""
        textEdit = TextEdit(page: i, anchor: p, existingID: nil, isLeader: false)
    }

    func editExisting(_ s: Stroke, page i: Int) {
        commitTextEdit()
        textDraft = s.text ?? ""
        let anchor = s.tool == .callout && s.points.count >= 3 ? s.points[2].point : s.anchor
        textEdit = TextEdit(page: i, anchor: anchor, existingID: s.id, isLeader: s.tool == .callout)
        selection = [s.id]
    }

    /// Commits the inline edit: new text box, updated text, or removal when the text is empty.
    func commitTextEdit() {
        guard let te = textEdit else { return }
        textEdit = nil
        let txt = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let ctx = context(page: te.page)
        if let id = te.existingID {
            if txt.isEmpty {
                app.mutate(docID) { $0.removeStrokes(ids: [id], at: ctx) }
                selection = []
            } else {
                app.mutate(docID) { d in
                    d.updateStrokes(ids: [id], at: ctx) { $0.text = txt }
                    if let cid = d.strokes(at: ctx).first(where: { $0.id == id })?.commentID { d.editComment(cid) { $0.text = txt } }
                }
            }
            return
        }
        guard !txt.isEmpty else { return }
        textPrompt = te.anchor
        textPromptPage = te.page
        textDraft = txt
        commitText()
    }

    func cancelTextEdit() {
        guard let te = textEdit else { return }
        textEdit = nil
        if let id = te.existingID, te.isLeader, (currentStrokes.first { $0.id == id }?.text ?? "").isEmpty {
            app.mutate(docID) { $0.removeStrokes(ids: [id], at: self.context(page: te.page)) }
        }
    }

    /// Style used by the inline editor (existing stroke or the current text-box preset).
    func textEditStyle() -> (fs: Double, color: String, bg: String?, bgo: Double, bc: String, bco: Double, bw: Double, font: String?, weight: TextWeight?) {
        if let te = textEdit, let id = te.existingID, let s = doc.strokes(at: context(page: te.page)).first(where: { $0.id == id }) {
            return (10 + (s.width ?? 6), s.color, s.background, s.backgroundOpacity ?? 1, s.borderColor ?? s.color, s.borderOpacity ?? 1, s.borderWidth ?? 0, s.font, s.fontWeight)
        }
        let st = style(for: .textbox)
        return (10 + st.width, st.color, st.background, st.backgroundOpacity ?? (type == .markup ? 1 : 0), st.borderColor ?? st.color, st.borderOpacity ?? 1,
                st.borderWidth ?? (type == .markup ? 1.5 : 0), st.font, st.fontWeight)
    }

    // MARK: - Leader handles

    func beginHandle(_ id: ID, index: Int) {
        app.mutate(docID) { _ in }
        handleDrag = (id, index)
    }
    func dragHandle(to v: CGPoint, page i: Int) {
        guard let h = handleDrag else { return }
        let p = pagePoint(fromView: v, page: i)
        app.patch(docID) { d in
            d.updateStrokes(ids: [h.id], at: self.context(page: i)) { s in
                if s.points.indices.contains(h.index) { s.points[h.index] = StrokePoint(p.x, p.y, 0.5) }
            }
        }
    }
    func endHandle() { handleDrag = nil }

    func commitText() {
        guard let p = textPrompt else { return }
        let txt = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        textPrompt = nil
        guard !txt.isEmpty else { return }
        let st = style(for: .textbox)
        var s = newStroke(.textbox, at: p, pressure: 0.5, isPencil: false)
        s.text = txt
        s.background = st.background; s.backgroundOpacity = st.backgroundOpacity ?? (type == .markup ? 1 : 0)
        s.borderColor = st.borderColor ?? st.color; s.borderOpacity = st.borderOpacity ?? 1; s.borderWidth = st.borderWidth ?? (type == .markup ? 1.5 : 0)
        s.font = st.font; s.fontWeight = st.fontWeight
        commit(s, page: textPromptPage)
    }

    // MARK: - Keyboard

    func handleKey(_ key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        let mod = modifiers.contains(.command)
        let ch = key.character
        if mod && ch == "z" { if modifiers.contains(.shift) { redo() } else { undo() }; return true }
        if mod && ch == "d" { duplicateSelection(); return true }
        if mod && ch == "a" { selectAll(); return true }
        if ch == KeyEquivalent.delete.character || ch == KeyEquivalent.deleteForward.character {
            if !selection.isEmpty { deleteSelection(); return true }
            return false
        }
        if ch == KeyEquivalent.escape.character { closeAllPopovers(); clearSelection(); organizeOpen = false; flatten = nil; return true }
        if !mod && ch == "v" { tool = .select; return true }
        if !mod && ch == "e" { tool = .eraser; return true }
        if type == .journal && journalView == .book {
            if ch == KeyEquivalent.rightArrow.character { nextPage(); return true }
            if ch == KeyEquivalent.leftArrow.character { prevPage(); return true }
        }
        return false
    }
}
