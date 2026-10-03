import SwiftUI
import PDFKit
import RedlineCore

/// In-progress stroke drawn by the overlay (page space).
struct LiveMark {
    var page: PDFPage
    var tool: Tool
    var points: [CGPoint]
    var quads: [CGRect] = []
    var color: UIColor
    var width: CGFloat
    var opacity: CGFloat
}

struct PDFTextEdit {
    var annotation: PDFAnnotation
    var page: PDFPage
    var isNew: Bool
}

/// One sidebar row / popup subject: a primary annotation with its replies and review state.
struct MarkupComment: Identifiable {
    var id: String
    var annotation: PDFAnnotation
    var pageIndex: Int
    var tool: Tool
    var author: String
    var time: Date
    var text: String
    var replies: [(author: String, time: Date, text: String)]
    var status: CommentStatus
    var colorHex: String
    var markCount: Int
}

/// PDFKit-backed markup state (Markups only). Stored on WorkspaceModel as `mk`.
@MainActor
@Observable
final class MarkupState {
    var pdf: PDFDocument?
    @ObservationIgnored weak var pdfView: PDFStackView?
    var selected: [PDFAnnotation] = []
    var activeInk: PDFAnnotation? = nil
    /// First Ink annotation of the current pen chain (group parent when colours change mid-chain).
    var activeInkRoot: PDFAnnotation? = nil
    var live: LiveMark? = nil
    var lasso: [CGPoint] = []
    var marquee: CGRect? = nil
    var lassoPage: PDFPage? = nil
    var textEdit: PDFTextEdit? = nil
    var textDraft = ""
    var annotationPopup = false
    var annotationProps = false
    var focusComment = false
    var replyDraft = ""
    /// Popup: the reply field shows only after tapping Reply.
    var replyFieldOpen = false
    /// Selection bar: the Properties editor dropped under it.
    var selectionProps = false
    /// Comments sidebar: the expanded row (stable id) and whether its text is being edited.
    var expandedComment: String? = nil
    var editingComment = false
    var undoStack: [PDFCommand] = []
    var redoStack: [PDFCommand] = []
    /// Bumped whenever the overlay must redraw (live stroke, selection, ruler…).
    var renderTick = 0
    /// Bumped when the PDFView scrolled / zoomed (SwiftUI overlays re-anchor).
    var viewportTick = 0
    var scrollToPage: Int? = nil
    var dirty = false
    @ObservationIgnored var saveTask: Task<Void, Never>? = nil
    @ObservationIgnored var styleSnapshotTaken = false
    @ObservationIgnored var eraseSnapshotTaken = false
    /// One eraser drag: snapshots taken BEFORE the first cut, strokes removed along the way, last point (throttle).
    @ObservationIgnored var eraseSnaps: [(PDFAnnotation, AnnotationSnapshot)] = []
    @ObservationIgnored var eraseRemoved: [PDFAnnotation] = []
    @ObservationIgnored var eraseChanged = false
    @ObservationIgnored var lastErasePoint: CGPoint? = nil
    /// When the file was last written; appearance streams are rebuilt only for annotations modified since.
    @ObservationIgnored var lastSaveDate: Date? = nil
    @ObservationIgnored var pendingTextEdit: PDFAnnotation? = nil
    /// Snapshot taken when a text edit starts (undo for the whole edit).
    @ObservationIgnored var textEditSnapshot: AnnotationSnapshot? = nil
    /// A tap that only closed the inline text editor places nothing.
    @ObservationIgnored var swallowTap = false
    /// Keyboard height overlapping the PDF view (popup placement).
    var keyboardOverlap: CGFloat = 0
    /// Polyline being placed point by point.
    var polyPoints: [CGPoint] = []
    var polyPage: PDFPage? = nil
    /// Eraser outline while erasing (page space).
    var eraserPoint: CGPoint? = nil
    var eraserPage: PDFPage? = nil
    /// `mkComments()` result for the current render tick and filter (rebuilding it per view body was seconds on busy pages).
    @ObservationIgnored var commentsCache: (tick: Int, filter: AuthorFilter, items: [MarkupComment])? = nil

    var selectedPrimary: PDFAnnotation? { selected.first { $0.isPrimary } ?? selected.first }
    var pageCount: Int { pdf?.pageCount ?? 0 }
    func page(_ i: Int) -> PDFPage? { pdf?.page(at: i) }
    func index(of page: PDFPage) -> Int { pdf?.index(for: page) ?? 0 }
}

extension WorkspaceModel {
    var isPDF: Bool { type == .markup && mk.pdf != nil }

    // MARK: - Setup / save

    func mkLoad() {
        guard type == .markup, let f = doc.pdfFile else { return }
        mk.pdf = app.pdf.document(f)   // rendered exactly as saved; nothing is rewritten on load
    }

