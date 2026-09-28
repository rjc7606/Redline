import SwiftUI
import RedlineCore

enum SideTab: String, CaseIterable, Hashable {
    case comments, forms, pages, layers, tags
    var label: String { rawValue.capitalized }
}

enum MarkupTab: Hashable {
    case favorites(Int)
    case tab(String)
}

enum WorkspacePopover: Equatable { case tray, stamps, export }
enum JournalView: String, CaseIterable { case book, calendar }
enum AuthorFilter: String, CaseIterable { case all = "All", mine = "Mine", others = "Others" }

struct CommentItem: Identifiable {
    var comment: Comment
    var pageIndex: Int
    var strokeCount: Int
    var id: ID { comment.id }
}

struct FlattenRequest: Equatable {
    /// nil → flatten all layers.
    var layerID: ID?
}

struct PointerSample {
    var location: CGPoint      // in the page's scaled view coordinates
    var pressure: Double
    var isPencil: Bool
}

/// Editing state for one open document (tool, page, zoom, selection, in-progress input).
@MainActor
@Observable
final class WorkspaceModel {
    unowned let app: AppModel
    let docID: ID

    var pageIndex = 0
    var tool: Tool
    var zoom: Double = Metrics.defaultZoom
    var pan: CGSize = .zero
    var sidebarOpen = true
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

    var presetsTool: Tool? = nil
    var styleExpanded = false
    var styleTarget: StylePreset.Target = .color
    var palettesExpanded = false
    var popover: WorkspacePopover? = nil
    var organizeOpen = false
    var stampText = "APPROVED"
    var stampColor = "#34C759"
    var rulerLock = false
    var flatten: FlattenRequest? = nil
    var textPrompt: Point? = nil
    var textPromptPage = 0
    var textDraft = ""
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
    var replyDraft = ""

    /// Set by the view from its width.
    var isCompact = false

    private enum Drag {
        case draw, marquee(Point), lasso, move(start: Point, base: [Stroke]), scale(center: Point, d0: Double, base: [Stroke]), erase, flip(x0: Double)
    }
    private var drag: Drag? = nil
    private var dragMoved = false
    /// Page index the in-progress pointer interaction belongs to (spreads draw on either page).
    var dragPage = 0

    init(app: AppModel, docID: ID) {
        self.app = app
        self.docID = docID
        let d = app.store.document(docID)!
        switch d.type {
        case .markup: tool = .select; sideTab = .comments
        case .drawing: tool = .pen; sideTab = .layers
        case .journal: tool = .pen; sideTab = .pages
        }
        if d.type == .drawing { activeLayer = d.pages.first?.layers.last?.id }
    }

    // MARK: - Document access

    var doc: Document { app.store.document(docID) ?? Document(type: .markup, name: "", pages: [.markup()]) }
    var type: DocumentType { doc.type }
    var canvas: Size { doc.canvasSize }
    var page: Page { doc.pages[min(pageIndex, doc.pages.count - 1)] }
    var pageCount: Int { doc.pages.count }

    var strokeContext: StrokeContext { StrokeContext(pageIndex: pageIndex, layerID: activeLayer) }
    func context(page i: Int) -> StrokeContext { StrokeContext(pageIndex: i, layerID: activeLayer) }

    /// Strokes the current tool acts on (active layer for drawings).
    var currentStrokes: [Stroke] { doc.strokes(at: strokeContext) }

    var canUndo: Bool { app.store.canUndo(docID) }
    var canRedo: Bool { app.store.canRedo(docID) }

    var sideTabs: [SideTab] {
        switch type { case .markup: [.comments, .forms, .pages]; case .drawing: [.layers, .pages]; case .journal: [.pages, .tags] }
    }
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
            return session != nil ? "Drawing session open — strokes group into one comment" : "Next ink stroke starts a new comment"
        case .drawing:
            return "Drawing on: " + (activeLayerObject?.name ?? "Base")
        case .journal:
            return rulerLock ? "Ruler lock: straight lines" : "Swipe with Select to flip pages"
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
    func zoomIn() { zoom = min(Metrics.maxZoom, ((zoom + 0.1) * 100).rounded() / 100) }
    func zoomOut() { zoom = max(Metrics.minZoom, ((zoom - 0.1) * 100).rounded() / 100) }
    func pinch(by factor: Double) { zoom = min(Metrics.maxZoom, max(Metrics.minZoom, zoom * factor)) }
    func panBy(_ d: CGSize) { pan = CGSize(width: pan.width + d.width, height: pan.height + d.height) }

    // MARK: - Tools

    func pick(_ t: Tool) {
        let info = t.info
        closePopovers()
        if info.kind == .flash { tool = t; app.flash(info.message ?? ""); return }
        if info.kind == .pageAction { rotatePage(at: pageIndex); return }
        if info.kind == .stampGallery {
            tool = .stamps
            popover = popover == .stamps ? nil : .stamps
            selection = []
            return
        }
        if tool == t {
            // Tapping the active tool deselects it (README).
            tool = type == .markup ? .select : .none
            session = nil
            return
        }
        let keepSession = t.isPen && (tool.isPen || tool == .eraser || tool == .none)
        tool = t
        if !keepSession { session = nil }
        if t != .select && t != .lasso { selection = []; selectedField = nil }
        if let h = ToolCatalog.pickHint(for: t, rulerLocked: rulerLock) { app.flash(h) }
    }

