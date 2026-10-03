import SwiftUI
import UIKit
import PDFKit
import RedlineCore

/// Redline's page stack (PDFStackView) plus a transparent input/drawing overlay, with SwiftUI overlays for the comment
/// popup and the inline text editor. Fingers scroll and pinch; the Pencil goes to the pages.
struct MarkupCanvas: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        let mk = editor.mk
        ZStack(alignment: .topLeading) {
            GrainBackground(color: theme.canvas)
            PDFStackRepresentable(editor: editor, tick: mk.renderTick, viewportTick: mk.viewportTick, canvasColor: UIColor(hex: theme.tokens.canvas))
            if let te = mk.textEdit { PDFTextEditor(editor: editor, edit: te) }
            if mk.annotationPopup, mk.textEdit == nil { PDFAnnotationPopup(editor: editor) }
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            if !mk.selected.isEmpty && !editor.organizeOpen { SelectionChrome(editor: editor) }
        }
    }
}

/// Floating bar beside the selection: "N selected" · Comment · Properties · Delete · ×. Properties drops the
/// embedded style editor under the bar. Follows the selection as the page scrolls or zooms.
struct SelectionChrome: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let mk = editor.mk
        let _ = mk.viewportTick
        let _ = mk.renderTick
        if let first = mk.selected.first, let page = first.page, let v = mk.pdfView, let b = editor.mkSelectionBounds {
            let r = v.convert(b, from: page)
            let fw = v.bounds.width, fh = max(200, v.bounds.height - mk.keyboardOverlap)
            let primaries = mk.selected.filter(\.isPrimary).count
            let isWidget = mk.selectedPrimary?.isWidget ?? false
            let canComment = primaries == 1 && !mk.annotationPopup && !isWidget
            let canStyle = !isWidget && editor.mkSelectedPreset() != nil
            let barW: CGFloat = 96 + (canComment ? 106 : 0) + (canStyle ? 118 : 0) + 86 + 36
            let x = min(max(8, r.midX - barW / 2), max(8, fw - barW - 8))
            let above = r.minY - 14 - 40 >= 8
            let y = above ? r.minY - 14 - 40 : min(r.maxY + 14, fh - 48)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(primaries <= 1 ? "1 selected" : "\(primaries) selected").font(fnt(13, .semibold)).foregroundStyle(theme.ink2)
                    if canComment {
                        Button { mk.selectionProps = false; mk.annotationPopup = true; mk.annotationProps = false; mk.focusComment = true } label: {
                            HStack(spacing: 5) { Image(systemName: "text.bubble").font(fnt(15, .medium)); Text("Comment").font(fnt(13, .semibold)) }
                                .foregroundStyle(theme.ink1).frame(height: 40).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if canStyle {
                        Button { withAnimation(.easeOut(duration: 0.15)) { mk.selectionProps.toggle() } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "slider.horizontal.3").font(fnt(15, .medium)); Text("Properties").font(fnt(13, .semibold))
                                Image(systemName: "chevron.down").font(fnt(10, .bold)).rotationEffect(.degrees(mk.selectionProps ? 180 : 0))
                            }
                            .foregroundStyle(mk.selectionProps ? theme.accent : theme.ink1).frame(height: 40).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Button { editor.mkDeleteSelection() } label: {
                        HStack(spacing: 5) { Image(systemName: "trash").font(fnt(15, .medium)); Text("Delete").font(fnt(13, .semibold)) }
                            .foregroundStyle(theme.danger).frame(height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { editor.mkClearSelection() } label: {
                        Image(systemName: "xmark").font(fnt(13, .bold)).foregroundStyle(theme.ink3).frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Clear selection")
                }
                .lineLimit(1)
                .padding(.leading, 14).padding(.trailing, 8)
                .frame(height: 40)
                .fixedSize(horizontal: true, vertical: false)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.popSolid).shadow(color: theme.popShadow.opacity(0.6), radius: 9, y: 4))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                if mk.selectionProps, let preset = editor.mkSelectedPreset(), let tool = editor.mkSelectedTool {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let f = editor.mkSelectedFill {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: f.annotation.interiorColor ?? .clear).opacity(f.isPolygon ? f.annotation.opacityValue : 1)).frame(width: 18, height: 18)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.line, lineWidth: 1))
                                    Text("Fill").font(fnt(13, .medium)).foregroundStyle(theme.ink2)
                                    Spacer()
                                    SecondaryButton(label: "Remove fill", symbol: "drop.slash", height: 30) { editor.mkRemoveFill() }
                                }
                            }
                            StylePopoverView(editor: editor, stroke: preset, apply: { body in editor.mkUpdateSelectedStyle(body) }, forTool: tool, showPresets: false, embedded: true)
                        }
                        .padding(14)
                    }
                    .frame(width: 300)
                    .frame(maxHeight: min(460, fh - y - 56))
                    .fixedSize(horizontal: false, vertical: true)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .popShadow(theme))
                    .popIn()
                }
            }
            .offset(x: x, y: max(8, y))
        }
    }
}