    func mkMarkDirty() {
        mk.dirty = true
        mk.renderTick += 1
        mk.saveTask?.cancel()
        mk.saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.mkSaveNow()
        }
    }

    func mkSaveNow() {
        guard mk.dirty, let f = doc.pdfFile, let pdf = mk.pdf else { return }
        mk.dirty = false
        let url = app.pdf.url(for: f)
        var ours: [PDFAnnotation] = []
        let since = mk.lastSaveDate?.addingTimeInterval(-2)
        for i in 0..<pdf.pageCount {
            guard let p = pdf.page(at: i) else { continue }
            for a in p.annotations where a.isRedlineTextBox || a.isRedlineNote || a.isRedlinePolygon || a.isRedlineLine || a.isRedlineMarkup || a.isRedlineInk || WidgetRenderer.wantsAppearance(a) {
                // Untouched annotations keep the stream PDFKit carries over from the last save.
                let fresh = since.map { (a.modificationDate ?? .distantFuture) >= $0 } ?? true
                if fresh || a.value(forAnnotationKey: .appearanceDictionary) == nil { ours.append(a) }
            }
        }
        // The file may live anywhere in Files (opened in place), so the write is coordinated.
        var ok = false
        var coordError: NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            ok = pdf.write(to: u)
            // PDFKit can't write appearance streams: attach ours in an incremental update.
            if ok { AppearancePatcher.patch(fileURL: u, annotations: ours) }
        }
        if ok {
            mk.lastSaveDate = Date()
            app.pdf.invalidateImages(f)
            app.patch(docID) { $0.modified = Date() }
        } else {
            app.flash("Couldn't save the PDF")
        }
    }

    // MARK: - Undo

    private func mkApply(_ cmd: PDFCommand, reverse: Bool) {
        switch cmd {
        case .add(let page, let annots):
            if reverse { annots.forEach { page.removeAnnotation($0) } } else { annots.forEach { page.addAnnotation($0) } }
        case .remove(let page, let annots):
            if reverse { annots.forEach { page.addAnnotation($0) } } else { annots.forEach { page.removeAnnotation($0) } }
        case .change(let pairs):
            for (a, snap) in pairs { snap.restore(to: a) }
        case .group(let cmds):
            for c in (reverse ? cmds.reversed() : cmds) { mkApply(c, reverse: reverse) }
        }
    }

    /// Records and performs an edit (for `.change`, pass the *before* snapshots; the change itself is already applied).
    func mkPerform(_ cmd: PDFCommand, alreadyApplied: Bool = false) {
        if !alreadyApplied { mkApply(cmd, reverse: false) }
        mk.undoStack.append(cmd)
        if mk.undoStack.count > 100 { mk.undoStack.removeFirst() }
        mk.redoStack.removeAll()
        mkMarkDirty()
    }

    private func mkInverse(_ cmd: PDFCommand) -> PDFCommand {
        switch cmd {
        case .add(let p, let a): return .remove(page: p, annots: a)
        case .remove(let p, let a): return .add(page: p, annots: a)
        case .change(let pairs): return .change(annots: pairs.map { ($0.0, AnnotationSnapshot($0.0)) })
        case .group(let cmds): return .group(cmds.reversed().map { mkInverse($0) })
        }
    }

    func mkUndo() {
        guard let cmd = mk.undoStack.popLast() else { return }
        let inverse = mkInverse(cmd)
        mkApply(cmd, reverse: true)
        mk.redoStack.append(inverse)
        mkClearSelection()
        mkMarkDirty()
    }

    func mkRedo() {
        guard let cmd = mk.redoStack.popLast() else { return }
        let inverse = mkInverse(cmd)
        mkApply(cmd, reverse: true)
        mk.undoStack.append(inverse)
        mkClearSelection()
        mkMarkDirty()
    }

    // MARK: - Selection

    /// Every annotation that belongs with `a` (callout box + leader share a group id).
    func mkGroup(of a: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        guard let gid = a.value(forAnnotationKey: .redlineGroup) as? String else { return [a] }
        return page.annotations.filter { ($0.value(forAnnotationKey: .redlineGroup) as? String) == gid }
    }

    /// Highlights, underlines, strikeouts and squiggles are anchored to the page text: never moved or resized.
    func mkIsLocked(_ a: PDFAnnotation) -> Bool { ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(a.subtype) }
    /// The selected annotations that may move / resize.
    var mkMovableSelection: [PDFAnnotation] { mk.selected.filter { !mkIsLocked($0) } }

    /// Our own hit test (PDFKit's ignores grouped children and uses loose bounds): topmost annotation under `p`,
    /// and for Ink the index of the path that was actually touched.
    func mkAnnotation(at p: CGPoint, page: PDFPage) -> (annotation: PDFAnnotation, pathIndex: Int?)? {
        let z = mkZoom
        for a in page.annotations.reversed() where !a.isLink && !a.isPopup && !a.isReply && !a.isStateAnnotation {
            if a.subtype == "Ink" {
                let tol = Double((a.border?.lineWidth ?? 2) / 2 + 8 / z)
                let q = Point(p.x, p.y)
                for (i, path) in AnnotationFactory.inkPaths(a).enumerated() {
                    if path.count == 1, hypot(path[0].x - p.x, path[0].y - p.y) <= tol { return (a, i) }
                    for k in 1..<max(1, path.count) where Hit.distance(q, toSegment: Point(path[k - 1].x, path[k - 1].y), Point(path[k].x, path[k].y)) <= tol { return (a, i) }
                }
            } else if a.subtype == "Polygon" {
                if Hit.polygon(a.polygonVertices.map { Point($0.x, $0.y) }, contains: Point(p.x, p.y)) { return (a, nil) }
            } else {
                // Small annotations (sticky notes) get at least a 36-screen-point hit box.
                let pad = max(4 / z, (36 / z - min(a.bounds.width, a.bounds.height)) / 2)
                if a.bounds.insetBy(dx: -pad, dy: -pad).contains(p) { return (a, nil) }
            }
        }
        return nil
    }

    /// Selects what's under `p`. With `splitStrokes`, one stroke of a multi-stroke pen annotation is pulled out
    /// into its own annotation and selected alone (so it can be moved by itself).
    @discardableResult
    func mkSelectHit(at p: CGPoint, page: PDFPage, splitStrokes: Bool) -> Bool {
        guard let hit = mkAnnotation(at: p, page: page) else { return false }
        let a = hit.annotation
        if splitStrokes, let idx = hit.pathIndex, a.subtype == "Ink", a.redlineTool.isPen || a.redlineTool == .signature,
           AnnotationFactory.inkPaths(a).count > 1 {
            let single = mkExtractPaths([idx], from: a, page: page)
            mkSelect(single, on: page)
        } else {
            mkSelect(a, on: page)
        }
        return true
    }

    /// Moves the given paths of an Ink annotation into a new annotation with the same style (undoable).
    func mkExtractPaths(_ indices: [Int], from a: PDFAnnotation, page: PDFPage) -> PDFAnnotation {
        let all = AnnotationFactory.inkPaths(a)
        let taken = indices.compactMap { all.indices.contains($0) ? all[$0] : nil }
        let kept = all.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        let new = AnnotationFactory.ink(paths: taken, tool: a.redlineTool, style: WorkspaceModel.preset(of: a), author: (a.userName ?? "").isEmpty ? app.author : a.userName!)
        mkPerform(.change(annots: [(a, AnnotationSnapshot(a))]), alreadyApplied: true)
        AnnotationFactory.setInkPaths(a, kept)
        mkPerform(.add(page: page, annots: [new]))
        return new
    }

    func mkSelect(_ a: PDFAnnotation, on page: PDFPage) {
        mk.selected = AppearancePatcher.promote(mkGroup(of: a, on: page), on: page)
        mk.annotationPopup = false
        mk.annotationProps = false
        mk.replyFieldOpen = false
        mk.selectionProps = false
        mk.styleSnapshotTaken = false
        mk.replyDraft = ""
        mk.renderTick += 1
    }

    func mkClearSelection() {
        mk.selected = []
        mk.annotationPopup = false
        mk.annotationProps = false
        mk.selectionProps = false
        mk.styleSnapshotTaken = false
        mk.renderTick += 1
    }

    func mkSelectComment(_ c: MarkupComment) {
        if let i = mk.pdf.map({ $0.index(for: c.annotation.page ?? PDFPage()) }) { setPage(i) }
        if let page = c.annotation.page { mkSelect(c.annotation, on: page) }
    }

    func mkDeleteSelection() {
        guard let page = mk.selected.first?.page, !mk.selected.isEmpty else { return }
        var all = mk.selected
        for a in mk.selected { all.append(contentsOf: mkChildren(of: a, on: page)) }
        mkPerform(.remove(page: page, annots: all))
        mkClearSelection()
        app.flash("Annotation deleted")
    }

    /// Replies and review-state annotations attached to `a`.
    func mkChildren(of a: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { ($0.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation) === a }
    }

    var mkSelectionBounds: CGRect? {
        guard !mk.selected.isEmpty else { return nil }
        var r = mk.selected[0].bounds
        for a in mk.selected.dropFirst() { r = r.union(a.bounds) }
        return r
    }

    // MARK: - Comments

    func mkComments() -> [MarkupComment] {
        if let c = mk.commentsCache, c.tick == mk.renderTick, c.filter == authorFilter { return c.items }
        guard let pdf = mk.pdf else { return [] }
        var out: [MarkupComment] = []
        let me = app.author
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let annots = page.annotations
            // One pass: replies and review states by parent, group members by group id.
            var replies: [ObjectIdentifier: [PDFAnnotation]] = [:]
            var states: [ObjectIdentifier: [PDFAnnotation]] = [:]
            var groups: [String: [PDFAnnotation]] = [:]
            for a in annots {
                if let parent = a.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation {
                    if a.isReply { replies[ObjectIdentifier(parent), default: []].append(a) }
                    else if a.isStateAnnotation { states[ObjectIdentifier(parent), default: []].append(a) }
                }
                if let gid = a.value(forAnnotationKey: .redlineGroup) as? String { groups[gid, default: []].append(a) }
            }
            for a in annots where a.isPrimary && !a.isWidget {
                let author = (a.userName ?? "").isEmpty ? "Unknown" : a.userName!
                switch authorFilter {
                case .all: break
                case .mine: if author != me { continue }
                case .others: if author == me { continue }
                }
                let key = ObjectIdentifier(a)
                let rs = (replies[key] ?? []).sorted { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
                    .map { (author: ($0.userName ?? "").isEmpty ? "Unknown" : $0.userName!, time: $0.modificationDate ?? Date(), text: $0.contents ?? "") }
                let st = (states[key] ?? []).sorted { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
                let status = st.last.flatMap { AnnotationFactory.status(fromState: $0.value(forAnnotationKey: .state) as? String) } ?? .open
                let group = (a.value(forAnnotationKey: .redlineGroup) as? String).flatMap { groups[$0] } ?? [a]
                let tool = a.redlineTool
                let text = tool.isTextual ? "" : (a.contents ?? "")
                let strokes = group.filter { $0.subtype == "Ink" }.reduce(0) { $0 + max(1, $1.paths?.count ?? 1) }
                out.append(MarkupComment(id: a.stableID, annotation: a, pageIndex: i, tool: tool, author: author, time: a.modificationDate ?? Date(),
                                         text: text, replies: rs, status: status, colorHex: PDFColors.hex(a.color),
                                         markCount: a.subtype == "Ink" ? strokes : group.count))
            }
        }
        let sorted = out.sorted { $0.pageIndex != $1.pageIndex ? $0.pageIndex < $1.pageIndex : $0.time > $1.time }
        mk.commentsCache = (mk.renderTick, authorFilter, sorted)
        return sorted
    }

    func mkSetText(_ a: PDFAnnotation, _ text: String) {
        a.contents = text
        a.modificationDate = Date()
        if a.redlineTool.isTextual, let page = a.page {
            // Text boxes: the text is what's drawn, so refit the box and redraw its appearance.
            mkFitTextBox(a, text: text)
            if a.redlineTool == .callout { mkRelayoutLeader(for: a, on: page) }
            mk.renderTick += 1
        }
        mkMarkDirty()
    }

    func mkAddReply(_ a: PDFAnnotation) {
        let t = mk.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let page = a.page else { return }
        mkPerform(.add(page: page, annots: [AnnotationFactory.reply(to: a, text: t, author: app.author)]))
        mk.replyDraft = ""
    }

    func mkSetStatus(_ a: PDFAnnotation, _ s: CommentStatus) {
        guard let page = a.page else { return }
        mkPerform(.add(page: page, annots: [AnnotationFactory.stateAnnotation(for: a, status: s, author: app.author)]))
    }

    /// Parents that have at least one reply on this page (one pass; pair with `mkHasComment(_:replied:)`).
    func mkRepliedParents(on page: PDFPage) -> Set<ObjectIdentifier> {
        var set = Set<ObjectIdentifier>()
        for a in page.annotations where a.isReply {
            if let parent = a.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation { set.insert(ObjectIdentifier(parent)) }
        }
        return set
    }

    /// Whether an annotation carries comment text or replies (drives the badge).
    func mkHasComment(_ a: PDFAnnotation, replied: Set<ObjectIdentifier>) -> Bool {
        if a.redlineTool == .note || a.subtype == "Text" { return false }   // a sticky note IS the comment
        if !a.redlineTool.isTextual, !(a.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return replied.contains(ObjectIdentifier(a))
    }

    func mkHasComment(_ a: PDFAnnotation, on page: PDFPage) -> Bool {
        mkHasComment(a, replied: mkRepliedParents(on: page))
    }

    // MARK: - Style of the selection

    static func preset(of a: PDFAnnotation) -> StylePreset {
        let tool = a.redlineTool
        let w = Double(a.border?.lineWidth ?? 2)
        var p = StylePreset(color: PDFColors.hex(a.color), width: w, opacity: a.opacityValue)
        if a.subtype == "FreeText" {
            p.color = PDFColors.hex(a.fontColor ?? .black)
            p.width = max(1, Double(a.font?.pointSize ?? 16) - 10)
            p.borderColor = a.borderColorHex ?? PDFColors.hex(a.fontColor ?? .black); p.borderOpacity = 1; p.borderWidth = w
            var al: CGFloat = 0
            a.color.getWhite(nil, alpha: &al)
            if al > 0.01 { p.background = PDFColors.hex(a.color); p.backgroundOpacity = Double(al) } else { p.background = "#FFFFFF"; p.backgroundOpacity = 0 }
            if let f = a.font {
                let system = UIFont.systemFont(ofSize: 10).familyName
                p.font = (f.familyName == system || f.familyName.hasPrefix(RedlineFonts.family)) ? nil : f.familyName
                p.fontWeight = f.fontDescriptor.symbolicTraits.contains(.traitBold) || f.fontName.lowercased().contains("bold") ? .bold : .semibold
            }
        }
        if a.subtype == "Square" || a.subtype == "Circle" {
            if let ic = a.interiorColor { p.fill = PDFColors.hex(ic); p.fillPattern = .solid; var al: CGFloat = 1; ic.getWhite(nil, alpha: &al); p.fillOpacity = Double(al) } else { p.fillPattern = FillPattern.none }
        }
        if a.border?.style == .dashed { p.lineStyle = .dash }
        _ = tool
        return p
    }

    static func apply(_ p: StylePreset, to a: PDFAnnotation) {
        if a.subtype == "FreeText" {
            a.fontColor = PDFColors.uiColor(p.color)
            a.font = AnnotationFactory.fontFor(p, size: CGFloat(10 + p.width))
            let bgAlpha = p.backgroundOpacity ?? 1
            a.color = (p.background != nil && bgAlpha > 0) ? PDFColors.uiColor(p.background!, alpha: bgAlpha) : UIColor.clear
            a.interiorColor = nil
            let b = PDFBorder(); b.lineWidth = CGFloat(p.borderWidth ?? 1); a.border = b
            a.borderColorHex = p.borderColor ?? p.color
        } else {
            a.color = PDFColors.uiColor(p.color)
            let b = PDFBorder()
            b.lineWidth = CGFloat(p.width)
            b.style = p.lineStyle == .dash ? .dashed : .solid
            if p.lineStyle == .dash { b.dashPattern = [NSNumber(value: p.width * 3), NSNumber(value: p.width * 2)] }
            a.border = b
            if a.subtype == "Square" || a.subtype == "Circle" {
                if let fp = p.fillPattern, fp != FillPattern.none { a.interiorColor = PDFColors.uiColor(p.fill ?? p.color, alpha: p.fillOpacity ?? 0.5) } else { a.interiorColor = nil }
            }
        }
        a.opacityValue = p.opacity ?? 1
        a.modificationDate = Date()
        a.dropAppearance()
    }

    func mkSelectedPreset() -> StylePreset? { mk.selectedPrimary.map { WorkspaceModel.preset(of: $0) } }
    var mkSelectedTool: Tool? { mk.selectedPrimary?.redlineTool }

    func mkUpdateSelectedStyle(_ body: (inout StylePreset) -> Void) {
        let targets = mk.selected.filter { !$0.isWidget }
        guard !targets.isEmpty else { return }
        if !mk.styleSnapshotTaken {
            mkPerform(.change(annots: targets.map { ($0, AnnotationSnapshot($0)) }), alreadyApplied: true)
            mk.styleSnapshotTaken = true
        }
        for a in targets {
            var p = WorkspaceModel.preset(of: a)
            body(&p)
            WorkspaceModel.apply(p, to: a)
        }
        mkMarkDirty()
    }

    // MARK: - Pages

    func mkRotatePage(_ i: Int) { guard let p = mk.page(i) else { return }; p.rotation = (p.rotation + 90) % 360; mkMarkDirty(); app.flash("Page rotated 90°") }
    func mkDeletePage(_ i: Int) {
        guard let pdf = mk.pdf, pdf.pageCount > 1 else { app.flash("A document needs at least one page"); return }
        pdf.removePage(at: i)
        pageIndex = min(pageIndex, pdf.pageCount - 1)
        mk.undoStack.removeAll(); mk.redoStack.removeAll()
        mkClearSelection(); mkMarkDirty(); app.flash("Page deleted")
    }
    func mkDuplicatePage(_ i: Int) {
        guard let pdf = mk.pdf, let p = mk.page(i), let copy = p.copy() as? PDFPage else { return }
        pdf.insert(copy, at: i + 1)
        mkMarkDirty(); app.flash("Page duplicated")
    }
    func mkMovePage(from: Int, to: Int) {
        guard let pdf = mk.pdf, from != to, let p = mk.page(from) else { return }
        pdf.removePage(at: from)
        pdf.insert(p, at: to)
        pageIndex = to
        mkMarkDirty()
    }
    func mkInsertBlankPage(after i: Int) {
        guard let pdf = mk.pdf else { return }
        let ref = mk.page(min(i, pdf.pageCount - 1))
        let size = ref.map { PDFService.displaySize($0) } ?? CGSize(width: 612, height: 792)
        guard let page = AppModel.blankPage(size: size, template: .blank, paper: .white) else { return }
        pdf.insert(page, at: i + 1)
        pageIndex = i + 1
        mkMarkDirty(); app.flash("Blank page inserted")
    }

    // MARK: - Export

    /// Writes the annotated PDF and returns its file URL (Share / Save to Files).
    func mkAnnotatedURL() -> URL? {
        mkSaveNow()
        guard let f = doc.pdfFile else { return nil }
        return app.pdf.url(for: f)
    }

    /// Flattened copy: pages rendered with their annotations burned in.
    func mkFlattenedData() -> Data? {
        guard let pdf = mk.pdf, pdf.pageCount > 0 else { return nil }
        let first = PDFService.displaySize(pdf.page(at: 0)!)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first))
        return renderer.pdfData { c in
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let size = PDFService.displaySize(page)
                c.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                let cg = c.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                PDFDraw.page(page, in: cg)
                cg.restoreGState()
            }
        }
    }
}

