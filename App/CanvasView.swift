import SwiftUI
import UIKit
import RedlineCore

extension WorkspaceModel {
    /// Snapshot of everything the page renderer needs (read in `body` so Observation tracks it).
    func renderInput(page i: Int, zoom z: Double, interactive: Bool) -> PageRenderInput {
        let pg = doc.pages[min(i, doc.pages.count - 1)]
        var pdf: UIImage? = nil
        if type == .markup, let f = doc.pdfFile { pdf = app.pdfImage(file: f, pageIndex: pg.pdfPageIndex ?? i, canvas: canvas) }
        let showLive = interactive && i == dragPage
        return PageRenderInput(
            page: pg, docType: type, canvas: canvas, transform: pageTransform(page: i), zoom: z, activeLayer: activeLayer,
            live: showLive ? live : nil, selection: interactive && i == pageIndex ? selection : [],
            eraseHits: showLive ? eraseHits : [], highlightComment: interactive ? selectedComment : nil,
            selectedField: interactive ? selectedField : nil, showFieldTags: interactive && onFormsTab,
            lasso: showLive ? lasso : nil, marquee: showLive ? marquee : nil, blueprint: app.settings.blueprint, pdfImage: pdf,
            drawingPaper: doc.paper, accentHex: app.settings.theme == .dark ? "#0A84FF" : "#007AFF", showSelection: interactive)
    }
}

/// The page drawn by the shared renderer.
struct PageCanvas: View {
    var input: PageRenderInput
    var size: CGSize
    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, sz in
            PageRenderer.draw(input, in: ctx, size: sz)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One page at the editor's zoom, with Pencil/finger input and the resize handle.
struct PageView: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var pageIndex: Int
    var interactive = true
    @State private var scaling = false

    var body: some View {
        let z = editor.zoom
        let f = editor.frameSize(page: pageIndex)
        let size = CGSize(width: f.width * z, height: f.height * z)
        let input = editor.renderInput(page: pageIndex, zoom: z, interactive: interactive)
        let space = "page-\(pageIndex)"
        ZStack(alignment: .topLeading) {
            PageCanvas(input: input, size: size)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            if interactive {
                CanvasInputView(
                    onDown: { editor.pointerDown($0, page: pageIndex) },
                    onMove: { editor.pointerMove($0, page: pageIndex) },
                    onUp: { editor.pointerUp($0, page: pageIndex) },
                    onCancel: { editor.pointerCancel() },
                    onPinch: { editor.pinch(by: $0) },
                    onPan: { editor.panBy($0) },
                    onPencilTap: { editor.pencilDoubleTap() }
                )
                .frame(width: size.width, height: size.height)
                if editor.ruler.on, pageIndex == editor.pageIndex {
                    // Display only: finger touches on it are routed through the canvas input (Pencil passes through to draw).
                    RulerView(editor: editor, pageIndex: pageIndex).allowsHitTesting(false)
                }
                if pageIndex == editor.pageIndex, editor.selection.count == 1, editor.tool == .select || editor.tool == .lasso,
                   let b = editor.selectionBounds {
                    let hp = editor.viewPoint(fromPage: Point(b.maxX, b.maxY), page: pageIndex)
                    Circle()
                        .fill(theme.card)
                        .overlay(Circle().strokeBorder(theme.accent, lineWidth: 2.5))
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .position(x: hp.x + 8, y: hp.y + 8)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                                .onChanged { v in
                                    if !scaling { scaling = true; editor.beginScale(page: pageIndex, handle: v.startLocation) }
                                    editor.pointerMove(PointerSample(location: v.location, pressure: 0.5, isPencil: false), page: pageIndex)
                                }
                                .onEnded { v in
                                    scaling = false
                                    editor.pointerUp(PointerSample(location: v.location, pressure: 0.5, isPencil: false), page: pageIndex)
                                }
                        )
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: space)
    }
}

// MARK: - UIKit input (Apple Pencil pressure, two-finger pan/pinch)

struct CanvasInputView: UIViewRepresentable {
    var onDown: (PointerSample) -> Void
    var onMove: (PointerSample) -> Void
    var onUp: (PointerSample) -> Void
    var onCancel: () -> Void
    var onPinch: (Double) -> Void
    var onPan: (CGSize) -> Void
    var onPencilTap: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        apply(v)
        return v
    }
    func updateUIView(_ v: TouchView, context: Context) { apply(v) }
    private func apply(_ v: TouchView) {
        v.onDown = onDown; v.onMove = onMove; v.onUp = onUp; v.onCancel = onCancel; v.onPinch = onPinch; v.onPan = onPan
        v.onPencilTap = onPencilTap
    }
}