// MARK: - PDFView

struct PDFStackRepresentable: UIViewRepresentable {
    var editor: WorkspaceModel
    var tick: Int
    var viewportTick: Int
    var canvasColor: UIColor

    func makeUIView(context: Context) -> PDFStackView {
        let v = PDFStackView()
        v.backgroundColor = .clear   // the SwiftUI canvas (with its paper grain) shows through
        v.document = editor.mk.pdf
        editor.mk.pdfView = v
        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ v: PDFStackView, context: Context) {
        if v.document !== editor.mk.pdf { v.document = editor.mk.pdf }
        context.coordinator.editor = editor
        // Annotation layers redraw only when annotations changed, not on every scroll tick.
        if context.coordinator.lastTick != tick {
            context.coordinator.lastTick = tick
            v.syncPages()
            v.refreshAnnotations()
        }
        context.coordinator.overlay.setNeedsDisplay()
        if let i = editor.mk.scrollToPage { context.coordinator.scroll(to: i, in: v) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    static func dismantleUIView(_ uiView: PDFStackView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var editor: WorkspaceModel
        let overlay: MarkupOverlayView
        var lastTick = -1
        private var pendingScroll: Int? = nil
        private var observers: [NSObjectProtocol] = []

        init(editor: WorkspaceModel) {
            self.editor = editor
            self.overlay = MarkupOverlayView(editor: editor)
            super.init()
        }

        func detach() {
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
            overlay.removeFromSuperview()
            overlay.pdfView?.onViewportChange = nil
            overlay.pdfView?.onPageChange = nil
        }

        /// How much of the view the keyboard covers (the comment popup stays above it).
        private func keyboardChanged(_ frame: CGRect) {
            guard let v = overlay.pdfView else { return }
            var overlap: CGFloat = 0
            if frame != .zero, v.window != nil {
                let kb = v.convert(frame, from: nil)
                overlap = max(0, v.bounds.maxY - kb.minY)
            }
            if editor.mk.keyboardOverlap != overlap { editor.mk.keyboardOverlap = overlap }
        }

        func attach(to v: PDFStackView) {
            overlay.pdfView = v
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
                let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                MainActor.assumeIsolated { self?.keyboardChanged(frame) }
            })
            observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboardChanged(.zero) }
            })
            overlay.frame = v.documentView.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.documentView.addSubview(overlay)
            v.onViewportChange = { [weak self] in
                guard let self else { return }
                self.editor.mk.viewportTick += 1
                self.overlay.setNeedsDisplay()
            }
            v.onPageChange = { [weak self] i in
                guard let self, self.pendingScroll == nil else { return }
                if i != self.editor.pageIndex { self.editor.pageIndex = i }
            }
        }

        func scroll(to i: Int, in v: PDFStackView) {
            guard pendingScroll != i, let page = editor.mk.page(i) else { return }
            pendingScroll = i
            Task { @MainActor [weak self] in
                v.go(to: page)
                self?.editor.mk.scrollToPage = nil
                self?.pendingScroll = nil
            }
        }
    }
}

// MARK: - Overlay: input + live drawing + selection chrome + ruler

final class MarkupOverlayView: UIView, UIPencilInteractionDelegate {
    unowned let editor: WorkspaceModel
    weak var pdfView: PDFStackView?
    private var active: UITouch?
    private var dragPage: PDFPage?