// MARK: - Pointer handling (page space, y up)

extension WorkspaceModel {
    private var mkRulerLength: CGFloat { 820 * mkRulerScale }
    private var mkRulerHeight: CGFloat { 72 * mkRulerScale }
    /// The ruler is sized relative to the page (page width ≈ 1000 canvas units).
    private var mkRulerScale: CGFloat {
        guard let p = mk.page(pageIndex) else { return 0.6 }
        return PDFService.displaySize(p).width / 1000
    }
    private func mkRulerAxes() -> (c: CGPoint, d: CGPoint, n: CGPoint) {
        let a = ruler.angle * .pi / 180
        return (CGPoint(x: ruler.x, y: ruler.y), CGPoint(x: cos(a), y: -sin(a)), CGPoint(x: sin(a), y: cos(a)))
    }

    private enum RulerPart { case body, handle, lock }
    private func mkRulerHit(_ p: CGPoint) -> RulerPart? {
        guard ruler.on else { return nil }
        let A = mkRulerAxes()
        let vx = p.x - A.c.x, vy = p.y - A.c.y
        let along = vx * A.d.x + vy * A.d.y, across = vx * A.n.x + vy * A.n.y
        let halfL = mkRulerLength / 2, halfH = mkRulerHeight / 2
        guard abs(along) <= halfL, abs(across) <= halfH else { return nil }
        let z = CGFloat(mkZoom)
        if abs(abs(along) - (halfL - 30 / z)) <= 22 / z && abs(across) <= 22 / z { return .handle }
        if abs(along) <= 72 / z && abs(across) <= 16 / z { return .lock }
        return .body
    }

    var mkZoom: Double { Double(mk.pdfView?.scaleFactor ?? 1) }

    func mkToggleRuler() {
        ruler.on.toggle()
        if ruler.on, let p = mk.page(pageIndex) {
            let s = PDFService.displaySize(p)
            ruler.x = s.width / 2; ruler.y = s.height / 2; ruler.angle = 0
            app.flash("Drag the ruler to move · turn the end handles to rotate")
        } else { app.flash("Ruler hidden") }
        mk.renderTick += 1
    }

