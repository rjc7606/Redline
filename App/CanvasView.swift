import SwiftUI
import UIKit
import RedlineCore

extension WorkspaceModel {
    /// Snapshot of everything the page renderer needs (read in `body` so Observation tracks it).
    func renderInput(page i: Int, zoom z: Double, interactive: Bool) -> PageRenderInput {
        let pg = doc.pages[min(i, doc.pages.count - 1)]
        var pdf: UIImage? = nil
        _ = app.pdf.revision   // re-render when a background page render finishes
        if type == .markup, let f = doc.pdfFile { pdf = app.pdfImage(file: f, pageIndex: pg.pdfPageIndex ?? i, canvas: canvas) }
        let showLive = interactive && i == dragPage
        var badges: Set<ID> = []
        if type == .markup {
            let commented = Set(doc.comments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.replies.isEmpty }.map(\.id))
            var seen: Set<ID> = []
            for s in pg.strokes { if let cid = s.commentID, commented.contains(cid), !seen.contains(cid) { seen.insert(cid); badges.insert(s.id) } }
        }
        return PageRenderInput(
            page: pg, docType: type, canvas: canvas, transform: pageTransform(page: i), zoom: z, activeLayer: activeLayer,
            live: showLive ? live : nil, selection: interactive && i == pageIndex ? selection : [],
            eraseHits: showLive ? eraseHits : [], highlightComment: interactive ? selectedComment : nil,
            selectedField: interactive ? selectedField : nil, showFieldTags: interactive && onFormsTab,
            lasso: showLive ? lasso : nil, marquee: showLive ? marquee : nil, blueprint: app.settings.blueprint, pdfImage: pdf,
            pdfLoading: type == .markup && doc.pdfFile != nil && pdf == nil, drawingPaper: doc.paper, accentHex: app.settings.theme == .dark ? "#6C96E0" : "#2F6FE4", showSelection: interactive, commentBadges: badges,
            coverTitle: type == .journal && i == 0 ? doc.name : nil, coverHex: type == .journal && i == 0 ? doc.coverHex : nil)
    }
}

/// The page drawn by the shared renderer.
struct PageCanvas: View {
    var input: PageRenderInput
    var size: CGSize
    /// Off-main-thread drawing for thumbnails and previews (interactive pages stay synchronous for Pencil latency).
    var async: Bool = false
    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: async) { ctx, sz in
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
    /// Pinch / two-finger pan handled by the page itself (notebooks). Off inside the native scroll view.
    var ownGestures = true
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
                    onPencilTap: { editor.pencilDoubleTap() },
                    nativeGestures: ownGestures
                )
                .frame(width: size.width, height: size.height)
                if let te = editor.textEdit, te.page == pageIndex {
                    InlineTextEditor(editor: editor, pageIndex: pageIndex, anchor: te.anchor)
                }
                if pageIndex == editor.pageIndex, editor.selection.count == 1, editor.textEdit == nil,
                   let lead = editor.currentStrokes.first(where: { editor.selection.contains($0.id) }), lead.tool == .callout, lead.points.count >= 3 {
                    ForEach([0, 1], id: \.self) { idx in
                        LeaderHandle(editor: editor, pageIndex: pageIndex, stroke: lead, index: idx, space: space)
                    }
                }
                if editor.annotationPopup, pageIndex == editor.pageIndex, editor.textEdit == nil {
                    AnnotationPopup(editor: editor, pageIndex: pageIndex)
                }
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

/// Editable text box drawn on the page at the tap point (Return or tapping elsewhere commits).
struct InlineTextEditor: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel
    var pageIndex: Int
    var anchor: Point
    @FocusState private var focused: Bool

    var body: some View {
        let z = editor.zoom
        let st = editor.textEditStyle()
        let fs = st.fs * z
        let vp = editor.viewPoint(fromPage: anchor, page: pageIndex)
        HStack(alignment: .top, spacing: 4 * z) {
            TextField("Text", text: $editor.textDraft, axis: .vertical)
                .font(textFont(st.font, size: fs, weight: st.weight))
                .foregroundStyle(Color(hex: st.color))
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .frame(width: max(120, 240 * z))
                .focused($focused)
                .onSubmit { editor.commitTextEdit() }
            Button { editor.commitTextEdit() } label: {
                Image(systemName: "checkmark").font(.system(size: max(11, 12 * z), weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(theme.accent))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 6 * z).padding(.vertical, 3 * z)
        .background(RoundedRectangle(cornerRadius: 3 * z).fill(Color(hex: st.bg ?? "#ffffff", alpha: st.bgo)))
        .overlay(RoundedRectangle(cornerRadius: 3 * z).stroke(Color(hex: st.bc, alpha: st.bco), lineWidth: max(1, st.bw * z)))
        .overlay(RoundedRectangle(cornerRadius: 3 * z).stroke(theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).padding(-3))
        .fixedSize(horizontal: false, vertical: true)
        .offset(x: vp.x - 6 * z, y: vp.y - fs - 3 * z)
        .onAppear { focused = true }
    }
}

/// Drag handle for a leader's arrow tip (index 0) or elbow (index 1).
struct LeaderHandle: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var pageIndex: Int
    var stroke: Stroke
    var index: Int
    var space: String
    @State private var dragging = false

    var body: some View {
        let vp = editor.viewPoint(fromPage: stroke.points[index].point, page: pageIndex)
        Circle()
            .fill(theme.card)
            .overlay(Circle().strokeBorder(theme.accent, lineWidth: 2.5))
            .overlay(Image(systemName: index == 0 ? "arrow.up.left" : "arrow.left.and.right").font(fnt(10, .bold)).foregroundStyle(theme.accent))
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .position(vp)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { v in
                        if !dragging { dragging = true; editor.beginHandle(stroke.id, index: index) }
                        editor.dragHandle(to: v.location, page: pageIndex)
                    }
                    .onEnded { _ in dragging = false; editor.endHandle() }
            )
            .accessibilityLabel(index == 0 ? "Arrow tip" : "Elbow")
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
    var nativeGestures: Bool = true

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        apply(v)
        return v
    }
    func updateUIView(_ v: TouchView, context: Context) { apply(v) }
    private func apply(_ v: TouchView) {
        v.onDown = onDown; v.onMove = onMove; v.onUp = onUp; v.onCancel = onCancel; v.onPinch = onPinch; v.onPan = onPan
        v.onPencilTap = onPencilTap
        v.gesturesEnabled = nativeGestures
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
    /// When false (inside the pages scroll view) the scroll view owns pinch and two-finger pan.
    var gesturesEnabled = true { didSet { pinch.isEnabled = gesturesEnabled; pan.isEnabled = gesturesEnabled } }
    private let pinch = UIPinchGestureRecognizer()
    private let pan = UIPanGestureRecognizer()

    private var active: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        pinch.addTarget(self, action: #selector(pinched(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        pan.addTarget(self, action: #selector(panned(_:)))
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
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        ZStack {
            theme.canvas
            PagesScrollView(editor: editor, app: app, theme: theme)
        }
        .clipped()
        .overlay(alignment: .top) { if !editor.selection.isEmpty && !editor.organizeOpen { SelectionBar(editor: editor).padding(.top, 14) } }
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