    init(editor: WorkspaceModel) {
        self.editor = editor
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }
    required init?(coder: NSCoder) { fatalError() }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        if UIPencilInteraction.preferredTapAction == .ignore { return }
        editor.pencilDoubleTap()
    }

    /// While this overlay owns a drag (moving a selection, a handle, the ruler, a marquee…) the scroll view must not
    /// pan or zoom with the same finger. Disabling its recognisers cancels their tracking of the touch.
    private func captureScroll(_ on: Bool) {
        guard let sv = pdfView else { return }
        if sv.panGestureRecognizer.isEnabled == on { sv.panGestureRecognizer.isEnabled = !on }
        if let p = sv.pinchGestureRecognizer, p.isEnabled == on { p.isEnabled = !on }
    }

    private var overlayOwnsDrag: Bool {
        switch editor.mkDrag {
        case nil, .pan?, .polyTap?: return false
        default: return true
        }
    }

    // MARK: coordinates

    private func pageAndPoint(for location: CGPoint) -> (PDFPage, CGPoint)? {
        guard let v = pdfView else { return nil }
        let vp = convert(location, to: v)
        guard let page = dragPage ?? v.page(for: vp, nearest: true) else { return nil }
        return (page, v.convert(vp, to: page))
    }

    private func overlayPoint(_ p: CGPoint, on page: PDFPage) -> CGPoint {
        guard let v = pdfView else { return .zero }
        return v.convert(v.convert(p, from: page), to: self)
    }

    private func overlayRect(_ r: CGRect, on page: PDFPage) -> CGRect {
        guard let v = pdfView else { return .zero }
        return v.convert(v.convert(r, from: page), to: self)
    }

    /// Page units → overlay units, measured through the same conversion the points use (during a pinch the document
    /// view is transformed, so this is not simply `scaleFactor`).
    private func pageScale(_ v: PDFStackView) -> CGFloat {
        guard let page = v.currentPage else { return v.scaleFactor }
        let a = overlayPoint(.zero, on: page), b = overlayPoint(CGPoint(x: 100, y: 0), on: page)
        return max(0.01, hypot(b.x - a.x, b.y - a.y) / 100)
    }

    /// One screen point in overlay units (chrome like handles and badges keeps a constant size on screen).
    private var unit: CGFloat {
        guard let v = pdfView else { return 1 }
        return pageScale(v) / max(0.01, v.scaleFactor)
    }

    private func sample(_ t: UITouch) -> PointerSample {
        let pencil = t.type == .pencil
        let pressure = pencil && t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 0.5
        return PointerSample(location: t.location(in: self), pressure: pressure, isPencil: pencil, window: t.location(in: nil))
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if active == nil, let t = touches.first, (event?.allTouches?.count ?? 1) == 1 {
            active = t
            let s = sample(t)
            dragPage = nil
            guard let (page, p) = pageAndPoint(for: s.location) else { return }
            dragPage = page
            if let hit = handleHit(at: s.location, page: page) {
                switch hit {
                case .resize: editor.mkBeginResize(at: p)
                case .leader(let leader, let idx): editor.mkBeginLeaderHandle(leader, index: idx)
                }
                captureScroll(true)
                return
            }
            if let a = badgeHit(at: s.location, page: page) {
                // Badge tap: select and open the comment popup (the sidebar is left alone).
                active = nil
                dragPage = nil
                editor.mkSelect(a, on: page)
                editor.mk.annotationPopup = true
                editor.mk.focusComment = true
                setNeedsDisplay()
                return
            }
            editor.mkPointerDown(s, page: page, at: p)
            if overlayOwnsDrag { captureScroll(true) }
            setNeedsDisplay()
        } else if active != nil {
            // A second finger: give the touch back to the scroll view (pinch / two-finger pan).
            active = nil
            dragPage = nil
            editor.mkPointerCancel()
            captureScroll(false)
            setNeedsDisplay()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t), let page = dragPage else { return }
        for c in event?.coalescedTouches(for: t) ?? [t] {
            let s = sample(c)
            guard let (_, p) = pageAndPoint(for: s.location) else { continue }
            editor.mkPointerMove(s, page: page, at: p)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        active = nil
        let s = sample(t)
        if let page = dragPage, let (_, p) = pageAndPoint(for: s.location) { editor.mkPointerUp(s, page: page, at: p) }
        dragPage = nil
        captureScroll(false)
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        active = nil
        dragPage = nil
        editor.mkPointerCancel()
        captureScroll(false)
        setNeedsDisplay()
    }

    private enum HandleHit { case resize, leader(PDFAnnotation, Int) }

    /// The "has a comment" badge under a touch, if any.
    private func badgeHit(at loc: CGPoint, page: PDFPage) -> PDFAnnotation? {
        let replied = editor.mkRepliedParents(on: page)
        for a in page.annotations where a.isPrimary && !a.isWidget && editor.mkHasComment(a, replied: replied) {
            let c = badgeCenter(for: a, on: page)
            if hypot(loc.x - c.x, loc.y - c.y) <= 16 * unit { return a }
        }
        return nil
    }

    /// Badge centre (overlay space): 4 pt above the topmost point of the ink (bounds top for other kinds), 20 pt tall.
    private func badgeCenter(for a: PDFAnnotation, on page: PDFPage) -> CGPoint {
        var top = CGPoint(x: a.bounds.midX, y: a.bounds.maxY)
        if a.subtype == "Ink", let m = AnnotationFactory.inkPaths(a).flatMap({ $0 }).max(by: { $0.y < $1.y }) { top = m }
        let o = overlayPoint(top, on: page)
        return CGPoint(x: o.x, y: o.y - 14 * unit)
    }

    private func handleHit(at loc: CGPoint, page: PDFPage) -> HandleHit? {
        guard !editor.mk.selected.isEmpty, let sel = editor.mk.selected.first, sel.page === page else { return nil }
        if let box = editor.mk.selected.first(where: { $0.redlineTool == .callout && $0.subtype == "FreeText" }), let leader = editor.mkLeader(for: box, on: page) {
            let pts = editor.mkLeaderPoints(leader)
            if pts.count >= 3 {
                let tip = overlayPoint(pts[2], on: page), elbow = overlayPoint(pts[1], on: page)
                let u = unit
                if hypot(loc.x - tip.x, loc.y - tip.y) <= 18 * u { return .leader(leader, 0) }
                if hypot(loc.x - elbow.x, loc.y - elbow.y) <= 18 * u { return .leader(leader, 1) }
            }
        }
        if let b = editor.mkSelectionBounds, !editor.mkMovableSelection.isEmpty {
            let r = overlayRect(b, on: page)
            let u = unit
            let h = CGPoint(x: r.maxX + 8 * u, y: r.maxY + 8 * u)
            if hypot(loc.x - h.x, loc.y - h.y) <= 18 * u { return .resize }
        }
        return nil
    }

    // MARK: drawing

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext(), let v = pdfView else { return }
        let mk = editor.mk
        let accent = UIColor(hex: editor.app.settings.theme == .dark ? "#6C96E0" : "#2F6FE4")
        // z: page units → overlay units (stroke widths at their real displayed size); u: one screen point.
        let z = pageScale(v)
        let u = z / max(0.01, v.scaleFactor)

        // Live mark
        if let live = mk.live {
            cg.saveGState()
            cg.setLineCap(.round); cg.setLineJoin(.round)
            cg.setAlpha(live.opacity)
            if live.tool.kind == .highlight || live.tool.kind == .textMarkup {
                cg.setFillColor(live.color.cgColor)
                cg.setBlendMode(.multiply)
                for q in live.quads {
                    let r = overlayRect(q, on: live.page)
                    if live.tool == .highlighter { cg.fill(r) } else { cg.fill(CGRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 2)) }
                }
            } else {
                cg.setStrokeColor(live.color.cgColor)
                cg.setLineWidth(live.width * z)
                let pts = live.points.map { overlayPoint($0, on: live.page) }
                let p0 = live.points.first ?? .zero, p1 = live.points.last ?? p0
                let pageRect = CGRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y), width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
                if pts.count >= 2, [Tool.rect, .redact, .ellipse, .cloud, .line, .arrow, .dblarrow, .callout].contains(live.tool) {
                    switch live.tool {
                    case .rect, .redact:
                        cg.stroke(overlayRect(pageRect, on: live.page))
                    case .ellipse:
                        cg.strokeEllipse(in: overlayRect(pageRect, on: live.page))
                    case .cloud:
                        // The cloud as it will be committed.
                        if pageRect.width > 2 && pageRect.height > 2 {
                            strokePolyline(cg, MarkupGeometry.cloudPoints(pageRect).map { overlayPoint($0, on: live.page) }, close: true)
                        }
                    case .line, .arrow, .dblarrow:
                        let a = overlayPoint(p0, on: live.page), b = overlayPoint(p1, on: live.page)
                        cg.move(to: a); cg.addLine(to: b); cg.strokePath()
                        let head = max(10, live.width * 4) * z
                        if live.tool == .arrow || live.tool == .dblarrow { strokeArrowHead(cg, tip: b, from: a, size: head) }
                        if live.tool == .dblarrow { strokeArrowHead(cg, tip: a, from: b, size: head) }
                    case .callout:
                        drawCalloutPreview(cg, tip: p0, at: p1, page: live.page, color: live.color, width: live.width, z: z)
                    default: break
                    }
                } else if !pts.isEmpty {
                    cg.move(to: pts[0])
                    if pts.count == 1 { cg.addLine(to: CGPoint(x: pts[0].x + 0.1, y: pts[0].y)) }
                    for p in pts.dropFirst() { cg.addLine(to: p) }
                    cg.strokePath()
                }
            }
            cg.restoreGState()
        }

        // Eraser outline while erasing
        if let ep = mk.eraserPoint, let page = mk.eraserPage {
            let r = CGFloat(max(2, editor.style(for: .eraser).width / 2)) * z
            let c = overlayPoint(ep, on: page)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            cg.saveGState()
            cg.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor); cg.fillEllipse(in: rect)
            cg.setStrokeColor(UIColor(white: 0.15, alpha: 0.8).cgColor); cg.setLineWidth(1.5 * u); cg.strokeEllipse(in: rect)
            cg.restoreGState()
        }

        // Polyline being placed: segments so far, a dot on every vertex, a ring on the last one (tap it to finish).
        if let page = mk.polyPage, !mk.polyPoints.isEmpty {
            let st = editor.style(for: .polyline)
            let pts = mk.polyPoints.map { overlayPoint($0, on: page) }
            cg.saveGState()
            cg.setStrokeColor(PDFColors.uiColor(st.color).cgColor); cg.setLineWidth(CGFloat(st.width) * z)
            cg.setLineCap(.round); cg.setLineJoin(.round)
            if pts.count >= 2 { strokePolyline(cg, pts, close: false) }
            cg.setFillColor(UIColor.white.cgColor); cg.setLineWidth(2 * u)
            for p in pts { let r = CGRect(x: p.x - 4 * u, y: p.y - 4 * u, width: 8 * u, height: 8 * u); cg.fillEllipse(in: r); cg.strokeEllipse(in: r) }
            if let l = pts.last { cg.setStrokeColor(accent.cgColor); cg.strokeEllipse(in: CGRect(x: l.x - 9 * u, y: l.y - 9 * u, width: 18 * u, height: 18 * u)) }
            cg.restoreGState()
        }

        // Marquee / lasso
        if let page = mk.lassoPage {
            cg.saveGState()
            cg.setStrokeColor(accent.cgColor); cg.setFillColor(accent.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1.5 * u); cg.setLineDash(phase: 0, lengths: [6 * u, 4 * u])
            if let m = mk.marquee { let r = overlayRect(m, on: page); cg.fill(r); cg.stroke(r) }
            else if mk.lasso.count > 1 {
                let pts = mk.lasso.map { overlayPoint($0, on: page) }
                cg.move(to: pts[0]); for p in pts.dropFirst() { cg.addLine(to: p) }; cg.closePath()
                cg.drawPath(using: .fillStroke)
            }
            cg.restoreGState()
        }

        // Comment badges on annotations that carry text or replies
        for page in visiblePages(v) {
            let replied = editor.mkRepliedParents(on: page)
            for a in page.annotations where a.isPrimary && !a.isWidget && editor.mkHasComment(a, replied: replied) {
                drawBadge(cg, at: badgeCenter(for: a, on: page), color: a.color, u: u)
            }
        }

        // Selection
        if let first = mk.selected.first, let page = first.page {
            cg.saveGState()
            cg.setStrokeColor(accent.cgColor); cg.setLineWidth(2 * u)
            for a in mk.selected { cg.stroke(overlayRect(a.bounds, on: page).insetBy(dx: -3 * u, dy: -3 * u)) }
            if let b = editor.mkSelectionBounds, !editor.mkMovableSelection.isEmpty {
                let r = overlayRect(b, on: page)
                drawHandle(cg, at: CGPoint(x: r.maxX + 8 * u, y: r.maxY + 8 * u), accent: accent, u: u)
                if let box = mk.selected.first(where: { $0.redlineTool == .callout && $0.subtype == "FreeText" }), let leader = editor.mkLeader(for: box, on: page) {
                    let pts = editor.mkLeaderPoints(leader)
                    if pts.count >= 3 {
                        drawHandle(cg, at: overlayPoint(pts[2], on: page), accent: accent, u: u)
                        drawHandle(cg, at: overlayPoint(pts[1], on: page), accent: accent, u: u)
                    }
                }
            }
            cg.restoreGState()
        }

        // Ruler
        if editor.ruler.on, let page = editor.mk.page(editor.pageIndex) { drawRuler(cg, page: page, accent: accent) }
    }

    private func visiblePages(_ v: PDFStackView) -> [PDFPage] { v.visiblePages }

    private func strokePolyline(_ cg: CGContext, _ pts: [CGPoint], close: Bool) {
        guard let f = pts.first else { return }
        cg.move(to: f)
        for p in pts.dropFirst() { cg.addLine(to: p) }
        if close { cg.closePath() }
        cg.strokePath()
    }

    /// Open arrow head (two strokes) at `tip`, pointing away from `from`.
    private func strokeArrowHead(_ cg: CGContext, tip: CGPoint, from: CGPoint, size: CGFloat) {
        let ang = atan2(tip.y - from.y, tip.x - from.x)
        cg.move(to: CGPoint(x: tip.x - size * cos(ang - 0.45), y: tip.y - size * sin(ang - 0.45)))
        cg.addLine(to: tip)
        cg.addLine(to: CGPoint(x: tip.x - size * cos(ang + 0.45), y: tip.y - size * sin(ang + 0.45)))
        cg.strokePath()
    }

    /// The callout as it will be committed: arrow at the tip, leader to the elbow, and the empty box at the drag point.
    private func drawCalloutPreview(_ cg: CGContext, tip: CGPoint, at b: CGPoint, page: PDFPage, color: UIColor, width: CGFloat, z: CGFloat) {
        let st = editor.style(for: .callout)
        let L = editor.mkCalloutLayout(tip: tip, at: b, style: st)
        let lw = max(1.5, width * 0.35) * z
        cg.setLineWidth(lw); cg.setLineCap(.round); cg.setLineJoin(.round)
        let t = overlayPoint(tip, on: page), e = overlayPoint(L.elbow, on: page), a = overlayPoint(L.attach, on: page)
        cg.move(to: a); cg.addLine(to: e); cg.addLine(to: t); cg.strokePath()
        strokeArrowHead(cg, tip: t, from: e, size: max(10, lw * 4))
        let box = overlayRect(L.box, on: page)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 6 * z).cgPath
        if let bg = L.textStyle.background, (L.textStyle.backgroundOpacity ?? 1) > 0.005 {
            cg.setFillColor(PDFColors.uiColor(bg, alpha: L.textStyle.backgroundOpacity ?? 1).cgColor)
            cg.addPath(path); cg.fillPath()
        }
        cg.setLineWidth(CGFloat(L.textStyle.borderWidth ?? 1) * z)
        cg.addPath(path); cg.strokePath()
    }

    private func drawHandle(_ cg: CGContext, at p: CGPoint, accent: UIColor, u: CGFloat = 1) {
        let r = CGRect(x: p.x - 11 * u, y: p.y - 11 * u, width: 22 * u, height: 22 * u)
        cg.setShadow(offset: CGSize(width: 0, height: 1 * u), blur: 3 * u, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: r)
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.setStrokeColor(accent.cgColor); cg.setLineWidth(2.5 * u); cg.strokeEllipse(in: r.insetBy(dx: 1.25 * u, dy: 1.25 * u))
    }

    /// 20 pt Tabler `bubble-text` in the annotation's colour: fill mixed 72 % toward white, stroke mixed 28 %, 2 pt, soft shadow.
    private func drawBadge(_ cg: CGContext, at c: CGPoint, color: UIColor, u: CGFloat = 1) {
        let fill = MarkupOverlayView.mix(color, towardWhite: 0.72), stroke = MarkupOverlayView.mix(color, towardWhite: 0.28)
        let k: CGFloat = 20 / 24 * u
        cg.saveGState()
        cg.translateBy(x: c.x - 10 * u, y: c.y - 10 * u)
        let body = Glyphs.cgPath(Glyphs.bubble, scale: k)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        cg.setFillColor(fill.cgColor); cg.addPath(body); cg.fillPath()
        cg.restoreGState()
        cg.setStrokeColor(stroke.cgColor); cg.setLineWidth(2 * k); cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.addPath(body); cg.strokePath()
        cg.addPath(Glyphs.cgPath(Glyphs.bubbleLines, scale: k)); cg.strokePath()
        cg.restoreGState()
    }

    static func mix(_ c: UIColor, towardWhite t: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if !c.getRed(&r, green: &g, blue: &b, alpha: &a) { var w: CGFloat = 0; _ = c.getWhite(&w, alpha: &a); r = w; g = w; b = w }
        return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: 1)
    }

    private func drawRuler(_ cg: CGContext, page: PDFPage, accent: UIColor) {
        let r = editor.ruler
        let scale = PDFService.displaySize(page).width / 1000
        let L = 820 * scale, H = 72 * scale
        let a = r.angle * .pi / 180
        let d = CGPoint(x: cos(a), y: -sin(a)), n = CGPoint(x: sin(a), y: cos(a))
        let c = CGPoint(x: r.x, y: r.y)
        func pt(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            overlayPoint(CGPoint(x: c.x + d.x * along + n.x * across, y: c.y + d.y * along + n.y * across), on: page)
        }
        let corners = [pt(-L / 2, -H / 2), pt(L / 2, -H / 2), pt(L / 2, H / 2), pt(-L / 2, H / 2)]
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.18).cgColor)
        cg.setFillColor(UIColor(white: 0.97, alpha: 0.9).cgColor)
        cg.move(to: corners[0]); for p in corners.dropFirst() { cg.addLine(to: p) }; cg.closePath(); cg.fillPath()
        cg.restoreGState()
        let u = unit
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.25).cgColor); cg.setLineWidth(1 * u)
        cg.move(to: corners[0]); for p in corners.dropFirst() { cg.addLine(to: p) }; cg.closePath(); cg.strokePath()
        // ticks
        cg.setStrokeColor(UIColor.darkGray.cgColor); cg.setLineWidth(1 * u)
        let n10 = Int(L / (10 * scale))
        for i in 0...n10 {
            let along = -L / 2 + CGFloat(i) * 10 * scale
            let len = CGFloat(i % 10 == 0 ? 14 : (i % 5 == 0 ? 10 : 6)) * scale
            cg.move(to: pt(along, -H / 2)); cg.addLine(to: pt(along, -H / 2 + len))
            cg.move(to: pt(along, H / 2)); cg.addLine(to: pt(along, H / 2 - len))
        }
        cg.strokePath()
        // handles + lock pill
        let sf = pdfView?.scaleFactor ?? 1
        drawHandle(cg, at: pt(-L / 2 + 30 / sf, 0), accent: UIColor.darkGray, u: u)
        drawHandle(cg, at: pt(L / 2 - 30 / sf, 0), accent: UIColor.darkGray, u: u)
        let deg = Int((r.angle > 90 ? 180 - r.angle : r.angle).rounded())
        let label = "\(deg)°  \(r.lock ? "Locked" : "Lock")" as NSString
        let font = UIFont.systemFont(ofSize: 13, weight: .bold)
        let size = label.size(withAttributes: [.font: font])
        let center = pt(0, 0)
        // The pill keeps its screen size: draw it in screen units around the ruler centre.
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y); cg.scaleBy(x: u, y: u)
        let pill = CGRect(x: -size.width / 2 - 12, y: -14, width: size.width + 24, height: 28)
        cg.setFillColor((r.lock ? accent : UIColor.white).cgColor)
        cg.addPath(UIBezierPath(roundedRect: pill, cornerRadius: 14).cgPath); cg.fillPath()
        cg.setLineWidth(1)
        cg.setStrokeColor((r.lock ? accent : UIColor.black.withAlphaComponent(0.2)).cgColor)
        cg.addPath(UIBezierPath(roundedRect: pill, cornerRadius: 14).cgPath); cg.strokePath()
        UIGraphicsPushContext(cg)
        label.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 6), withAttributes: [.font: font, .foregroundColor: r.lock ? UIColor.white : UIColor.darkGray])
        UIGraphicsPopContext()
        cg.restoreGState()
    }
}