final class TouchView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    var onDown: ((PointerSample) -> Void)?
    var onMove: ((PointerSample) -> Void)?
    var onUp: ((PointerSample) -> Void)?
    var onCancel: (() -> Void)?
    var onPinch: ((Double) -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onPencilTap: (() -> Void)?

    private var active: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Apple Pencil double-tap (honours the system "Double Tap" preference).
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        if UIPencilInteraction.preferredTapAction == .ignore { return }
        onPencilTap?()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed else { return }
        onPinch?(Double(g.scale))
        g.scale = 1
    }
    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        let t = g.translation(in: self)
        onPan?(CGSize(width: t.x, height: t.y))
        g.setTranslation(.zero, in: self)
    }

    private func sample(_ t: UITouch) -> PointerSample {
        let pencil = t.type == .pencil
        let pressure = pencil && t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 0.5
        return PointerSample(location: t.location(in: self), pressure: min(1, max(0.05, pressure)), isPencil: pencil, window: t.location(in: nil))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if active == nil, let t = touches.first, (event?.allTouches?.count ?? 1) == 1 {
            active = t
            onDown?(sample(t))
        } else if active != nil {
            active = nil
            onCancel?()
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        for c in event?.coalescedTouches(for: t) ?? [t] { onMove?(sample(c)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        active = nil
        onUp?(sample(t))
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        active = nil
        onCancel?()
    }
}

// MARK: - Sheet canvas area (Markup / Drawing)

struct SheetCanvasArea: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @State private var fitted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.canvas
                PageView(editor: editor, pageIndex: editor.pageIndex)
                    .offset(editor.pan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .onAppear { if !fitted { fitted = true; editor.fitZoom(available: geo.size) } }
            .onChange(of: geo.size) { _, s in editor.fitZoom(available: s) }
            .overlay(alignment: .top) { if !editor.selection.isEmpty && !editor.organizeOpen { SelectionBar(editor: editor).padding(.top, 14) } }
            .overlay(alignment: .bottom) { PageNavPill(editor: editor).padding(.bottom, 14) }
        }
    }
}

struct SelectionBar: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var body: some View {
        HStack(spacing: 2) {
            Text(editor.selection.count == 1 ? "1 selected" : "\(editor.selection.count) selected")
                .font(fnt(12.5, .bold)).foregroundStyle(theme.ink3).padding(.leading, 8).padding(.trailing, 10)
            Button { editor.duplicateSelection() } label: {
                Label("Duplicate", systemImage: "doc.on.doc").font(fnt(13, .semibold)).foregroundStyle(theme.ink1).padding(.horizontal, 12).frame(height: 36)
            }.buttonStyle(.plain)
            Button { editor.deleteSelection() } label: {
                Label("Delete", systemImage: "trash").font(fnt(13, .semibold)).foregroundStyle(theme.danger).padding(.horizontal, 12).frame(height: 36)
            }.buttonStyle(.plain)
            Button { editor.clearSelection() } label: {
                Image(systemName: "xmark").font(fnt(15, .semibold)).foregroundStyle(theme.ink3).frame(width: 36, height: 36)
            }.buttonStyle(.plain)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.popSolid).shadow(color: .black.opacity(0.18), radius: 9, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        .popIn()
    }
}

struct PageNavPill: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button { editor.prevPage() } label: {
                    Image(systemName: "chevron.left").font(fnt(15, .semibold)).foregroundStyle(editor.pageIndex > 0 ? theme.ink2 : theme.dis).frame(width: 34, height: 32)
                }.buttonStyle(.plain).disabled(editor.pageIndex == 0)
                Text("Page \(editor.pageIndex + 1) of \(editor.pageCount)").font(fnt(12.5, .bold)).foregroundStyle(theme.ink1).padding(.horizontal, 8)
                Button { editor.nextPage() } label: {
                    Image(systemName: "chevron.right").font(fnt(15, .semibold)).foregroundStyle(editor.pageIndex < editor.pageCount - 1 ? theme.ink2 : theme.dis).frame(width: 34, height: 32)
                }.buttonStyle(.plain).disabled(editor.pageIndex >= editor.pageCount - 1)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.popSolid).shadow(color: .black.opacity(0.18), radius: 9, y: 4))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            Text("\(Int((editor.zoom * 100).rounded()))%")
                .font(fnt(12, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: "#1e1e20", alpha: 0.82)))
        }
    }
}