    func openPresets(_ t: Tool) {
        guard t.hasPresets else { return }
        tool = t
        presetsTool = t
        styleExpanded = false
        styleTarget = .color
        popover = nil
    }

    func closePopovers() {
        presetsTool = nil
        styleExpanded = false
        popover = nil
        layerMenu = nil
        tagPopoverPage = nil
    }

    func selectPreset(_ i: Int) {
        let t = styleTool
        if app.styles.selectedIndex(for: t) == i {
            styleExpanded.toggle()
        } else {
            app.styles.select(i, for: t)
            styleExpanded = false
        }
    }

    func updateStyle(_ body: (inout StylePreset) -> Void) {
        app.styles.update(styleTool, body)
    }

    func toggleRuler() {
        rulerLock.toggle()
        app.flash(rulerLock ? "Ruler lock on — strokes snap to straight lines" : "Ruler lock off")
    }

    // MARK: - Undo / pages

    func undo() { app.store.undo(docID); session = nil; selection = []; clampPage(); app.scheduleSave() }
    func redo() { app.store.redo(docID); session = nil; selection = []; clampPage(); app.scheduleSave() }
    private func clampPage() { pageIndex = min(pageIndex, max(0, pageCount - 1)) }

    func setPage(_ i: Int) {
        let n = max(0, min(pageCount - 1, i))
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
        guard pageCount > 1 else { app.flash("A document needs at least one page"); return }
        app.mutate(docID) { $0.deletePage(at: i) }
        clampPage()
        app.flash("Page deleted")
    }
    func duplicatePage(at i: Int) { app.mutate(docID) { $0.duplicatePage(at: i) }; app.flash("Page duplicated") }
    func rotatePage(at i: Int) { app.mutate(docID) { $0.rotatePage(at: i) }; app.flash("Page rotated 90°") }
    func movePage(from: Int, to: Int) {
        let curID = page.id
        app.mutate(docID) { $0.movePage(from: from, to: to) }
        if let i = doc.pageIndex(of: curID) { pageIndex = i }
    }
    func toggleBookmark() { app.mutate(docID) { $0.toggleBookmark(pageIndex: self.pageIndex) } }

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