    func mkPointerDown(_ s: PointerSample, page: PDFPage, at p: CGPoint) {
        let i = mk.index(of: page)
        if i != pageIndex { pageIndex = i; mk.activeInk = nil; mk.activeInkRoot = nil }
        let wasEditing = mk.textEdit != nil
        mkCommitTextEdit()
        closePopovers()
        mkDragMoved = false
        mk.swallowTap = false
        let info = tool.info
        if wasEditing {
            // Tapping outside the inline editor only closes it.
            mkClearSelection(); selectedField = nil
            mk.swallowTap = true
            mkDrag = .pan
            return
        }
        if mk.annotationPopup {
            // Tapping outside the comment popup only closes it (no sticky note, stamp or text box gets placed).
            mkClosePopup()
            mk.swallowTap = true
            mkDrag = .pan
            mk.renderTick += 1
            return
        }
        // A finger on something already selected moves it (any tool) instead of panning.
        if !s.isPencil, !mk.selected.isEmpty, let a = mkAnnotation(at: p, page: page)?.annotation, mk.selected.contains(where: { $0 === a }) {
            let movable = mkMovableSelection
            if movable.isEmpty { mkDrag = .pan; return }   // a highlight stays with its text
            mkDrag = .move(start: p, snaps: movable.map { ($0, AnnotationSnapshot($0)) }, boxOnly: mkIsCalloutBox(a))
            mk.pendingTextEdit = (a.subtype == "FreeText") ? a : nil
            return
        }
        if info.kind != .select && info.kind != .lasso { mkClearSelection(); selectedField = nil }
        // Finger or Pencil on the ruler: move / rotate / lock.
        if let hit = mkRulerHit(p) {
            switch hit {
            case .body: mkDrag = .rulerMove(start: p, base: CGPoint(x: ruler.x, y: ruler.y))
            case .handle: mkDrag = .rulerRotate(a0: atan2(-(p.y - ruler.y), p.x - ruler.x) * 180 / .pi, r0: ruler.angle)
            case .lock: mkDrag = .rulerTap
            }
            return
        }
        let fingerBlocked = !s.isPencil && info.kind == .ink && !mkFingerMayInk(deciding: false)
        if s.isPencil, info.kind == .ink { _ = mkFingerMayInk(deciding: true) }
        let fingerTapTool = !s.isPencil && (info.isTap || info.kind == .fill)
        if info.kind == .none || fingerBlocked || fingerTapTool {
            mk.activeInk = nil; mk.activeInkRoot = nil
            mkDrag = .pan
            return
        }
        switch info.kind {
        case .select, .lasso:
            if let a = mkAnnotation(at: p, page: page)?.annotation {
                if mk.selected.contains(where: { $0 === a }) {
                    let movable = mkMovableSelection
                    if movable.isEmpty { mkDrag = nil; return }
                    mkDrag = .move(start: p, snaps: movable.map { ($0, AnnotationSnapshot($0)) }, boxOnly: mkIsCalloutBox(a))
                    mk.pendingTextEdit = (a.subtype == "FreeText") ? a : nil
                } else {
                    mkSelectHit(at: p, page: page, splitStrokes: true)
                    mkDrag = nil
                }
            } else {
                mkDrag = .marquee(start: p)
                mk.marquee = nil; mk.lasso = [p]; mk.lassoPage = page; mkLassoMode = false
                mk.renderTick += 1
            }
        case .ink, .highlight, .textMarkup, .shape:
            if tool == .polyline { mkDrag = .polyTap(start: p); return }
            let st = style(for: tool)
            var color = PDFColors.uiColor(st.color)
            if tool == .redact { color = .black }
            mk.live = LiveMark(page: page, tool: tool, points: [p], color: color, width: CGFloat(st.width), opacity: CGFloat(st.opacity ?? ToolStyles.defaultOpacity(for: tool)))
            mkDrag = .draw
            mkDrawMode = .free
            if tool.kind == .ink, ruler.on {
                let A = mkRulerAxes()
                let vx = p.x - A.c.x, vy = p.y - A.c.y
                let along = vx * A.d.x + vy * A.d.y, across = vx * A.n.x + vy * A.n.y
                if ruler.lock { mkDrawMode = .lock }
                else if abs(along) <= mkRulerLength / 2, abs(across) >= mkRulerHeight / 2 - 2, abs(across) <= mkRulerHeight / 2 + 40 {
                    mkDrawMode = .edge(offset: (across < 0 ? -1 : 1) * (mkRulerHeight / 2 + CGFloat(st.width) / 2 + 1), along0: along)
                }
            }
            mk.renderTick += 1
        case .eraser:
            mkDrag = .erase
            mk.eraserPoint = p; mk.eraserPage = page
            mkBeginErase(on: page)
            mkEraseAt(p, page: page)
            mk.renderTick += 1
        default:
            mkDrag = .draw   // tap tools finish on up
        }
    }

