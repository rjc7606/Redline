import SwiftUI
import UIKit
import PDFKit
import RedlineCore

/// PDFKit viewer plus a transparent input/drawing overlay, with SwiftUI overlays for the comment popup and
/// the inline text editor. Finger scroll/zoom is native (bounce, direction lock); the Pencil goes to the pages.
struct MarkupCanvas: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        let mk = editor.mk
        ZStack(alignment: .topLeading) {
            theme.canvas
            PDFViewRepresentable(editor: editor, tick: mk.renderTick, viewportTick: mk.viewportTick, canvasColor: UIColor(hex: theme.tokens.canvas))
            if let te = mk.textEdit { PDFTextEditor(editor: editor, edit: te) }
            if mk.annotationPopup, mk.textEdit == nil { PDFAnnotationPopup(editor: editor) }
        }
        .clipped()
        .overlay(alignment: .top) {
            if !mk.selected.isEmpty && !editor.organizeOpen {
                HStack(spacing: 2) {
                    Text(mk.selected.filter(\.isPrimary).count <= 1 ? "1 selected" : "\(mk.selected.filter(\.isPrimary).count) selected")
                        .font(fnt(12.5, .bold)).foregroundStyle(theme.ink3).padding(.leading, 8).padding(.trailing, 10)
                    Button { editor.mkDeleteSelection() } label: {
                        Label("Delete", systemImage: "trash").font(fnt(13, .semibold)).foregroundStyle(theme.danger).padding(.horizontal, 12).frame(height: 36)
                    }.buttonStyle(.plain)
                    Button { editor.mkClearSelection() } label: {
                        Image(systemName: "xmark").font(fnt(15, .semibold)).foregroundStyle(theme.ink3).frame(width: 36, height: 36)
                    }.buttonStyle(.plain)
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.popSolid).shadow(color: .black.opacity(0.18), radius: 9, y: 4))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .padding(.top, 14)
            }
        }
    }
}

// MARK: - PDFView