    func clearSelection() { selection = []; selectedComment = nil; selectedField = nil }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let n = selection.count
        app.mutate(docID) { $0.removeStrokes(ids: self.selection, at: self.strokeContext) }
        selection = []
        app.flash(n > 1 ? "\(n) annotations deleted" : "Annotation deleted")
    }

    func duplicateSelection() {
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
        if type == .markup { sideTab = .forms }
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
        s.favorites.append(FavoritesTab(name: "★ \(s.favorites.count + 1)", pins: ["select"]))
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

    // MARK: - Pointer input (page-scaled view coordinates)

    private func newStroke(_ t: Tool, at p: Point, pressure: Double, isPencil: Bool) -> Stroke {
        let st = style(for: t)
        var s = Stroke(tool: t, color: st.color, points: [StrokePoint(p.x, p.y, isPencil ? pressure : 0.5)], width: st.width,
                       weight: (st.pressure ?? false) && isPencil ? .pressure : .constant, opacity: st.opacity, lineStyle: st.lineStyle)
        if t.isShape { s.fill = st.fill ?? st.color; s.fillPattern = st.fillPattern ?? .none; s.fillOpacity = st.fillOpacity ?? 0.5 }
        if t == .callout { s.fill = st.fill; s.fillPattern = st.fillPattern ?? .none; s.fillOpacity = st.fillOpacity ?? 0.5 }
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
        closePopovers()
        let info = tool.info
        if type == .drawing, info.isDrag || info.isTap, let L = activeLayerObject, L.locked || !L.visible {
            app.flash(L.locked ? "Active layer is locked" : "Active layer is hidden")
            drag = nil
            return
        }
        switch info.kind {
        case .none:
            if type == .journal && journalView == .book { drag = .flip(x0: Double(s.location.x)); flipDx = 0 } else { drag = nil }
        case .select, .lasso:
            if type == .markup, let f = page.fields.last(where: { $0.frame.contains(p) }), i == pageIndex {
                selectedField = f.id
                if f.type.isToggleLike { app.mutate(docID) { $0.editField(f.id, pageIndex: i) { $0.value = $0.isOn ? "" : "on" } } }
                if type == .markup { sideTab = .forms }
                drag = nil
                return
            }
            if i == pageIndex, let hit = topStroke(at: p, page: i) {
                if !selection.contains(hit.id) { selection = [hit.id]; selectedComment = hit.commentID }
                drag = .move(start: p, base: currentStrokes)
            } else if tool == .lasso {
                drag = .lasso; lasso = [p]
            } else if type == .journal && journalView == .book {
                drag = .flip(x0: Double(s.location.x)); flipDx = 0
            } else {
                drag = .marquee(p); marquee = nil
            }
        case .ink, .highlight, .textMarkup, .shape:
            live = newStroke(tool, at: p, pressure: s.pressure, isPencil: s.isPencil)
            drag = .draw
            selection = []
        case .eraser:
            eraseHits = []
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
                if rulerLock {
                    let a = st.points[0]
                    let snapped = snapAngle(from: Point(a.x, a.y), to: p)
                    st.points = [a, StrokePoint(snapped.x, snapped.y, pt.p)]
                } else {
                    st.points.append(pt)
                }
            case .highlight, .textMarkup:
                st.points = [st.points[0], StrokePoint(p.x, st.points[0].y, 0.5)]
            case .shape:
                if st.tool == .polyline || st.tool == .polygon { st.points.append(pt) } else { st.points = [st.points[0], pt] }
            default: break
            }
            live = st
        case .marquee(let start):
            dragMoved = true
            marquee = Rect.from(start, p)
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
            flipDx = Double(s.location.x) - x0
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
            marquee = nil
            if let r, dragMoved {
                selection = Set(doc.strokes(at: context(page: i)).filter { r.contains(StrokeGeometry.bounds(of: $0).center) }.map(\.id))
                if !selection.isEmpty { app.flash("\(selection.count) selected") }
            } else {
                clearSelection()
            }
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
            break
        case .erase:
            let hits = eraseHits
            eraseHits = []
            if !hits.isEmpty {
                app.mutate(docID) { $0.removeStrokes(ids: hits, at: self.context(page: i)) }
                app.flash(hits.count == 1 ? "Annotation erased" : "\(hits.count) annotations erased")
            }
        case .flip:
            let dx = flipDx
            flipDx = 0
            let g = book
            let threshold = canvas.w * zoom * 0.3
            if dx < -threshold { if g.nextExists { setPage(g.nextIndex) } else if dx < -threshold * 1.8 { addJournalPage() } }
            else if dx > threshold, g.canBack { setPage(g.prevIndex) }
        }
    }

    func pointerCancel() {
        if case .flip = drag { flipDx = 0 }
        drag = nil
        live = nil
        lasso = nil
        marquee = nil
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

    private func snapAngle(from a: Point, to b: Point) -> Point {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return b }
        let ang = atan2(dy, dx)
        let snapped = (ang / (.pi / 4)).rounded() * (.pi / 4)
        return Point(a.x + cos(snapped) * len, a.y + sin(snapped) * len)
    }

    private func eraseAt(_ p: Point, page i: Int) {
        let r = max(6, 12 / zoom)
        for s in doc.strokes(at: context(page: i)) where !eraseHits.contains(s.id) {
            if Hit.strokeTouches(s, point: p, radius: r) { eraseHits.insert(s.id) }
        }
    }

    private func commit(_ strokeIn: Stroke, page i: Int) {
        var st = strokeIn
        if st.tool == .polyline || st.tool == .polygon {
            let simplified = Hit.simplify(st.points.map(\.point), tolerance: 6)
            st.points = simplified.map { StrokePoint($0.x, $0.y, 0.5) }
        }
        if st.tool.kind == .shape, st.points.count >= 2, st.tool != .polyline, st.tool != .polygon {
            let a = st.points[0], b = st.points[1]
            if abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2 { return }
        }
        let author = app.author
        let sess = session
        var cid: ID? = nil
        app.mutate(docID) { cid = $0.addStroke(st, at: self.context(page: i), author: author, session: sess) }
        if type == .markup {
            if st.tool.kind == .ink { session = cid } else { session = nil }
            selectedComment = cid
        }
    }

    private func tap(at p: Point, page i: Int) {
        let info = tool.info
        switch info.kind {
        case .place:
            commit(newStroke(tool, at: p, pressure: 0.5, isPencil: false), page: i)
        case .text:
            textPrompt = p
            textPromptPage = i
            textDraft = ""
            textAlertVisible = true
        case .stampGallery:
            var s = newStroke(.stamps, at: p, pressure: 0.5, isPencil: false)
            s.color = stampColor; s.text = stampText
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
            if let target = doc.strokes(at: context(page: i)).last(where: { $0.tool.isShape && StrokeGeometry.bounds(of: $0).contains(p) }) {
                app.mutate(docID) { $0.updateStrokes(ids: [target.id], at: self.context(page: i)) { $0.fill = st.color; $0.fillPattern = .solid; $0.fillOpacity = st.opacity ?? 0.5 } }
                app.flash("Shape filled")
            } else {
                app.flash("Bucket fill works on closed shapes — rectangle, ellipse, polygon, cloud")
            }
        default:
            break
        }
    }

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
        if ch == KeyEquivalent.escape.character { closePopovers(); clearSelection(); organizeOpen = false; flatten = nil; return true }
        if !mod && ch == "v" { tool = .select; return true }
        if !mod && ch == "e" { tool = .eraser; return true }
        if type == .journal && journalView == .book {
            if ch == KeyEquivalent.rightArrow.character { nextPage(); return true }
            if ch == KeyEquivalent.leftArrow.character { prevPage(); return true }
        }
        return false
    }
}