    func mkPointerMove(_ s: PointerSample, page: PDFPage, at p: CGPoint) {
        guard let d = mkDrag else { return }
        switch d {
        case .draw:
            guard var live = mk.live else { return }
            mkDragMoved = true
            switch live.tool.kind {
            case .ink:
                switch mkDrawMode {
                case .free:
                    if let l = live.points.last, hypot(l.x - p.x, l.y - p.y) < 0.8 { return }
                    live.points.append(p)
                case .edge(let offset, let along0):
                    let A = mkRulerAxes()
                    let half = mkRulerLength / 2
                    let along = max(-half, min(half, (p.x - A.c.x) * A.d.x + (p.y - A.c.y) * A.d.y))
                    func at(_ q: CGFloat) -> CGPoint { CGPoint(x: A.c.x + A.d.x * q + A.n.x * offset, y: A.c.y + A.d.y * q + A.n.y * offset) }
                    live.points = [at(along0), at(along)]
                case .lock:
                    let A = mkRulerAxes()
                    let a = live.points[0]
                    let vx = p.x - a.x, vy = p.y - a.y
                    let pd = vx * A.d.x + vy * A.d.y, pn = vx * A.n.x + vy * A.n.y
                    let u = abs(pd) >= abs(pn) ? CGPoint(x: A.d.x * pd, y: A.d.y * pd) : CGPoint(x: A.n.x * pn, y: A.n.y * pn)
                    live.points = [a, CGPoint(x: a.x + u.x, y: a.y + u.y)]
                }
            case .highlight, .textMarkup:
                live.points = [live.points[0], p]
                if let sel = page.selection(from: live.points[0], to: p) {
                    live.quads = sel.selectionsByLine().map { $0.bounds(for: page) }.filter { $0.width > 0.5 }
                } else { live.quads = [] }
            case .shape:
                if live.tool == .polyline || live.tool == .polygon { live.points.append(p) } else { live.points = [live.points[0], p] }
            default: break
            }
            mk.live = live
            mk.renderTick += 1
        case .marquee(let start):
            mkDragMoved = true
            if let l = mk.lasso.last, hypot(l.x - p.x, l.y - p.y) >= 1.5 { mk.lasso.append(p) }
            if !mkLassoMode {
                let dev = mk.lasso.map { Hit.distance(Point($0.x, $0.y), toSegment: Point(start.x, start.y), Point(p.x, p.y)) }.max() ?? 0
                if dev > 14 / mkZoom { mkLassoMode = true; mk.marquee = nil }
            }
            if !mkLassoMode { mk.marquee = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y)) }
            mk.renderTick += 1
        case .move(let start, let snaps, let boxOnly):
            let dx = p.x - start.x, dy = p.y - start.y
            if !mkDragMoved { if hypot(dx, dy) < 2 / mkZoom { return }; mkDragMoved = true; mkPerform(.change(annots: snaps), alreadyApplied: true) }
            for (a, snap) in snaps {
                // Dragging a callout's box alone: the leader stays put here and is re-laid around its fixed tip below.
                if boxOnly, a.subtype == "Ink", a.redlineTool == .callout { continue }
                a.bounds = snap.bounds.offsetBy(dx: dx, dy: dy)
                if let vs = snap.vertices { a.polygonVertices = vs.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }; a.dropAppearance() }
            }
            if boxOnly {
                for (a, _) in snaps where mkIsCalloutBox(a) { if let pg = a.page { mkRelayoutLeader(for: a, on: pg) } }
            }
            mkMarkDirty()
        case .resize(let center, let d0, let snaps):
            if !mkDragMoved { mkDragMoved = true; mkPerform(.change(annots: snaps), alreadyApplied: true) }
            if snaps.count == 1, let first = snaps.first, first.0.subtype == "FreeText" {
                // Text box: the bottom-right corner sets width and height; the text keeps its size and rewraps.
                let a = first.0, b = first.1.bounds
                let font = a.font ?? RedlineFonts.page(size: 16, weight: nil)
                let w = max(40, p.x - b.minX)
                let need = TextBoxRenderer.fittingSize(text: a.contents ?? "", font: font, maxWidth: w).height
                let h = max(need, b.maxY - p.y)
                a.bounds = CGRect(x: b.minX, y: b.maxY - h, width: w, height: h)
                a.isManuallySized = true
                a.modificationDate = Date()
                a.dropAppearance()
                if a.redlineTool == .callout { mkRelayoutLeader(for: a, on: page) }
                mkMarkDirty()
                return
            }
            let f = max(0.05, hypot(p.x - center.x, p.y - center.y) / d0)
            for (a, snap) in snaps {
                if a.subtype == "Ink", let paths = snap.paths {
                    AnnotationFactory.setInkPaths(a, paths.map { $0.map { CGPoint(x: center.x + ($0.x - center.x) * f, y: center.y + ($0.y - center.y) * f) } })
                } else if let vs = snap.vertices {
                    let b = snap.bounds
                    a.bounds = CGRect(x: center.x + (b.minX - center.x) * f, y: center.y + (b.minY - center.y) * f, width: b.width * f, height: b.height * f)
                    a.polygonVertices = vs.map { CGPoint(x: center.x + ($0.x - center.x) * f, y: center.y + ($0.y - center.y) * f) }
                    a.dropAppearance()
                } else {
                    let b = snap.bounds
                    a.bounds = CGRect(x: center.x + (b.minX - center.x) * f, y: center.y + (b.minY - center.y) * f, width: b.width * f, height: b.height * f)
                    if a.subtype == "FreeText", let font = snap.font { a.font = font.withSize(max(4, font.pointSize * f)) }
                    a.dropAppearance()
                }
            }
            mkMarkDirty()
        case .handle(let leader, let index, let snap):
            if !mkDragMoved { mkDragMoved = true; mkPerform(.change(annots: [(leader, snap)]), alreadyApplied: true) }
            mkMoveLeaderPoint(leader, index: index, to: p)
        case .erase:
            mk.eraserPoint = p; mk.eraserPage = page
            mkEraseAt(p, page: page)
            mk.renderTick += 1
        case .rulerMove(let start, let base):
            mkDragMoved = true
            ruler.x = base.x + (p.x - start.x); ruler.y = base.y + (p.y - start.y)
            mk.renderTick += 1
        case .rulerRotate(let a0, let r0):
            mkDragMoved = true
            let ang = atan2(-(p.y - ruler.y), p.x - ruler.x) * 180 / .pi
            var na = ang - a0 + r0
            na = (na.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
            let snapped = (na / 15).rounded() * 15
            if abs(na - snapped) < 2.5 { na = snapped.truncatingRemainder(dividingBy: 180) }
            ruler.angle = na
            mk.renderTick += 1
        case .rulerTap, .pan:
            break
        case .polyTap(let start):
            if hypot(p.x - start.x, p.y - start.y) > 6 / mkZoom { mkDragMoved = true }
        }
    }

    func mkPointerUp(_ s: PointerSample, page: PDFPage, at p: CGPoint) {
        guard let d = mkDrag else { return }
        mkDrag = nil
        if mk.eraserPoint != nil { mk.eraserPoint = nil; mk.eraserPage = nil; mk.renderTick += 1 }
        switch d {
        case .draw:
            if let live = mk.live {
                mk.live = nil
                mk.renderTick += 1
                if mkDragMoved || live.tool.kind == .ink { mkCommit(live) }
                return
            }
            if !mkDragMoved { mkTap(at: p, page: page) }
        case .marquee:
            let poly = mk.lasso, rect = mk.marquee
            mk.lasso = []; mk.marquee = nil; mk.lassoPage = nil
            if mkDragMoved {
                let polyPts = poly.map { Point($0.x, $0.y) }
                func inside(_ c: CGPoint) -> Bool {
                    if mkLassoMode { return poly.count >= 3 && Hit.polygon(polyPts, contains: Point(c.x, c.y)) }
                    return rect?.contains(c) ?? false
                }
                var hits: [PDFAnnotation] = []
                for a in page.annotations where a.isPrimary && !a.isWidget {
                    if a.subtype == "Ink", a.redlineTool.isPen || a.redlineTool == .signature {
                        // Stroke by stroke: strokes inside the lasso come out of the annotation and are selected alone.
                        let paths = AnnotationFactory.inkPaths(a)
                        let idx = paths.indices.filter { i in paths[i].count > 0 && inside(paths[i][paths[i].count / 2]) }
                        if idx.isEmpty { continue }
                        if idx.count == paths.count { hits.append(a) } else { hits.append(mkExtractPaths(idx, from: a, page: page)) }
                    } else if inside(CGPoint(x: a.bounds.midX, y: a.bounds.midY)) {
                        hits.append(a)
                    }
                }
                mk.selected = hits.flatMap { AppearancePatcher.promote(mkGroup(of: $0, on: page), on: page) }
                mk.annotationPopup = false
                if !hits.isEmpty { app.flash("\(hits.count) selected") }
            } else {
                mkClearSelection()
            }
            mkLassoMode = false
            mk.renderTick += 1
        case .move:
            if !mkDragMoved, let a = mk.pendingTextEdit { mkBeginTextEdit(a, page: page, isNew: false) }
            mk.pendingTextEdit = nil
            mk.renderTick += 1
        case .resize, .handle:
            mk.renderTick += 1
        case .erase:
            mkEndErase(on: page)
        case .rulerTap:
            toggleRulerLock(); mk.renderTick += 1
        case .rulerMove, .rulerRotate:
            break
        case .polyTap:
            if !mkDragMoved { mkPolyAddPoint(p, page: page) }
        case .pan:
            if !mkDragMoved {
                if mk.swallowTap { mk.swallowTap = false; return }
                // A clean tap on an annotation selects it, whatever tool is active.
                if tool.kind == .fill, mkFillAt(p, page: page) { return }   // a bucket tap is always on top of something
                if mkSelectHit(at: p, page: page, splitStrokes: false) { return }
                if tool.info.isTap || tool.kind == .fill { mkTap(at: p, page: page) }
                else if tool == .none { mkClearSelection() }
            }
        }
    }

    func mkPointerCancel() {
        if case .erase? = mkDrag, let pg = mk.eraserPage { mkEndErase(on: pg) }
        mkDrag = nil
        mk.live = nil
        mk.eraserPoint = nil; mk.eraserPage = nil
        mk.lasso = []; mk.marquee = nil; mk.lassoPage = nil
        mk.renderTick += 1
    }

    /// Resize handle (bottom-right of the selection) drag start.
    func mkBeginResize(at p: CGPoint) {
        guard let b = mkSelectionBounds else { return }
        let movable = mkMovableSelection
        guard !movable.isEmpty else { return }
        let c = CGPoint(x: b.midX, y: b.midY)
        mkDrag = .resize(center: c, d0: max(4, hypot(p.x - c.x, p.y - c.y)), snaps: movable.map { ($0, AnnotationSnapshot($0)) })
        mkDragMoved = false
    }

    /// Callout leader handle drag start (index 0 = tip, 1 = elbow).
    func mkBeginLeaderHandle(_ leader: PDFAnnotation, index: Int) {
        mkDrag = .handle(leader: leader, index: index, snap: AnnotationSnapshot(leader))
        mkDragMoved = false
    }

    private func mkFingerMayInk(deciding isPencil: Bool) -> Bool {
        switch app.settings.fingerDrawingMode {
        case .always: return true
        case .never: return false
        case .auto:
            if fingerInkAllowed == nil { fingerInkAllowed = !isPencil }
            return fingerInkAllowed ?? true
        }
    }

    // MARK: commit

    private func mkCommit(_ live: LiveMark) {
        let page = live.page
        let st = style(for: live.tool)
        let author = app.author
        switch live.tool.kind {
        case .ink:
            let pts = live.points
            // Chain into the open Ink annotation only while the style is identical (one annotation = one colour/width).
            let sameStyle: Bool = {
                guard let ink = mk.activeInk else { return false }
                let sameColor = HexColor.same(PDFColors.hex(ink.color), st.color)
                let sameWidth = abs(Double(ink.border?.lineWidth ?? 0) - st.width) < 0.05
                let sameOpacity = abs(ink.opacityValue - (st.opacity ?? 1)) < 0.01
                return sameColor && sameWidth && sameOpacity
            }()
            let chainOpen = live.tool.isPen && mk.activeInk != nil && mk.activeInk?.page === page && mk.activeInk?.redlineTool == live.tool && mk.pdf?.index(for: page) == pageIndex
            if chainOpen, sameStyle, let ink = mk.activeInk {
                mkPerform(.change(annots: [(ink, AnnotationSnapshot(ink))]), alreadyApplied: true)
                AnnotationFactory.append(path: pts, to: ink)
                mkMarkDirty()
            } else if chainOpen, let root = mk.activeInkRoot ?? mk.activeInk {
                // Different colour / width in the same chain: a new Ink annotation grouped with the first
                // (PDF "RT /Group"), so readers show one comment with several colours.
                let a = AnnotationFactory.ink(paths: [pts], tool: live.tool, style: st, author: author)
                var gid = root.value(forAnnotationKey: .redlineGroup) as? String
                if gid == nil { gid = IDGen.make(); root.setValue(NSString(string: gid!), forAnnotationKey: .redlineGroup) }
                a.setValue(NSString(string: gid!), forAnnotationKey: .redlineGroup)
                a.setValue(root, forAnnotationKey: .inReplyTo)
                a.setValue(NSString(string: "/Group"), forAnnotationKey: .replyType)
                mkPerform(.add(page: page, annots: [a]))
                mk.activeInk = a
                mk.activeInkRoot = root
            } else {
                let a = AnnotationFactory.ink(paths: [pts], tool: live.tool, style: st, author: author)
                mkPerform(.add(page: page, annots: [a]))
                mk.activeInk = live.tool.isPen ? a : nil
                mk.activeInkRoot = live.tool.isPen ? a : nil
            }
        case .highlight, .textMarkup:
            guard !live.quads.isEmpty else { app.flash("No text under the \(live.tool.label.lowercased())"); return }
            mkPerform(.add(page: page, annots: [AnnotationFactory.textMarkup(quads: live.quads, tool: live.tool, style: st, author: author)]))
            mk.activeInk = nil; mk.activeInkRoot = nil
        case .shape:
            guard live.points.count >= 2 else { return }
            let a = live.points[0], b = live.points[live.points.count - 1]
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            if rect.width < 2 && rect.height < 2 { return }
            var annots: [PDFAnnotation] = []
            switch live.tool {
            case .rect, .ellipse: annots = [AnnotationFactory.shape(rect: rect, tool: live.tool, style: st, author: author)]
            case .redact: annots = [AnnotationFactory.redaction(rect: rect, author: author)]
            case .line, .arrow, .dblarrow: annots = [AnnotationFactory.line(from: a, to: b, tool: live.tool, style: st, author: author)]
            case .cloud:
                annots = [AnnotationFactory.ink(paths: [MarkupGeometry.cloudPoints(rect)], tool: live.tool, style: st, author: author)]
            case .callout:
                let L = mkCalloutLayout(tip: a, at: b, style: st)
                let pair = AnnotationFactory.callout(tip: a, elbow: L.elbow, attach: L.attach, box: L.box, text: "", style: L.textStyle, author: author)
                annots = [pair.leader, pair.box]
                mkPerform(.add(page: page, annots: annots))
                mk.selected = annots
                mkBeginTextEdit(pair.box, page: page, isNew: true)
                return
            default: break
            }
            guard !annots.isEmpty else { return }
            mkPerform(.add(page: page, annots: annots))
            mk.activeInk = nil; mk.activeInkRoot = nil
        default:
            break
        }
    }

    private func mkTap(at p: CGPoint, page: PDFPage) {
        let info = tool.info
        let author = app.author
        switch info.kind {
        case .place:
            let st = style(for: tool)
            if tool == .note {
                let a = AnnotationFactory.note(at: p, style: st, author: author)
                mkPerform(.add(page: page, annots: [a]))
                mkSelect(a, on: page)
                mk.focusComment = true
            } else if tool == .check || tool == .xmark {
                let s: CGFloat = 40
                let paths: [[CGPoint]] = tool == .check
                    ? [[CGPoint(x: p.x - s * 0.5, y: p.y), CGPoint(x: p.x - s * 0.12, y: p.y - s * 0.38), CGPoint(x: p.x + s * 0.6, y: p.y + s * 0.48)]]
                    : [[CGPoint(x: p.x - s * 0.4, y: p.y + s * 0.4), CGPoint(x: p.x + s * 0.4, y: p.y - s * 0.4)], [CGPoint(x: p.x + s * 0.4, y: p.y + s * 0.4), CGPoint(x: p.x - s * 0.4, y: p.y - s * 0.4)]]
                mkPerform(.add(page: page, annots: [AnnotationFactory.ink(paths: paths, tool: tool, style: st, author: author)]))
            }
        case .text:
            let st = style(for: .textbox)
            let fs = CGFloat(10 + st.width)
            let empty = TextBoxRenderer.fittingSize(text: "", font: AnnotationFactory.fontFor(st, size: fs))
            let a = AnnotationFactory.freeText(rect: CGRect(x: p.x, y: p.y - empty.height, width: max(60, empty.width), height: empty.height), text: "", tool: .textbox, style: st, author: author)
            mkPerform(.add(page: page, annots: [a]))
            mk.selected = [a]
            mkBeginTextEdit(a, page: page, isNew: true)
        case .stampGallery:
            mkPerform(.add(page: page, annots: [AnnotationFactory.stampText(center: p, text: stamp.resolved(author: author), colorHex: stamp.color, author: author, tool: .stamps)]))
        case .stampPreset:
            let text = tool == .datestamp ? "RECEIVED \(Formatting.shortDate(Date()))" : Avatar.initials(app.author) + "."
            mkPerform(.add(page: page, annots: [AnnotationFactory.stampText(center: p, text: text, colorHex: info.stampColor ?? "#FF3B30", author: author, tool: tool)]))
        case .form:
            guard let ft = info.fieldType else { return }
            let sz = ft.defaultSize
            let n = page.annotations.filter(\.isWidget).count + 1
            let a = AnnotationFactory.widget(rect: CGRect(x: p.x - sz.w / 2, y: p.y - sz.h / 2, width: sz.w, height: sz.h), type: ft, name: "\(ft.rawValue)_\(n)", author: author)
            mkPerform(.add(page: page, annots: [a]))
            mk.selected = [a]
            tool = .select
        case .fill:
            if !mkFillAt(p, page: page) { app.flash("Tap inside a shape, a cloud or a closed line") }
        default:
            break
        }
    }

    // MARK: erase (partial, ink only)

    /// The fill of the selected annotation: its own interior colour (rectangle / ellipse) or the grouped fill polygon.
    var mkSelectedFill: (annotation: PDFAnnotation, isPolygon: Bool)? {
        guard let a = mk.selectedPrimary, let page = a.page else { return nil }
        if (a.subtype == "Square" || a.subtype == "Circle"), a.interiorColor != nil, a.redlineTool != .redact { return (a, false) }
        if let fill = mkGroup(of: a, on: page).first(where: { $0.subtype == "Polygon" && $0.redlineTool == .fill }) { return (fill, true) }
        return nil
    }

    /// Removes the fill from the selected annotation (undoable); the outline stays.
    func mkRemoveFill() {
        guard let f = mkSelectedFill, let page = f.annotation.page else { return }
        if f.isPolygon {
            mkPerform(.remove(page: page, annots: [f.annotation]))
            mk.selected.removeAll { $0 === f.annotation }
        } else {
            mkPerform(.change(annots: [(f.annotation, AnnotationSnapshot(f.annotation))]), alreadyApplied: true)
            f.annotation.interiorColor = nil
            f.annotation.dropAppearance()
        }
        mkMarkDirty()
        app.flash("Fill removed")
    }

    /// Bucket: rectangles / ellipses take their own interior colour; closed outlines (clouds, closed polylines, pen
    /// loops) get a grouped fill polygon drawn beneath them. Text boxes, stamps and notes are never filled.
    /// Returns false when nothing fillable is under `p`.
    @discardableResult
    func mkFillAt(_ p: CGPoint, page: PDFPage) -> Bool {
        let st = style(for: .fill)
        let alpha = st.opacity ?? 0.5
        let author = app.author
        if let a = page.annotations.last(where: { ($0.subtype == "Square" || $0.subtype == "Circle") && $0.redlineTool != .redact && $0.bounds.contains(p) }) {
            mkPerform(.change(annots: [(a, AnnotationSnapshot(a))]), alreadyApplied: true)
            a.interiorColor = PDFColors.uiColor(st.color, alpha: alpha)
            a.dropAppearance()
            mkMarkDirty()
            app.flash("Filled")
            return true
        }
        guard let closed = mkClosedOutline(at: p, page: page) else { return false }
        let ink = closed.0, outline = closed.1
        if let fill = mkGroup(of: ink, on: page).first(where: { $0.subtype == "Polygon" && $0.redlineTool == .fill }) {
            mkPerform(.change(annots: [(fill, AnnotationSnapshot(fill))]), alreadyApplied: true)
            fill.interiorColor = PDFColors.uiColor(st.color); fill.color = fill.interiorColor ?? fill.color
            fill.opacityValue = alpha
            fill.dropAppearance()
            mkMarkDirty()
        } else {
            let fill = AnnotationFactory.fillPolygon(points: outline, colorHex: st.color, alpha: alpha, root: ink, author: author)
            mkPerform(.add(page: page, annots: [fill]))
            // Keep the outline on top of its fill.
            page.removeAnnotation(ink); page.addAnnotation(ink)
            mkMarkDirty()
        }
        app.flash("Filled")
        return true
    }

    /// The topmost closed Ink outline (cloud, closed polyline, pen loop) containing `p`, with its outline points.
    private func mkClosedOutline(at p: CGPoint, page: PDFPage) -> (PDFAnnotation, [CGPoint])? {
        for a in page.annotations.reversed() where a.subtype == "Ink" && a.isPrimary && a.redlineTool != .callout && a.redlineTool != .arrow && a.redlineTool != .dblarrow {
            guard a.bounds.contains(p) else { continue }
            for path in AnnotationFactory.inkPaths(a) where path.count >= 3 {
                let f = path[0], l = path[path.count - 1]
                let span = max(a.bounds.width, a.bounds.height)
                let closed = a.redlineTool == .cloud || hypot(f.x - l.x, f.y - l.y) <= max(6, span * 0.12)
                if closed, Hit.polygon(path.map { Point($0.x, $0.y) }, contains: Point(p.x, p.y)) { return (a, path) }
            }
        }
        return nil
    }

    private func mkErasable(_ a: PDFAnnotation) -> Bool { a.subtype == "Ink" && (a.redlineTool.isPen || a.redlineTool == .signature) }

    /// Start of an eraser drag: snapshot every erasable stroke on the page before anything is cut.
    private func mkBeginErase(on page: PDFPage) {
        mk.eraseSnaps = page.annotations.filter(mkErasable).map { ($0, AnnotationSnapshot($0)) }
        mk.eraseRemoved = []
        mk.eraseChanged = false
        mk.lastErasePoint = nil
    }

    /// End of the drag: everything it cut or removed becomes a single undo step.
    private func mkEndErase(on page: PDFPage) {
        defer { mk.eraseSnaps = []; mk.eraseRemoved = []; mk.eraseChanged = false; mk.lastErasePoint = nil }
        guard mk.eraseChanged else { return }
        var cmds: [PDFCommand] = [.change(annots: mk.eraseSnaps)]
        if !mk.eraseRemoved.isEmpty { cmds.append(.remove(page: page, annots: mk.eraseRemoved)) }
        mkPerform(.group(cmds), alreadyApplied: true)
    }

    private func mkEraseAt(_ p: CGPoint, page: PDFPage) {
        let r = CGFloat(max(2, style(for: .eraser).width / 2))
        // Throttle: a move shorter than a third of the radius changes nothing visible.
        if let last = mk.lastErasePoint, hypot(last.x - p.x, last.y - p.y) < r / 3 { return }
        mk.lastErasePoint = p
        // Only pen ink is erasable; shapes, arrows, clouds and callout leaders stay whole.
        let inks = page.annotations.filter { mkErasable($0) && $0.bounds.insetBy(dx: -r, dy: -r).contains(p) }
        var removed: [PDFAnnotation] = []
        var touchedAny = false
        for a in inks {
            let paths = AnnotationFactory.inkPaths(a)
            let w = (a.border?.lineWidth ?? 2) / 2
            var out: [[CGPoint]] = []
            var touched = false
            for path in paths {
                let sp = Hit.resample(path.map { StrokePoint(Double($0.x), Double($0.y)) }, maxStep: Double(max(2, r / 2)))
                let inside = sp.map { hypot(CGFloat($0.x) - p.x, CGFloat($0.y) - p.y) <= r + w }
                if !inside.contains(true) { out.append(path); continue }
                touched = true
                var run: [CGPoint] = []
                for (i, q) in sp.enumerated() {
                    if inside[i] { if run.count >= 2 { out.append(run) }; run = [] } else { run.append(CGPoint(x: q.x, y: q.y)) }
                }
                if run.count >= 2 { out.append(run) }
            }
            guard touched else { continue }
            touchedAny = true
            if !mk.eraseSnaps.contains(where: { $0.0 === a }) { mk.eraseSnaps.append((a, AnnotationSnapshot(a))) }   // drawn mid-drag
            if out.isEmpty { removed.append(a) } else { AnnotationFactory.setInkPaths(a, out) }
        }
        guard touchedAny else { return }
        mk.eraseChanged = true
        if !removed.isEmpty { removed.forEach { page.removeAnnotation($0) }; mk.eraseRemoved += removed }
        if mk.activeInk.map({ removed.contains($0) }) == true { mk.activeInk = nil; mk.activeInkRoot = nil }
        mk.dirty = true
        mk.renderTick += 1   // the save itself waits for the drag to end
    }

    // MARK: text editing (FreeText)

    func mkBeginTextEdit(_ a: PDFAnnotation, page: PDFPage, isNew: Bool) {
        mkCommitTextEdit()
        mk.textDraft = a.contents ?? ""
        mk.textEditSnapshot = isNew ? nil : AnnotationSnapshot(a)
        mk.textEdit = PDFTextEdit(annotation: a, page: page, isNew: isNew)
        mk.annotationPopup = false
        a.shouldDisplay = false   // the inline editor draws the box while typing
        mk.renderTick += 1
    }

    /// Called on every keystroke: the box follows the text (width too, unless the user sized it).
    func mkLiveTextChanged() {
        guard let te = mk.textEdit else { return }
        te.annotation.contents = mk.textDraft
        mkFitTextBox(te.annotation, text: mk.textDraft)
        if te.annotation.redlineTool == .callout { mkRelayoutLeader(for: te.annotation, on: te.page) }
        mk.renderTick += 1
    }

    /// Fits a text box to its text: free boxes grow in both directions; corner-sized boxes keep their width.
    func mkFitTextBox(_ a: PDFAnnotation, text: String) {
        let font = a.font ?? RedlineFonts.page(size: 16, weight: nil)
        let b = a.bounds
        if a.isManuallySized {
            let need = TextBoxRenderer.fittingSize(text: text, font: font, maxWidth: b.width).height
            let h = max(b.height, need)
            a.bounds = CGRect(x: b.minX, y: b.maxY - h, width: b.width, height: h)
        } else {
            var size = TextBoxRenderer.fittingSize(text: text, font: font)
            size.width = max(60, size.width)
            if a.rotationDegrees != 0 {
                // Stamps: keep the tilt; the bounds grow around the same centre.
                let outer = TextBoxRenderer.outerSize(inner: size, rotation: a.rotationDegrees)
                a.bounds = CGRect(x: b.midX - outer.width / 2, y: b.midY - outer.height / 2, width: outer.width, height: outer.height)
            } else {
                a.bounds = CGRect(x: b.minX, y: b.maxY - size.height, width: size.width, height: size.height)
            }
        }
        a.dropAppearance()
    }

    // MARK: polyline (tap to place vertices)

    func mkPolyAddPoint(_ p: CGPoint, page: PDFPage) {
        if let pg = mk.polyPage, pg !== page { mkFinishPolyline() }
        let tol = 14 / mkZoom
        if let last = mk.polyPoints.last, hypot(last.x - p.x, last.y - p.y) <= tol { mkFinishPolyline(); return }   // tap the last point: done
        if mk.polyPoints.count >= 2, let first = mk.polyPoints.first, hypot(first.x - p.x, first.y - p.y) <= tol {
            mk.polyPoints.append(first); mkFinishPolyline(); return   // tap the first point: closed
        }
        mk.polyPage = page
        mk.polyPoints.append(p)
        mk.renderTick += 1
        if mk.polyPoints.count == 1 { app.flash("Tap to add points · tap the last point to finish") }
    }

    func mkFinishPolyline() {
        guard let page = mk.polyPage else { return }
        let pts = mk.polyPoints
        mk.polyPoints = []; mk.polyPage = nil
        mk.renderTick += 1
        guard pts.count >= 2 else { return }
        mkPerform(.add(page: page, annots: [AnnotationFactory.ink(paths: [pts], tool: .polyline, style: style(for: .polyline), author: app.author)]))
    }

    // MARK: callout geometry (shared by the live preview and the commit)

    /// Where the box, elbow and attach point go for a callout whose arrow tip is `tip` and whose box corner is at `b`.
    func mkCalloutLayout(tip a: CGPoint, at b: CGPoint, style st: StylePreset) -> (box: CGRect, elbow: CGPoint, attach: CGPoint, textStyle: StylePreset) {
        var tb = style(for: .textbox); tb.color = st.color; tb.borderColor = st.color
        let fs = CGFloat(10 + st.width)
        let empty = TextBoxRenderer.fittingSize(text: "", font: AnnotationFactory.fontFor(tb, size: fs))
        let box = CGRect(x: b.x, y: b.y - empty.height, width: max(60, empty.width), height: empty.height)
        let g = mkCalloutGeometry(box: box, tip: a, distance: 28)
        return (box, g.elbow, g.attach, tb)
    }

    func mkIsCalloutBox(_ a: PDFAnnotation) -> Bool { a.subtype == "FreeText" && a.redlineTool == .callout }

    enum CalloutSide { case left, right, top, bottom }

    /// The side of the box that faces the tip (by the box's aspect, so wide boxes prefer top / bottom less readily).
    func mkCalloutSide(box: CGRect, tip: CGPoint) -> CalloutSide {
        let dx = tip.x - box.midX, dy = tip.y - box.midY
        if abs(dx) / max(1, box.width) >= abs(dy) / max(1, box.height) { return dx < 0 ? .left : .right }
        return dy < 0 ? .bottom : .top
    }

    /// How far outside the box a point lies on a given side (negative = not on that side).
    func mkOutward(_ p: CGPoint, of box: CGRect, side: CalloutSide) -> CGFloat {
        switch side {
        case .left: return box.minX - p.x
        case .right: return p.x - box.maxX
        case .top: return p.y - box.maxY
        case .bottom: return box.minY - p.y
        }
    }

    /// The side a dragged elbow is being pulled toward: the one it is furthest outside of.
    func mkNearestSide(_ p: CGPoint, of box: CGRect, fallback: CalloutSide) -> CalloutSide {
        let sides: [CalloutSide] = [.left, .right, .top, .bottom]
        let best = sides.max { mkOutward(p, of: box, side: $0) < mkOutward(p, of: box, side: $1) } ?? fallback
        return mkOutward(p, of: box, side: best) > 0 ? best : fallback
    }

    /// The elbow's side as stored on the leader (set when the user drags it), if any.
    func mkStoredSide(_ leader: PDFAnnotation) -> CalloutSide? {
        switch (leader.value(forAnnotationKey: .redlineSide) as? String) ?? "" {
        case "L": return .left; case "R": return .right; case "T": return .top; case "B": return .bottom
        default: return nil
        }
    }
    func mkStoreSide(_ side: CalloutSide?, on leader: PDFAnnotation) {
        guard let side else { leader.removeValue(forAnnotationKey: .redlineSide); return }
        let s: String
        switch side { case .left: s = "L"; case .right: s = "R"; case .top: s = "T"; case .bottom: s = "B" }
        leader.setValue(NSString(string: s), forAnnotationKey: .redlineSide)
    }

    /// Attach point = midpoint of the chosen (or facing) side; elbow = that point pushed `distance` straight out.
    func mkCalloutGeometry(box: CGRect, tip: CGPoint, distance d: CGFloat, side chosen: CalloutSide? = nil) -> (attach: CGPoint, elbow: CGPoint, side: CalloutSide) {
        let side = chosen ?? mkCalloutSide(box: box, tip: tip)
        let dd = max(10, d)
        switch side {
        case .left: return (CGPoint(x: box.minX, y: box.midY), CGPoint(x: box.minX - dd, y: box.midY), side)
        case .right: return (CGPoint(x: box.maxX, y: box.midY), CGPoint(x: box.maxX + dd, y: box.midY), side)
        case .top: return (CGPoint(x: box.midX, y: box.maxY), CGPoint(x: box.midX, y: box.maxY + dd), side)
        case .bottom: return (CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.midX, y: box.minY - dd), side)
        }
    }

    func mkCommitTextEdit() {
        guard let te = mk.textEdit else { return }
        mk.textEdit = nil
        te.annotation.shouldDisplay = true
        let txt = mk.textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if txt.isEmpty {
            var all = mkGroup(of: te.annotation, on: te.page)
            if all.isEmpty { all = [te.annotation] }
            if te.isNew {
                // Never committed: drop it (and the add command that created it).
                all.forEach { te.page.removeAnnotation($0) }
                if case .add(_, let annots)? = mk.undoStack.last, annots.contains(where: { $0 === te.annotation }) { mk.undoStack.removeLast() }
            } else {
                mkPerform(.remove(page: te.page, annots: all))
            }
            mkClearSelection()
            mkMarkDirty()
            return
        }
        if !te.isNew, let snap = mk.textEditSnapshot { mkPerform(.change(annots: [(te.annotation, snap)]), alreadyApplied: true) }
        mk.textEditSnapshot = nil
        te.annotation.contents = txt
        mkFitTextBox(te.annotation, text: txt)
        te.annotation.modificationDate = Date()
        if te.annotation.redlineTool == .callout { mkRelayoutLeader(for: te.annotation, on: te.page) }
        mkMarkDirty()
    }

    func mkCancelTextEdit() {
        guard let te = mk.textEdit else { return }
        if te.isNew { mk.textDraft = "" }
        mkCommitTextEdit()
    }

    // MARK: callout leader geometry

    func mkLeader(for box: PDFAnnotation, on page: PDFPage) -> PDFAnnotation? {
        mkGroup(of: box, on: page).first { $0 !== box && $0.subtype == "Ink" }
    }

    /// Leader points: attach (0), elbow (1), tip (2) of the first path.
    func mkLeaderPoints(_ leader: PDFAnnotation) -> [CGPoint] { AnnotationFactory.inkPaths(leader).first ?? [] }

    private func mkSetLeader(_ leader: PDFAnnotation, tip: CGPoint, elbow: CGPoint, attach: CGPoint) {
        let w = leader.border?.lineWidth ?? 1.5
        let ang = atan2(tip.y - elbow.y, tip.x - elbow.x)
        let size = max(10, w * 4)
        let h1 = CGPoint(x: tip.x - size * cos(ang - 0.45), y: tip.y - size * sin(ang - 0.45))
        let h2 = CGPoint(x: tip.x - size * cos(ang + 0.45), y: tip.y - size * sin(ang + 0.45))
        AnnotationFactory.setInkPaths(leader, [[attach, elbow, tip], [h1, tip, h2]])
    }

    /// Re-lays the leader around its fixed tip, keeping the elbow's distance. A side the user chose is kept while
    /// the tip is still out on that side; otherwise the elbow moves to the side that faces the tip.
    func mkRelayoutLeader(for box: PDFAnnotation, on page: PDFPage) {
        guard let leader = mkLeader(for: box, on: page) else { return }
        let pts = mkLeaderPoints(leader)
        guard pts.count >= 3 else { return }
        let d = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
        var side = mkStoredSide(leader)
        if let s = side, mkOutward(pts[2], of: box.bounds, side: s) <= 0 { side = nil; mkStoreSide(nil, on: leader) }
        let g = mkCalloutGeometry(box: box.bounds, tip: pts[2], distance: d, side: side)
        mkSetLeader(leader, tip: pts[2], elbow: g.elbow, attach: g.attach)
    }

    /// Tip handle (0): re-aims the arrow, the elbow follows to the facing side. Elbow handle (1): slides straight
    /// out from its side — horizontally on the left / right, vertically on the top / bottom.
    private func mkMoveLeaderPoint(_ leader: PDFAnnotation, index: Int, to p: CGPoint) {
        guard let page = leader.page, let box = mkGroup(of: leader, on: page).first(where: { $0.subtype == "FreeText" }) else { return }
        let pts = mkLeaderPoints(leader)
        guard pts.count >= 3 else { return }
        let b = box.bounds
        if index == 0 {
            let d = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
            let g = mkCalloutGeometry(box: b, tip: p, distance: d)
            mkSetLeader(leader, tip: p, elbow: g.elbow, attach: g.attach)
        } else {
            // Drag the elbow to any side; on that side it only slides straight out (horizontal on L/R, vertical on T/B).
            let current = mkStoredSide(leader) ?? mkCalloutSide(box: b, tip: pts[2])
            let side = mkNearestSide(p, of: b, fallback: current)
            mkStoreSide(side, on: leader)
            let g = mkCalloutGeometry(box: b, tip: pts[2], distance: mkOutward(p, of: b, side: side), side: side)
            mkSetLeader(leader, tip: pts[2], elbow: g.elbow, attach: g.attach)
        }
        mkMarkDirty()
    }
}