struct PDFViewRepresentable: UIViewRepresentable {
    var editor: WorkspaceModel
    var tick: Int
    var viewportTick: Int
    var canvasColor: UIColor

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = true
        v.pageBreakMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        v.pageShadowsEnabled = true
        v.backgroundColor = canvasColor
        v.minScaleFactor = 0.25
        v.maxScaleFactor = 6
        v.document = editor.mk.pdf
        editor.mk.pdfView = v
        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== editor.mk.pdf { v.document = editor.mk.pdf }
        v.backgroundColor = canvasColor
        context.coordinator.editor = editor
        context.coordinator.ensureOverlay(in: v)
        context.coordinator.overlay.setNeedsDisplay()
        if let i = editor.mk.scrollToPage {
            context.coordinator.scroll(to: i, in: v)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var editor: WorkspaceModel
        let overlay: MarkupOverlayView
        private var observers: [NSObjectProtocol] = []
        private var offsetObservation: NSKeyValueObservation?
        private var pendingScroll: Int? = nil

        init(editor: WorkspaceModel) {
            self.editor = editor
            self.overlay = MarkupOverlayView(editor: editor)
            super.init()
        }

        /// Called from `dismantleUIView` (main actor) — a nonisolated deinit may not touch these.
        func detach() {
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
            offsetObservation?.invalidate()
            offsetObservation = nil
            overlay.removeFromSuperview()
        }

        func attach(to v: PDFView) {
            overlay.pdfView = v
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .PDFViewScaleChanged, object: v, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewportChanged() }
            })
            observers.append(center.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pageChanged(v) }
            })
            if let sv = v.subviews.compactMap({ $0 as? UIScrollView }).first {
                let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                sv.panGestureRecognizer.allowedTouchTypes = direct
                sv.pinchGestureRecognizer?.allowedTouchTypes = direct
                // Free panning in any direction; vertical always rubber-bands, horizontal only when the page is wider than the view.
                sv.alwaysBounceVertical = true
                sv.alwaysBounceHorizontal = false
                sv.isDirectionalLockEnabled = false
                sv.delaysContentTouches = false
                sv.canCancelContentTouches = true
                offsetObservation = sv.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.viewportChanged() }
                }
            }
            ensureOverlay(in: v)
        }

        /// Keeps the drawing overlay on top of PDFKit's document view (which PDFKit may recreate).
        func ensureOverlay(in v: PDFView) {
            guard let dv = v.documentView else { return }
            if overlay.superview !== dv {
                overlay.removeFromSuperview()
                overlay.frame = dv.bounds
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                dv.addSubview(overlay)
            } else if overlay.frame != dv.bounds {
                overlay.frame = dv.bounds
            }
        }

        private func viewportChanged() {
            editor.mk.viewportTick += 1
            if let v = overlay.pdfView { ensureOverlay(in: v) }
            overlay.setNeedsDisplay()
        }

        private func pageChanged(_ v: PDFView) {
            viewportChanged()
            guard pendingScroll == nil, let p = v.currentPage, let pdf = editor.mk.pdf else { return }
            let i = pdf.index(for: p)
            if i != editor.pageIndex { editor.pageIndex = i }
        }

        func scroll(to i: Int, in v: PDFView) {
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
    weak var pdfView: PDFView?
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
                return
            }
            editor.mkPointerDown(s, page: page, at: p)
            setNeedsDisplay()
        } else if active != nil {
            active = nil
            dragPage = nil
            editor.mkPointerCancel()
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
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        active = nil
        dragPage = nil
        editor.mkPointerCancel()
        setNeedsDisplay()
    }

    private enum HandleHit { case resize, leader(PDFAnnotation, Int) }

    private func handleHit(at loc: CGPoint, page: PDFPage) -> HandleHit? {
        guard editor.tool == .select, !editor.mk.selected.isEmpty, let sel = editor.mk.selected.first, sel.page === page else { return nil }
        if let box = editor.mk.selected.first(where: { $0.redlineTool == .callout && $0.subtype == "FreeText" }), let leader = editor.mkLeader(for: box, on: page) {
            let pts = editor.mkLeaderPoints(leader)
            if pts.count >= 3 {
                let tip = overlayPoint(pts[2], on: page), elbow = overlayPoint(pts[1], on: page)
                if hypot(loc.x - tip.x, loc.y - tip.y) <= 18 { return .leader(leader, 0) }
                if hypot(loc.x - elbow.x, loc.y - elbow.y) <= 18 { return .leader(leader, 1) }
            }
        }
        if let b = editor.mkSelectionBounds {
            let r = overlayRect(b, on: page)
            let h = CGPoint(x: r.maxX + 8, y: r.maxY + 8)
            if hypot(loc.x - h.x, loc.y - h.y) <= 18 { return .resize }
        }
        return nil
    }

    // MARK: drawing

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext(), let v = pdfView else { return }
        let mk = editor.mk
        let accent = UIColor(hex: "#007AFF")
        let z = v.scaleFactor

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
                if live.tool == .rect || live.tool == .ellipse || live.tool == .redact || live.tool == .cloud, pts.count >= 2 {
                    let r = CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y), width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y))
                    if live.tool == .ellipse { cg.strokeEllipse(in: r) } else { cg.stroke(r) }
                } else if !pts.isEmpty {
                    cg.move(to: pts[0])
                    if pts.count == 1 { cg.addLine(to: CGPoint(x: pts[0].x + 0.1, y: pts[0].y)) }
                    for p in pts.dropFirst() { cg.addLine(to: p) }
                    cg.strokePath()
                }
            }
            cg.restoreGState()
        }

        // Marquee / lasso
        if let page = mk.lassoPage {
            cg.saveGState()
            cg.setStrokeColor(accent.cgColor); cg.setFillColor(accent.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1.5); cg.setLineDash(phase: 0, lengths: [6, 4])
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
            for a in page.annotations where a.isPrimary && !a.isWidget && editor.mkHasComment(a, on: page) {
                let r = overlayRect(a.bounds, on: page)
                drawBadge(cg, at: CGPoint(x: r.maxX, y: r.minY), accent: accent)
            }
        }

        // Selection
        if let first = mk.selected.first, let page = first.page {
            cg.saveGState()
            cg.setStrokeColor(accent.cgColor); cg.setLineWidth(2)
            for a in mk.selected { cg.stroke(overlayRect(a.bounds, on: page).insetBy(dx: -3, dy: -3)) }
            if let b = editor.mkSelectionBounds, editor.tool == .select {
                let r = overlayRect(b, on: page)
                drawHandle(cg, at: CGPoint(x: r.maxX + 8, y: r.maxY + 8), accent: accent)
                if let box = mk.selected.first(where: { $0.redlineTool == .callout && $0.subtype == "FreeText" }), let leader = editor.mkLeader(for: box, on: page) {
                    let pts = editor.mkLeaderPoints(leader)
                    if pts.count >= 3 {
                        drawHandle(cg, at: overlayPoint(pts[2], on: page), accent: accent)
                        drawHandle(cg, at: overlayPoint(pts[1], on: page), accent: accent)
                    }
                }
            }
            cg.restoreGState()
        }

        // Ruler
        if editor.ruler.on, let page = editor.mk.page(editor.pageIndex) { drawRuler(cg, page: page, accent: accent) }
    }

    private func visiblePages(_ v: PDFView) -> [PDFPage] {
        guard let pdf = v.document, let cur = v.currentPage else { return [] }
        let i = pdf.index(for: cur)
        return [i - 1, i, i + 1].compactMap { $0 >= 0 && $0 < pdf.pageCount ? pdf.page(at: $0) : nil }
    }

    private func drawHandle(_ cg: CGContext, at p: CGPoint, accent: UIColor) {
        let r = CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: r)
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.setStrokeColor(accent.cgColor); cg.setLineWidth(2.5); cg.strokeEllipse(in: r.insetBy(dx: 1.25, dy: 1.25))
    }

    private func drawBadge(_ cg: CGContext, at c: CGPoint, accent: UIColor) {
        let r: CGFloat = 9
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        cg.setFillColor(accent.cgColor); cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        cg.restoreGState()
        cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(1.5); cg.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        cg.setFillColor(UIColor.white.cgColor)
        for dx in [-0.42, 0.0, 0.42] { cg.fillEllipse(in: CGRect(x: c.x + dx * r - 0.15 * r, y: c.y - 0.15 * r, width: 0.3 * r, height: 0.3 * r)) }
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
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.25).cgColor); cg.setLineWidth(1)
        cg.move(to: corners[0]); for p in corners.dropFirst() { cg.addLine(to: p) }; cg.closePath(); cg.strokePath()
        // ticks
        cg.setStrokeColor(UIColor.darkGray.cgColor); cg.setLineWidth(1)
        let n10 = Int(L / (10 * scale))
        for i in 0...n10 {
            let along = -L / 2 + CGFloat(i) * 10 * scale
            let len = CGFloat(i % 10 == 0 ? 14 : (i % 5 == 0 ? 10 : 6)) * scale
            cg.move(to: pt(along, -H / 2)); cg.addLine(to: pt(along, -H / 2 + len))
            cg.move(to: pt(along, H / 2)); cg.addLine(to: pt(along, H / 2 - len))
        }
        cg.strokePath()
        // handles + lock pill
        let z = pdfView?.scaleFactor ?? 1
        drawHandle(cg, at: pt(-L / 2 + 30 / z, 0), accent: UIColor.darkGray)
        drawHandle(cg, at: pt(L / 2 - 30 / z, 0), accent: UIColor.darkGray)
        let deg = Int((r.angle > 90 ? 180 - r.angle : r.angle).rounded())
        let label = "\(deg)°  \(r.lock ? "Locked" : "Lock")" as NSString
        let font = UIFont.systemFont(ofSize: 13, weight: .bold)
        let size = label.size(withAttributes: [.font: font])
        let center = pt(0, 0)
        let pill = CGRect(x: center.x - size.width / 2 - 12, y: center.y - 14, width: size.width + 24, height: 28)
        cg.setFillColor((r.lock ? accent : UIColor.white).cgColor)
        cg.addPath(UIBezierPath(roundedRect: pill, cornerRadius: 14).cgPath); cg.fillPath()
        cg.setStrokeColor((r.lock ? accent : UIColor.black.withAlphaComponent(0.2)).cgColor)
        cg.addPath(UIBezierPath(roundedRect: pill, cornerRadius: 14).cgPath); cg.strokePath()
        label.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 6), withAttributes: [.font: font, .foregroundColor: r.lock ? UIColor.white : UIColor.darkGray])
    }
}
