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
    @ObservationIgnored weak var pdfView: PDFView?
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
    @ObservationIgnored var pendingTextEdit: PDFAnnotation? = nil

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
        mk.pdf = app.pdf.document(f)
        if let pdf = mk.pdf { AppearancePatcher.adoptTextBoxes(in: pdf) }
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
        if pdf.write(to: url) {
            // PDFKit can't write appearance streams: attach ours for text boxes in an incremental update.
            var textBoxes: [PDFAnnotation] = []
            for i in 0..<pdf.pageCount { if let p = pdf.page(at: i) { textBoxes += p.annotations.filter { $0.isRedlineTextBox } } }
            AppearancePatcher.patch(fileURL: url, annotations: textBoxes)
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

    func mkSelect(_ a: PDFAnnotation, on page: PDFPage) {
        mk.selected = mkGroup(of: a, on: page)
        mk.annotationPopup = true
        mk.annotationProps = false
        mk.styleSnapshotTaken = false
        mk.replyDraft = ""
        mk.renderTick += 1
    }

    func mkClearSelection() {
        mk.selected = []
        mk.annotationPopup = false
        mk.annotationProps = false
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
        guard let pdf = mk.pdf else { return [] }
        var out: [MarkupComment] = []
        let me = app.author
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let annots = page.annotations
            for a in annots where a.isPrimary && !a.isWidget {
                let author = (a.userName ?? "").isEmpty ? "Unknown" : a.userName!
                switch authorFilter {
                case .all: break
                case .mine: if author != me { continue }
                case .others: if author == me { continue }
                }
                let kids = annots.filter { ($0.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation) === a }
                let replies = kids.filter { $0.isReply }.sorted { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
                    .map { (author: ($0.userName ?? "").isEmpty ? "Unknown" : $0.userName!, time: $0.modificationDate ?? Date(), text: $0.contents ?? "") }
                let states = kids.filter { $0.isStateAnnotation }.sorted { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
                let status = states.last.flatMap { AnnotationFactory.status(fromState: $0.value(forAnnotationKey: .state) as? String) } ?? .open
                let group = mkGroup(of: a, on: page)
                let tool = a.redlineTool
                let text = tool == .textbox || tool == .callout || tool == .stamps || tool == .datestamp || tool == .initials ? "" : (a.contents ?? "")
                let strokes = group.filter { $0.subtype == "Ink" }.reduce(0) { $0 + max(1, ($1.paths ?? []).count) }
                out.append(MarkupComment(id: a.stableID, annotation: a, pageIndex: i, tool: tool, author: author, time: a.modificationDate ?? Date(),
                                         text: text, replies: replies, status: status, colorHex: PDFColors.hex(a.color),
                                         markCount: a.subtype == "Ink" ? strokes : group.count))
            }
        }
        return out.sorted { $0.pageIndex != $1.pageIndex ? $0.pageIndex < $1.pageIndex : $0.time > $1.time }
    }

    func mkSetText(_ a: PDFAnnotation, _ text: String) {
        a.contents = text
        a.modificationDate = Date()
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

    /// Whether an annotation carries comment text or replies (drives the badge).
    func mkHasComment(_ a: PDFAnnotation, on page: PDFPage) -> Bool {
        let t = a.redlineTool
        let textual = t == .textbox || t == .callout || t == .stamps || t == .datestamp || t == .initials
        if !textual, !(a.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return page.annotations.contains { $0.isReply && ($0.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation) === a }
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
                p.font = f.familyName == system ? nil : f.fontName
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
                page.draw(with: .mediaBox, to: cg)
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
        mkCommitTextEdit()
        closePopovers()
        mkDragMoved = false
        let info = tool.info
        if info.kind != .select && info.kind != .lasso { mkClearSelection(); selectedField = nil }
        // Finger on the ruler: move / rotate / lock. The Pencil passes through.
        if !s.isPencil, let hit = mkRulerHit(p) {
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
            if let a = page.annotation(at: p), !a.isLink, !a.isPopup {
                if mk.selected.contains(where: { $0 === a }) {
                    mkDrag = .move(start: p, snaps: mk.selected.map { ($0, AnnotationSnapshot($0)) })
                    mk.pendingTextEdit = (a.subtype == "FreeText") ? a : nil
                } else {
                    mkSelect(a, on: page)
                    mkDrag = nil
                }
            } else {
                mkDrag = .marquee(start: p)
                mk.marquee = nil; mk.lasso = [p]; mk.lassoPage = page; mkLassoMode = false
                mk.renderTick += 1
            }
        case .ink, .highlight, .textMarkup, .shape:
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
            mk.eraseSnapshotTaken = false
            mkDrag = .erase
            mkEraseAt(p, page: page)
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
        case .move(let start, let snaps):
            let dx = p.x - start.x, dy = p.y - start.y
            if !mkDragMoved { if hypot(dx, dy) < 2 / mkZoom { return }; mkDragMoved = true; mkPerform(.change(annots: snaps), alreadyApplied: true) }
            for (a, snap) in snaps { a.bounds = snap.bounds.offsetBy(dx: dx, dy: dy) }
            mkMarkDirty()
        case .resize(let center, let d0, let snaps):
            if !mkDragMoved { mkDragMoved = true; mkPerform(.change(annots: snaps), alreadyApplied: true) }
            let f = max(0.05, hypot(p.x - center.x, p.y - center.y) / d0)
            for (a, snap) in snaps {
                if a.subtype == "Ink", let paths = snap.paths {
                    AnnotationFactory.setInkPaths(a, paths.map { $0.map { CGPoint(x: center.x + ($0.x - center.x) * f, y: center.y + ($0.y - center.y) * f) } })
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
            mkEraseAt(p, page: page)
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
        }
    }

    func mkPointerUp(_ s: PointerSample, page: PDFPage, at p: CGPoint) {
        guard let d = mkDrag else { return }
        mkDrag = nil
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
                let hits = page.annotations.filter { a in
                    guard a.isPrimary, !a.isWidget else { return false }
                    let c = CGPoint(x: a.bounds.midX, y: a.bounds.midY)
                    if mkLassoMode { return poly.count >= 3 && Hit.polygon(poly.map { Point($0.x, $0.y) }, contains: Point(c.x, c.y)) }
                    return rect?.contains(c) ?? false
                }
                mk.selected = hits.flatMap { mkGroup(of: $0, on: page) }
                mk.annotationPopup = hits.count == 1
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
            break
        case .rulerTap:
            toggleRulerLock(); mk.renderTick += 1
        case .rulerMove, .rulerRotate:
            break
        case .pan:
            if !mkDragMoved, tool.info.isTap || tool.kind == .fill { mkTap(at: p, page: page) }
        }
    }

    func mkPointerCancel() {
        mkDrag = nil
        mk.live = nil
        mk.lasso = []; mk.marquee = nil; mk.lassoPage = nil
        mk.renderTick += 1
    }

    /// Resize handle (bottom-right of the selection) drag start.
    func mkBeginResize(at p: CGPoint) {
        guard let b = mkSelectionBounds else { return }
        let c = CGPoint(x: b.midX, y: b.midY)
        mkDrag = .resize(center: c, d0: max(4, hypot(p.x - c.x, p.y - c.y)), snaps: mk.selected.map { ($0, AnnotationSnapshot($0)) })
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
            if UIPencilInteraction.prefersPencilOnlyDrawing { return false }
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
            if rect.width < 2 && rect.height < 2 && live.tool != .polyline && live.tool != .polygon { return }
            var annots: [PDFAnnotation] = []
            switch live.tool {
            case .rect, .ellipse: annots = [AnnotationFactory.shape(rect: rect, tool: live.tool, style: st, author: author)]
            case .redact: annots = [AnnotationFactory.redaction(rect: rect, author: author)]
            case .line, .arrow, .dblarrow: annots = [AnnotationFactory.line(from: a, to: b, tool: live.tool, style: st, author: author)]
            case .polyline, .polygon:
                var pts = Hit.simplify(live.points.map { Point($0.x, $0.y) }, tolerance: 4).map { CGPoint(x: $0.x, y: $0.y) }
                if live.tool == .polygon, let f = pts.first { pts.append(f) }
                annots = [AnnotationFactory.ink(paths: [pts], tool: live.tool, style: st, author: author)]
            case .cloud:
                let r = Rect(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
                let pts = MarkupGeometry.flatten(StrokeGeometry.cloud(r, radius: max(6, min(r.w, r.h) / 8)))
                annots = [AnnotationFactory.ink(paths: [pts], tool: live.tool, style: st, author: author)]
            case .callout:
                let text = ""
                let fs = CGFloat(10 + st.width)
                let box = CGRect(x: b.x, y: b.y - fs * 1.6, width: 130, height: fs * 1.6 + 8)
                let left = a.x < box.midX
                let elbow = CGPoint(x: left ? box.minX - 28 : box.maxX + 28, y: box.midY)
                let attach = CGPoint(x: left ? box.minX : box.maxX, y: box.midY)
                var tb = style(for: .textbox); tb.color = st.color; tb.borderColor = st.color
                let pair = AnnotationFactory.callout(tip: a, elbow: elbow, attach: attach, box: box, text: text, style: tb, author: author)
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
            let a = AnnotationFactory.freeText(rect: CGRect(x: p.x, y: p.y - fs * 1.6, width: 140, height: fs * 1.6 + 8), text: "", tool: .textbox, style: st, author: author)
            mkPerform(.add(page: page, annots: [a]))
            mk.selected = [a]
            mkBeginTextEdit(a, page: page, isNew: true)
        case .stampGallery:
            mkPerform(.add(page: page, annots: [AnnotationFactory.stampText(center: p, text: stampText, colorHex: stampColor, author: author, tool: .stamps)]))
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
            let st = style(for: .fill)
            if let a = page.annotations.last(where: { ($0.subtype == "Square" || $0.subtype == "Circle") && $0.bounds.contains(p) }) {
                mkPerform(.change(annots: [(a, AnnotationSnapshot(a))]), alreadyApplied: true)
                a.interiorColor = PDFColors.uiColor(st.color, alpha: st.opacity ?? 0.5)
                a.dropAppearance()
                mkMarkDirty()
                app.flash("Filled")
            } else {
                app.flash("Tap inside a rectangle or ellipse")
            }
        default:
            break
        }
    }

    // MARK: erase (partial, ink only)

    private func mkEraseAt(_ p: CGPoint, page: PDFPage) {
        let r = CGFloat(max(2, style(for: .eraser).width / 2))
        let inks = page.annotations.filter { $0.subtype == "Ink" && $0.redlineTool != .callout && $0.bounds.insetBy(dx: -r, dy: -r).contains(p) }
        var changed: [(PDFAnnotation, AnnotationSnapshot)] = []
        var removed: [PDFAnnotation] = []
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
            if !mk.eraseSnapshotTaken { changed.append((a, AnnotationSnapshot(a))) }
            if out.isEmpty { removed.append(a) } else { AnnotationFactory.setInkPaths(a, out) }
        }
        guard !changed.isEmpty || !removed.isEmpty else { return }
        if !mk.eraseSnapshotTaken {
            // One undo step for the whole erase drag: snapshot every ink on the page.
            let all = page.annotations.filter { $0.subtype == "Ink" }.map { ($0, AnnotationSnapshot($0)) }
            mkPerform(.change(annots: all), alreadyApplied: true)
            mk.eraseSnapshotTaken = true
        }
        if !removed.isEmpty { removed.forEach { page.removeAnnotation($0) }; mk.undoStack.append(.remove(page: page, annots: removed)) }
        if mk.activeInk.map({ removed.contains($0) }) == true { mk.activeInk = nil; mk.activeInkRoot = nil }
        mkMarkDirty()
    }

    // MARK: text editing (FreeText)

    func mkBeginTextEdit(_ a: PDFAnnotation, page: PDFPage, isNew: Bool) {
        mkCommitTextEdit()
        mk.textDraft = a.contents ?? ""
        mk.textEdit = PDFTextEdit(annotation: a, page: page, isNew: isNew)
        mk.annotationPopup = false
    }

    func mkCommitTextEdit() {
        guard let te = mk.textEdit else { return }
        mk.textEdit = nil
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
        if !te.isNew { mkPerform(.change(annots: [(te.annotation, AnnotationSnapshot(te.annotation))]), alreadyApplied: true) }
        te.annotation.contents = txt
        // Grow the box to fit the text.
        let font = te.annotation.font ?? UIFont.systemFont(ofSize: 16)
        let size = TextBoxRenderer.fittingSize(text: txt, font: font)
        let b = te.annotation.bounds
        te.annotation.bounds = CGRect(x: b.minX, y: b.maxY - size.height, width: max(60, size.width), height: size.height)
        te.annotation.modificationDate = Date()
        te.annotation.dropAppearance()
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

    private func mkAttach(box: CGRect, elbow: CGPoint) -> CGPoint {
        if elbow.x < box.minX { return CGPoint(x: box.minX, y: min(box.maxY, max(box.minY, elbow.y))) }
        if elbow.x > box.maxX { return CGPoint(x: box.maxX, y: min(box.maxY, max(box.minY, elbow.y))) }
        if elbow.y > box.maxY { return CGPoint(x: min(box.maxX, max(box.minX, elbow.x)), y: box.maxY) }
        if elbow.y < box.minY { return CGPoint(x: min(box.maxX, max(box.minX, elbow.x)), y: box.minY) }
        return CGPoint(x: box.minX, y: box.midY)
    }

    private func mkSetLeader(_ leader: PDFAnnotation, tip: CGPoint, elbow: CGPoint, box: CGRect) {
        let attach = mkAttach(box: box, elbow: elbow)
        let w = leader.border?.lineWidth ?? 1.5
        let ang = atan2(tip.y - elbow.y, tip.x - elbow.x)
        let size = max(10, w * 4)
        let h1 = CGPoint(x: tip.x - size * cos(ang - 0.45), y: tip.y - size * sin(ang - 0.45))
        let h2 = CGPoint(x: tip.x - size * cos(ang + 0.45), y: tip.y - size * sin(ang + 0.45))
        AnnotationFactory.setInkPaths(leader, [[attach, elbow, tip], [h1, tip, h2]])
    }

    func mkRelayoutLeader(for box: PDFAnnotation, on page: PDFPage) {
        guard let leader = mkLeader(for: box, on: page) else { return }
        let pts = mkLeaderPoints(leader)
        guard pts.count >= 3 else { return }
        mkSetLeader(leader, tip: pts[2], elbow: pts[1], box: box.bounds)
    }

    private func mkMoveLeaderPoint(_ leader: PDFAnnotation, index: Int, to p: CGPoint) {
        guard let page = leader.page, let box = mkGroup(of: leader, on: page).first(where: { $0.subtype == "FreeText" }) else { return }
        let pts = mkLeaderPoints(leader)
        guard pts.count >= 3 else { return }
        let tip = index == 0 ? p : pts[2]
        let elbow = index == 1 ? p : pts[1]
        mkSetLeader(leader, tip: tip, elbow: elbow, box: box.bounds)
        mkMarkDirty()
    }
}

enum MarkupGeometry {
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