enum MarkupGeometry {
    /// Revision cloud outline (page space) around a rectangle.
    static func cloudPoints(_ rect: CGRect) -> [CGPoint] {
        let r = Rect(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
        return flatten(StrokeGeometry.cloud(r, radius: max(6, min(r.w, r.h) / 8)))
    }

    /// Flattens a PathData into a polyline (cubics sampled).
    static func flatten(_ path: PathData) -> [CGPoint] {
        var out: [CGPoint] = []
        var cur = CGPoint.zero
        for op in path.ops {
            switch op {
            case .move(let p): cur = CGPoint(x: p.x, y: p.y); out.append(cur)
            case .line(let p): cur = CGPoint(x: p.x, y: p.y); out.append(cur)
            case .quad(let c, let e):
                for k in 1...4 { let t = CGFloat(k) / 4; let mt = 1 - t
                    out.append(CGPoint(x: mt * mt * cur.x + 2 * mt * t * c.x + t * t * e.x, y: mt * mt * cur.y + 2 * mt * t * c.y + t * t * e.y)) }
                cur = CGPoint(x: e.x, y: e.y)
            case .cubic(let c1, let c2, let e):
                for k in 1...6 { let t = CGFloat(k) / 6; let mt = 1 - t
                    let x = mt * mt * mt * cur.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * e.x
                    let y = mt * mt * mt * cur.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * e.y
                    out.append(CGPoint(x: x, y: y)) }
                cur = CGPoint(x: e.x, y: e.y)
            case .close: if let f = out.first { out.append(f) }
            }
        }
        return out
    }
}
