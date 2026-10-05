import SwiftUI
import UIKit
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
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
            if let pe = mk.pageTextEdit { PageTextEditBox(editor: editor, edit: pe) }
            if let fe = mk.fieldEdit { PDFFieldEditor(editor: editor, widget: fe) }
            if mk.annotationPopup, mk.textEdit == nil { PDFAnnotationPopup(editor: editor) }
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            if !mk.selected.isEmpty && !editor.organizeOpen { SelectionChrome(editor: editor) }
        }
        .overlay(alignment: .top) {
            if mk.searchOpen { PDFSearchBar(editor: editor).padding(.top, 10) }
        }
        .sheet(isPresented: Binding(get: { mk.calibratePending != nil }, set: { if !$0 { mk.calibratePending = nil } })) {
            CalibrateSheet(editor: editor)
        }
        .sheet(isPresented: Binding(get: { mk.imagePickerOn }, set: { mk.imagePickerOn = $0 })) {
            ImagePickSheet(editor: editor)
        }
        .sheet(isPresented: Binding(get: { mk.signaturePadOn }, set: { mk.signaturePadOn = $0 })) {
            SignatureSheet(editor: editor)
        }
        .sheet(isPresented: Binding(get: { mk.linkPending != nil }, set: { if !$0 { mk.linkPending = nil } })) {
            LinkSheet(editor: editor)
        }
        .sheet(isPresented: Binding(get: { mk.flattenSheet }, set: { mk.flattenSheet = $0 })) {
            FlattenSheet(editor: editor)
        }
        .sheet(isPresented: Binding(get: { mk.cropPending != nil }, set: { if !$0 { mk.cropPending = nil } })) {
            CropSheet(editor: editor)
        }
        .alert("Apply \(Formatting.plural(editor.mkPendingRedactions, "redaction"))?", isPresented: Binding(get: { mk.redactConfirm }, set: { mk.redactConfirm = $0 })) {
            Button("Apply", role: .destructive) { editor.mkApplyRedactions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The marked content is removed from the file for good. Each affected page is rebuilt as an image, so its text can no longer be selected or searched. Other annotations on those pages are kept.")
        }
    }
}

/// Find text in the PDF: field · "n of m" · previous · next · close. Hits are highlighted on the page.
struct PDFSearchBar: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @FocusState private var focused: Bool

    var body: some View {
        let mk = editor.mk
        let _ = mk.renderTick
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(fnt(14, .semibold)).foregroundStyle(theme.ink4)
            TextField("Find in document", text: Binding(get: { mk.searchQuery }, set: { editor.mkSearch($0) }))
                .font(fnt(14)).textFieldStyle(.plain).foregroundStyle(theme.ink1)
                .focused($focused)
                .onSubmit { editor.mkSearchStep(1) }
                .frame(width: 220)
            Text(mk.searchHits.isEmpty ? (mk.searchQuery.isEmpty ? "" : "No matches") : "\(mk.searchIndex + 1) of \(mk.searchHits.count)")
                .font(fnt(12, .medium)).monospacedDigit().foregroundStyle(theme.ink4).frame(minWidth: 60)
            Button { editor.mkSearchStep(-1) } label: { Image(systemName: "chevron.up").font(fnt(13, .bold)).foregroundStyle(theme.ink2).frame(width: 28, height: 28) }.buttonStyle(.plain).disabled(mk.searchHits.isEmpty)
            Button { editor.mkSearchStep(1) } label: { Image(systemName: "chevron.down").font(fnt(13, .bold)).foregroundStyle(theme.ink2).frame(width: 28, height: 28) }.buttonStyle(.plain).disabled(mk.searchHits.isEmpty)
            Button { editor.mkCloseSearch() } label: { Image(systemName: "xmark").font(fnt(12, .bold)).foregroundStyle(theme.ink3).frame(width: 28, height: 28).background(Circle().fill(theme.hov)) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            .popShadow(theme))
        .onAppear { focused = true }
        .popIn()
    }
}

/// After a calibration line: what real length it represents.
struct CalibrateSheet: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @State private var value = ""
    @State private var unit: MeasureUnit = .feet
    @FocusState private var focused: Bool

    var body: some View {
        let points = editor.mk.calibratePending ?? 0
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibrate scale").font(titleFnt(20)).foregroundStyle(theme.ink1)
            Text("The line you drew is \(String(format: "%.1f", points)) points on the page. How long is it really?").font(fnt(14)).foregroundStyle(theme.ink3)
            HStack(spacing: 10) {
                FieldText(placeholder: "Length", text: $value, height: 40, font: fnt(16)).keyboardType(.decimalPad).focused($focused).frame(width: 140)
                SegmentControl(options: MeasureUnit.allCases.map { SegmentOption(value: $0, label: $0.label) }, selection: $unit, fontSize: 12.5, vPad: 7)
            }
            Text("Measurements in this document will use this scale. Draw along a dimension or a scale bar for the best result.").font(fnt(12)).foregroundStyle(theme.ink4)
            HStack {
                Spacer()
                SecondaryButton(label: "Cancel") { editor.mk.calibratePending = nil }
                PrimaryButton(label: "Set scale") {
                    if let v = Double(value.replacingOccurrences(of: ",", with: ".")) { editor.mkApplyCalibration(points: points, value: v, unit: unit) }
                }.disabled(Double(value.replacingOccurrences(of: ",", with: ".")) == nil)
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .background(theme.bg2)
        .presentationDetents([.medium])
        .onAppear { unit = editor.mkMeasure.unit; focused = true }
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
            let isLink = mk.selectedPrimary?.isLink ?? false
            let locked = editor.mkSelectionLocked
            let canComment = primaries == 1 && !mk.annotationPopup && !isWidget && !isLink
            let canStyle = !isWidget && !isLink && !locked && editor.mkSelectedPreset() != nil
            let barW: CGFloat = 96 + (canComment ? 106 : 0) + (canStyle ? 118 : 0) + 86 + 36 + 92
            let x = min(max(8, r.midX - barW / 2), max(8, fw - barW - 8))
            let lift: CGFloat = editor.mkRotatable != nil ? 34 : 0   // leave the rotate handle clear
            let above = r.minY - 14 - 40 - lift >= 8
            let y = above ? r.minY - 14 - 40 - lift : min(r.maxY + 14, fh - 48)
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
                    Menu {
                        if !isLink {
                            Button("Duplicate", systemImage: "plus.square.on.square") { editor.mkDuplicateSelection() }
                            Button("Copy", systemImage: "doc.on.doc") { editor.mkCopySelection() }
                        }
                        if editor.mkRotatable != nil {
                            Divider()
                            Button("Rotate 90° right", systemImage: "rotate.right") { editor.mkRotateSelection(by: 90) }
                            Button("Rotate 90° left", systemImage: "rotate.left") { editor.mkRotateSelection(by: -90) }
                            if editor.mkRotatable is RedlineImage {
                                Button("Flip horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { editor.mkFlipSelection(horizontal: true) }
                                Button("Flip vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") { editor.mkFlipSelection(horizontal: false) }
                            }
                        }
                        if !isWidget && !isLink {
                            Divider()
                            Button(locked ? "Unlock" : "Lock", systemImage: locked ? "lock.open" : "lock") { editor.mkToggleLock() }
                        }
                    } label: {
                        HStack(spacing: 5) { Image(systemName: locked ? "lock.fill" : "ellipsis.circle").font(fnt(15, .medium)); Text(locked ? "Locked" : "More").font(fnt(13, .semibold)) }
                            .foregroundStyle(theme.ink1).frame(height: 40).contentShape(Rectangle())
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
            v.badgeProvider = { [weak self] page in
                guard let self else { return { _ in false } }
                let replied = self.editor.mkRepliedParents(on: page)
                let ed = self.editor
                return { a in a.isPrimary && !a.isWidget && ed.mkHasComment(a, replied: replied) }
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

final class MarkupOverlayView: UIView, UIPencilInteractionDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    unowned let editor: WorkspaceModel
    weak var pdfView: PDFStackView?
    private var active: UITouch?
    private var dragPage: PDFPage?
    /// Long press with a finger: the system edit menu (Paste; Copy / Duplicate / Delete on an annotation).
    private var pressTask: Task<Void, Never>? = nil
    private var pressStart: CGPoint = .zero
    private var pressSuppressUp = false
    private var menuTarget: (page: PDFPage, point: CGPoint)? = nil
    private var editMenu: UIEditMenuInteraction!
    /// Long press on page text with no tool (or Select): a word is selected, dragging extends it.
    private var textSelecting = false
    private var textSelAnchor: CGPoint = .zero

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
        editMenu = UIEditMenuInteraction(delegate: self)
        addInteraction(editMenu)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func longPress(at loc: CGPoint, page: PDFPage, point: CGPoint) {
        guard active != nil, editor.mkIsPanning else { return }
        let textTool = editor.tool == .none || editor.tool.info.kind == .select
        if textTool, editor.mkAnnotation(at: point, page: page) == nil, let word = page.selectionForWord(at: point), !(word.string ?? "").isEmpty {
            // Page text: select the word; dragging extends the selection, lifting shows Copy / Highlight / Edit…
            editor.mkPointerCancel()
            textSelecting = true
            textSelAnchor = point
            editor.mk.textSel = word
            editor.mk.textSelPage = page
            captureScroll(true)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            setNeedsDisplay()
            return
        }
        editor.mkPointerCancel()
        pressSuppressUp = true
        menuTarget = (page, point)
        captureScroll(false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: loc))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let ed = editor
        if menuTarget == nil, let sel = ed.mk.textSel, let page = ed.mk.textSelPage {
            var items: [UIMenuElement] = []
            items.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                MainActor.assumeIsolated { UIPasteboard.general.string = sel.string ?? ""; ed.app.flash("Copied"); ed.mkClearTextSelection() }
            })
            items.append(UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { _ in MainActor.assumeIsolated { ed.mkMarkupFromSelection(.highlighter) } })
            items.append(UIAction(title: "Underline", image: UIImage(systemName: "underline")) { _ in MainActor.assumeIsolated { ed.mkMarkupFromSelection(.underline) } })
            items.append(UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough")) { _ in MainActor.assumeIsolated { ed.mkMarkupFromSelection(.strike) } })
            if sel.selectionsByLine().count == 1 {
                items.append(UIAction(title: "Edit text", image: UIImage(systemName: "text.cursor")) { _ in
                    MainActor.assumeIsolated { ed.mkBeginPageTextEdit(page: page, lineRect: sel.bounds(for: page), text: sel.string ?? ""); ed.mkClearTextSelection() }
                })
            }
            items.append(UIAction(title: "Redact", image: UIImage(systemName: "eye.slash"), attributes: .destructive) { _ in MainActor.assumeIsolated { ed.mkRedactSelection() } })
            return UIMenu(children: items)
        }
        guard let t = menuTarget else { return nil }
        var items: [UIMenuElement] = []
        if let a = ed.mkAnnotation(at: t.point, page: t.page)?.annotation, !a.isWidget {
            items.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                MainActor.assumeIsolated { ed.mkSelect(a, on: t.page); ed.mkCopySelection() }
            })
            items.append(UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { _ in
                MainActor.assumeIsolated { ed.mkSelect(a, on: t.page); ed.mkDuplicateSelection() }
            })
            items.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                MainActor.assumeIsolated { ed.mkSelect(a, on: t.page); ed.mkDeleteSelection() }
            })
        }
        if !ed.app.clipboard.isEmpty {
            items.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                MainActor.assumeIsolated { ed.mkPaste(at: t.point) }
            })
        }
        return items.isEmpty ? nil : UIMenu(children: items)
    }

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
        let vp = v.visible(fromBounds: convert(location, to: v))
        guard let page = dragPage ?? v.page(for: vp, nearest: true) else { return nil }
        return (page, v.convert(vp, to: page))
    }

    private func overlayPoint(_ p: CGPoint, on page: PDFPage) -> CGPoint {
        guard let v = pdfView else { return .zero }
        return v.convert(v.boundsPoint(fromVisible: v.convert(p, from: page)), to: self)
    }

    private func overlayRect(_ r: CGRect, on page: PDFPage) -> CGRect {
        let pts = [r.origin, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].map { overlayPoint($0, on: page) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
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
                case .rotate: editor.mkBeginRotate(at: p)
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
            if !s.isPencil, editor.mkIsPanning {
                pressStart = s.location
                pressTask?.cancel()
                pressTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, let self else { return }
                    self.longPress(at: s.location, page: page, point: p)
                }
            }
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
        if textSelecting {
            if let (pg, p) = pageAndPoint(for: t.location(in: self)), pg === page { editor.mk.textSel = page.selection(from: textSelAnchor, to: p) }
            setNeedsDisplay()
            return
        }
        if pressTask != nil {
            let l = t.location(in: self)
            if hypot(l.x - pressStart.x, l.y - pressStart.y) > 10 { pressTask?.cancel(); pressTask = nil }
        }
        for c in event?.coalescedTouches(for: t) ?? [t] {
            let s = sample(c)
            guard let (_, p) = pageAndPoint(for: s.location) else { continue }
            editor.mkPointerMove(s, page: page, at: p)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        pressTask?.cancel(); pressTask = nil
        active = nil
        if textSelecting {
            textSelecting = false
            dragPage = nil
            captureScroll(false)
            menuTarget = nil
            if editor.mk.textSel != nil { editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: t.location(in: self))) }
            setNeedsDisplay()
            return
        }
        if pressSuppressUp { pressSuppressUp = false; dragPage = nil; return }
        let s = sample(t)
        if let page = dragPage, let (_, p) = pageAndPoint(for: s.location) { editor.mkPointerUp(s, page: page, at: p) }
        dragPage = nil
        captureScroll(false)
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = active, touches.contains(t) else { return }
        pressTask?.cancel(); pressTask = nil
        pressSuppressUp = false
        textSelecting = false
        active = nil
        dragPage = nil
        editor.mkPointerCancel()
        captureScroll(false)
        setNeedsDisplay()
    }

    private enum HandleHit { case resize, rotate, leader(PDFAnnotation, Int) }

    /// Rotate handle: above the top centre of the selection (overlay space).
    private func rotateHandlePoint(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.minY - 26 * unit) }

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
            if editor.mkRotatable != nil {
                let rp = rotateHandlePoint(r)
                if hypot(loc.x - rp.x, loc.y - rp.y) <= 18 * u { return .rotate }
            }
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
                switch editor.style(for: live.tool).lineStyle ?? .solid {
                case .dash: cg.setLineDash(phase: 0, lengths: [live.width * 3 * z, live.width * 2 * z])
                case .dot: cg.setLineDash(phase: 0, lengths: [0.01, live.width * 2.2 * z])
                case .solid: break
                }
                let pts = live.points.map { overlayPoint($0, on: live.page) }
                let p0 = live.points.first ?? .zero, p1 = live.points.last ?? p0
                let pageRect = CGRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y), width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
                if pts.count >= 2, [Tool.rect, .redact, .link, .crop, .ellipse, .cloud, .line, .arrow, .dblarrow, .callout, .distance, .calibrate].contains(live.tool) {
                    switch live.tool {
                    case .rect, .redact:
                        cg.stroke(overlayRect(pageRect, on: live.page))
                    case .crop:
                        // Dim what would be cut away; the kept area stays clear.
                        let keep = overlayRect(pageRect, on: live.page)
                        let whole = overlayRect(live.page.bounds(for: .cropBox), on: live.page)
                        cg.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
                        cg.addRect(whole); cg.addRect(keep); cg.fillPath(using: .evenOdd)
                        cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(1.5 * u); cg.setLineDash(phase: 0, lengths: [5 * u, 3 * u])
                        cg.stroke(keep)
                    case .link:
                        cg.setLineDash(phase: 0, lengths: [4 * u, 3 * u]); cg.setLineWidth(1.5 * u)
                        cg.setStrokeColor(accent.cgColor); cg.setFillColor(accent.withAlphaComponent(0.08).cgColor)
                        let r = overlayRect(pageRect, on: live.page)
                        cg.fill(r); cg.stroke(r)
                    case .ellipse:
                        cg.strokeEllipse(in: overlayRect(pageRect, on: live.page))
                    case .cloud:
                        // The cloud as it will be committed.
                        if pageRect.width > 2 && pageRect.height > 2 {
                            let straight = editor.style(for: .cloud).cloudStyle == "straight"
                            strokePolyline(cg, MarkupGeometry.cloudPoints(pageRect, straight: straight).map { overlayPoint($0, on: live.page) }, close: true)
                        }
                    case .line, .arrow, .dblarrow, .distance, .calibrate:
                        let a = overlayPoint(p0, on: live.page), b = overlayPoint(p1, on: live.page)
                        cg.move(to: a); cg.addLine(to: b); cg.strokePath()
                        if live.tool == .line || live.tool == .arrow || live.tool == .dblarrow {
                            let e = AnnotationFactory.endings(tool: live.tool, style: editor.style(for: live.tool))
                            cg.setFillColor(live.color.cgColor)
                            LineRenderer.ending(e.end.pdfStyle, at: b, from: a, width: live.width * z, in: cg)
                            LineRenderer.ending(e.start.pdfStyle, at: a, from: b, width: live.width * z, in: cg)
                        }
                        if live.tool == .distance || live.tool == .calibrate {
                            // end ticks + the live measurement
                            let ang = atan2(b.y - a.y, b.x - a.x), t = 6 * u
                            for e in [a, b] { cg.move(to: CGPoint(x: e.x - t * sin(ang), y: e.y + t * cos(ang))); cg.addLine(to: CGPoint(x: e.x + t * sin(ang), y: e.y - t * cos(ang))) }
                            cg.strokePath()
                            let len = hypot(p1.x - p0.x, p1.y - p0.y)
                            let text = live.tool == .calibrate ? "\(editor.mkMeasure.formatLength(points: Double(len))) · release to set" : editor.mkMeasure.formatLength(points: Double(len))
                            drawPill(cg, text, at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 16 * u), u: u)
                        }
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

        // Snap guides: alignment (dashed), touching (solid), equal spacing (brackets)
        if !mk.snapGuides.isEmpty, let page = mk.live?.page ?? mk.selected.first?.page ?? v.currentPage {
            cg.saveGState()
            let magenta = UIColor(red: 0.85, green: 0.2, blue: 0.6, alpha: 1)
            for g in mk.snapGuides {
                let a = overlayPoint(g.a, on: page), b = overlayPoint(g.b, on: page)
                switch g.kind {
                case .align:
                    cg.setStrokeColor(accent.cgColor); cg.setLineWidth(1 * u); cg.setLineDash(phase: 0, lengths: [4 * u, 3 * u])
                    cg.move(to: a); cg.addLine(to: b); cg.strokePath()
                case .touch:
                    cg.setStrokeColor(accent.cgColor); cg.setLineWidth(1.5 * u); cg.setLineDash(phase: 0, lengths: [])
                    cg.move(to: a); cg.addLine(to: b); cg.strokePath()
                case .gap:
                    // a bracket with end ticks and a centre "=" marker
                    cg.setStrokeColor(magenta.cgColor); cg.setLineWidth(1 * u); cg.setLineDash(phase: 0, lengths: [])
                    let horizontal = abs(b.y - a.y) < abs(b.x - a.x)
                    let t = 5 * u
                    cg.move(to: a); cg.addLine(to: b)
                    if horizontal {
                        cg.move(to: CGPoint(x: a.x, y: a.y - t)); cg.addLine(to: CGPoint(x: a.x, y: a.y + t))
                        cg.move(to: CGPoint(x: b.x, y: b.y - t)); cg.addLine(to: CGPoint(x: b.x, y: b.y + t))
                        let m = CGPoint(x: (a.x + b.x) / 2, y: a.y)
                        cg.move(to: CGPoint(x: m.x - 3 * u, y: m.y - 2 * u)); cg.addLine(to: CGPoint(x: m.x + 3 * u, y: m.y - 2 * u))
                        cg.move(to: CGPoint(x: m.x - 3 * u, y: m.y + 2 * u)); cg.addLine(to: CGPoint(x: m.x + 3 * u, y: m.y + 2 * u))
                    } else {
                        cg.move(to: CGPoint(x: a.x - t, y: a.y)); cg.addLine(to: CGPoint(x: a.x + t, y: a.y))
                        cg.move(to: CGPoint(x: b.x - t, y: b.y)); cg.addLine(to: CGPoint(x: b.x + t, y: b.y))
                        let m = CGPoint(x: a.x, y: (a.y + b.y) / 2)
                        cg.move(to: CGPoint(x: m.x - 2 * u, y: m.y - 3 * u)); cg.addLine(to: CGPoint(x: m.x - 2 * u, y: m.y + 3 * u))
                        cg.move(to: CGPoint(x: m.x + 2 * u, y: m.y - 3 * u)); cg.addLine(to: CGPoint(x: m.x + 2 * u, y: m.y + 3 * u))
                    }
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
            // running measurement for perimeter / area drafts
            if mk.polyTool == .perimeter, let l = pts.last {
                drawPill(cg, editor.mkMeasure.formatLength(points: Double(MarkupGeometry.pathLength(mk.polyPoints))), at: CGPoint(x: l.x, y: l.y - 18 * u), u: u)
            } else if mk.polyTool == .area, mk.polyPoints.count >= 3 {
                let c = overlayPoint(MarkupGeometry.centroid(mk.polyPoints), on: page)
                drawPill(cg, editor.mkMeasure.formatArea(points2: Double(MarkupGeometry.polygonArea(mk.polyPoints))), at: c, u: u)
            }
        }

        // Page-text selection (long press with no tool)
        if let sel = mk.textSel, let page = mk.textSelPage {
            cg.saveGState()
            cg.setFillColor(accent.withAlphaComponent(0.28).cgColor)
            for line in sel.selectionsByLine() { cg.fill(overlayRect(line.bounds(for: page), on: page).insetBy(dx: -1 * u, dy: -1 * u)) }
            cg.restoreGState()
        }

        // Search hits: the current one in accent, the rest in yellow
        if !mk.searchHits.isEmpty {
            cg.saveGState()
            for page in visiblePages(v) {
                for (i, sel) in mk.searchHits.enumerated() where sel.pages.contains(page) {
                    cg.setFillColor((i == mk.searchIndex ? accent.withAlphaComponent(0.4) : UIColor(red: 1, green: 0.85, blue: 0.1, alpha: 0.35)).cgColor)
                    for line in sel.selectionsByLine() { cg.fill(overlayRect(line.bounds(for: page), on: page).insetBy(dx: -1 * u, dy: -1 * u)) }
                }
            }
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

        // Links show while the Link tool is active (they are invisible otherwise, like in any reader).
        if editor.tool == .link {
            cg.saveGState()
            cg.setStrokeColor(accent.cgColor); cg.setLineWidth(1.5 * u); cg.setLineDash(phase: 0, lengths: [4 * u, 3 * u])
            cg.setFillColor(accent.withAlphaComponent(0.08).cgColor)
            for page in visiblePages(v) {
                for a in page.annotations where a.isLink {
                    let r = overlayRect(a.bounds, on: page)
                    cg.fill(r); cg.stroke(r)
                }
            }
            cg.restoreGState()
        }

        // (Comment badges are drawn on the annotation layer, beside their annotation.)

        // Selection
        if let first = mk.selected.first, let page = first.page {
            cg.saveGState()
            cg.setStrokeColor(accent.cgColor); cg.setLineWidth(2 * u)
            for a in mk.selected { cg.stroke(overlayRect(a.bounds, on: page).insetBy(dx: -3 * u, dy: -3 * u)) }
            if editor.mkSelectionLocked, let b = editor.mkSelectionBounds {
                let r = overlayRect(b, on: page)
                let s = 16 * u
                let box = CGRect(x: r.minX - 3 * u, y: r.minY - 3 * u - s - 2 * u, width: s + 6 * u, height: s + 2 * u)
                cg.setFillColor(accent.cgColor)
                cg.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height))
                if let glyph = UIImage(systemName: "lock.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    glyph.draw(in: CGRect(x: box.minX + 3 * u, y: box.minY + 1 * u, width: s, height: s))
                }
            }
            if let b = editor.mkSelectionBounds, !editor.mkMovableSelection.isEmpty {
                let r = overlayRect(b, on: page)
                drawHandle(cg, at: CGPoint(x: r.maxX + 8 * u, y: r.maxY + 8 * u), accent: accent, u: u)
                if editor.mkRotatable != nil {
                    let rp = rotateHandlePoint(r)
                    cg.setStrokeColor(accent.cgColor); cg.setLineWidth(1.5 * u)
                    cg.move(to: CGPoint(x: r.midX, y: r.minY - 3 * u)); cg.addLine(to: CGPoint(x: rp.x, y: rp.y + 11 * u)); cg.strokePath()
                    drawHandle(cg, at: rp, accent: accent, u: u)
                    if let glyph = UIImage(systemName: "arrow.clockwise")?.withTintColor(accent, renderingMode: .alwaysOriginal) {
                        glyph.draw(in: CGRect(x: rp.x - 6 * u, y: rp.y - 6 * u, width: 12 * u, height: 12 * u))
                    }
                }
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

    /// Small white pill with text, centred on `c` (screen-sized).
    private func drawPill(_ cg: CGContext, _ text: String, at c: CGPoint, u: CGFloat) {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        cg.saveGState()
        cg.translateBy(x: c.x, y: c.y); cg.scaleBy(x: u, y: u)
        let pill = CGRect(x: -size.width / 2 - 8, y: -11, width: size.width + 16, height: 22)
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.2).cgColor)
        cg.setFillColor(UIColor.white.cgColor)
        cg.addPath(UIBezierPath(roundedRect: pill, cornerRadius: 11).cgPath); cg.fillPath()
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        UIGraphicsPushContext(cg)
        (text as NSString).draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 4), withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.15, alpha: 1)])
        UIGraphicsPopContext()
        cg.restoreGState()
    }

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


/// Insert image: a photo from the library or an image file from Files; then tap the page to place it.
struct ImagePickSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    @State private var item: PhotosPickerItem? = nil
    @State private var filesOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert image").font(titleFnt(20)).foregroundStyle(theme.ink1)
            Text("Pick an image, then tap the page where it should go. Drag the corner to resize it afterwards.").font(fnt(14)).foregroundStyle(theme.ink3)
            HStack(spacing: 10) {
                PhotosPicker(selection: $item, matching: .images) {
                    HStack(spacing: 7) { Image(systemName: "photo.on.rectangle").font(fnt(14, .semibold)); Text("Photo Library").font(fnt(14, .semibold)) }
                        .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.accent))
                }
                SecondaryButton(label: "Files…", symbol: "folder") { filesOn = true }
                Spacer()
                SecondaryButton(label: "Cancel") { editor.mk.imagePickerOn = false; if editor.tool == .image { editor.tool = .none } }
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .background(theme.bg2)
        .presentationDetents([.height(200)])
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task { @MainActor in
                if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) { took(img) }
                else { app.flash("Couldn't load that image") }
            }
        }
        .fileImporter(isPresented: $filesOn, allowedContentTypes: [UTType.image]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { took(img) } else { app.flash("Couldn't load that image") }
            }
        }
    }

    private func took(_ img: UIImage) {
        // Keep memory sane: cap the longer side at 2000 px.
        let maxSide: CGFloat = 2000
        var image = img
        if max(img.size.width, img.size.height) * img.scale > maxSide {
            let k = maxSide / (max(img.size.width, img.size.height) * img.scale)
            let size = CGSize(width: img.size.width * img.scale * k, height: img.size.height * img.scale * k)
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            image = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        }
        editor.mk.pendingImage = image
        editor.mk.imagePickerOn = false
        app.flash("Tap the page to place the image")
    }
}

/// Draw a signature once; it is saved and placed by the Signature tool.
struct SignatureSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    @State private var paths: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var name = "Signature"
    @State private var padWidthOnScreen: CGFloat = 520
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var fileOn = false
    private let padSize = CGSize(width: 520, height: 200)

    /// A picture of a signature: trimmed to the ink, white paper made transparent, saved as an image signature.
    private func importSignature(_ raw: UIImage) {
        guard let png = SignatureImage.prepare(raw) else { app.flash("Couldn't read that image"); return }
        let sig = SavedSignature(name: name.isEmpty ? "Signature" : name, paths: [], width: Double(png.size.width), height: Double(png.size.height),
                                 image: png.data)
        var s = app.settings; s.signatures = [sig] + (s.signatures ?? []); app.settings = s
        editor.mk.signaturePadOn = false
        app.flash("Saved. Tap the page to place it.")
    }

    var body: some View {
        let saved = app.settings.signatures ?? []
        VStack(alignment: .leading, spacing: 14) {
            Text("Signatures").font(titleFnt(20)).foregroundStyle(theme.ink1)
            if !saved.isEmpty {
                SectionLabel(text: "Saved · first is the default")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(saved) { sig in
                            VStack(spacing: 4) {
                                SignaturePreview(sig: sig, color: theme.ink1).frame(width: 150, height: 60)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.card))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                                Text(sig.name).font(fnt(11.5, .medium)).foregroundStyle(theme.ink3).lineLimit(1)
                            }
                            .contextMenu {
                                Button("Make default", systemImage: "star") { var s = app.settings; var list = s.signatures ?? []; list.removeAll { $0.id == sig.id }; list.insert(sig, at: 0); s.signatures = list; app.settings = s }
                                Button("Delete", systemImage: "trash", role: .destructive) { var s = app.settings; s.signatures?.removeAll { $0.id == sig.id }; app.settings = s }
                            }
                            .onTapGesture { var s = app.settings; var list = s.signatures ?? []; list.removeAll { $0.id == sig.id }; list.insert(sig, at: 0); s.signatures = list; app.settings = s; editor.mk.signaturePadOn = false; app.flash("Tap the page to place it") }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                SectionLabel(text: "Draw a new one")
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 5) { Image(systemName: "photo").font(fnt(12, .semibold)); Text("From photo").font(fnt(12, .semibold)) }
                        .foregroundStyle(theme.ink2).padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.hov))
                }
                SecondaryButton(label: "From file…", symbol: "folder", height: 28) { fileOn = true }
            }
            .onChange(of: photoItem) { _, it in
                guard let it else { return }
                Task { @MainActor in
                    if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) { importSignature(img) }
                    else { app.flash("Couldn't load that image") }
                    photoItem = nil
                }
            }
            .fileImporter(isPresented: $fileOn, allowedContentTypes: [UTType.image]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { importSignature(img) } else { app.flash("Couldn't load that image") }
                }
            }
            Canvas { ctx, size in
                let k = size.width / padSize.width
                for path in paths + [current] where path.count > 1 {
                    var p = Path(); p.move(to: CGPoint(x: path[0].x * k, y: path[0].y * k))
                    for q in path.dropFirst() { p.addLine(to: CGPoint(x: q.x * k, y: q.y * k)) }
                    ctx.stroke(p, with: .color(theme.ink1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                var base = Path(); base.move(to: CGPoint(x: 20, y: size.height * 0.75)); base.addLine(to: CGPoint(x: size.width - 20, y: size.height * 0.75))
                ctx.stroke(base, with: .color(theme.line2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: padSize.height * padWidthOnScreen / padSize.width)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    // The pad is drawn scaled to its width; store points in pad space.
                    let k = padSize.width / max(1, padWidthOnScreen)
                    current.append(CGPoint(x: v.location.x * k, y: v.location.y * k))
                }
                .onEnded { _ in if current.count > 1 { paths.append(current) }; current = [] })
            .background(GeometryReader { g in Color.clear.onAppear { padWidthOnScreen = g.size.width }.onChange(of: g.size.width) { _, w in padWidthOnScreen = w } })
            HStack(spacing: 10) {
                FieldText(placeholder: "Name", text: $name, height: 36, font: fnt(14)).frame(width: 200)
                SecondaryButton(label: "Clear") { paths = []; current = [] }
                Spacer()
                SecondaryButton(label: "Close") { editor.mk.signaturePadOn = false }
                PrimaryButton(label: "Save signature") {
                    let all = paths.flatMap { $0 }
                    guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max(), maxX > minX else { return }
                    let sig = SavedSignature(name: name.isEmpty ? "Signature" : name,
                                             paths: paths.map { $0.map { Point(Double($0.x - minX), Double($0.y - minY)) } },
                                             width: Double(maxX - minX), height: Double(max(1, maxY - minY)))
                    var s = app.settings; s.signatures = [sig] + (s.signatures ?? []); app.settings = s
                    paths = []; current = []
                    editor.mk.signaturePadOn = false
                    app.flash("Saved. Tap the page to place it.")
                }.disabled(paths.isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: 620)
        .background(theme.bg2)
        .presentationDetents([.large])
    }
}

struct SignaturePreview: View {
    var sig: SavedSignature
    var color: Color
    var body: some View {
        if let data = sig.image, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFit().padding(6)
        } else {
            strokes
        }
    }
    private var strokes: some View {
        Canvas { ctx, size in
            let k = min((size.width - 12) / CGFloat(max(1, sig.width)), (size.height - 12) / CGFloat(max(1, sig.height)))
            let ox = (size.width - CGFloat(sig.width) * k) / 2, oy = (size.height - CGFloat(sig.height) * k) / 2
            for path in sig.paths where path.count > 1 {
                var p = Path(); p.move(to: CGPoint(x: ox + CGFloat(path[0].x) * k, y: oy + CGFloat(path[0].y) * k))
                for q in path.dropFirst() { p.addLine(to: CGPoint(x: ox + CGFloat(q.x) * k, y: oy + CGFloat(q.y) * k)) }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}


/// Link tool: where the drawn box should go.
struct LinkSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    @State private var mode = "web"
    @State private var address = ""
    @State private var pageText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add link").font(titleFnt(20)).foregroundStyle(theme.ink1)
            SegmentControl(options: [SegmentOption(value: "web", label: "Web address"), SegmentOption(value: "page", label: "Page in this document")],
                           selection: $mode, fontSize: 12.5, vPad: 5, radius: 8, fill: true)
            if mode == "web" {
                FieldText(placeholder: "https://…", text: $address, height: 38, font: fnt(14))
                    .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
            } else {
                HStack(spacing: 8) {
                    FieldText(placeholder: "Page number", text: $pageText, height: 38, font: fnt(14)).keyboardType(.numberPad).frame(width: 140)
                    Text("of \(editor.pageCount)").font(fnt(13)).foregroundStyle(theme.ink3)
                }
            }
            HStack {
                Spacer()
                SecondaryButton(label: "Cancel") { editor.mk.linkPending = nil }
                PrimaryButton(label: "Add link") {
                    if mode == "web" {
                        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.contains("://") { s = "https://" + s }
                        guard let u = URL(string: s), u.host != nil else { app.flash("That doesn't look like a web address"); return }
                        editor.mkAddLink(url: u, pageIndex: nil)
                    } else {
                        guard let n = Int(pageText.trimmingCharacters(in: .whitespaces)), n >= 1, n <= editor.pageCount else { app.flash("Enter a page between 1 and \(editor.pageCount)"); return }
                        editor.mkAddLink(url: nil, pageIndex: n - 1)
                    }
                }.disabled(mode == "web" ? address.trimmingCharacters(in: .whitespaces).isEmpty : pageText.isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(theme.bg2)
        .presentationDetents([.height(240)])
    }
}

/// Flatten: what gets burned into the pages. Everything else stays an editable annotation.
struct FlattenSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    @State private var mode = "all"
    @State private var authors: Set<String> = []

    var body: some View {
        let all = editor.mkAuthors()
        let selectedCount = editor.mk.selected.filter(\.isPrimary).count
        VStack(alignment: .leading, spacing: 12) {
            Text("Flatten").font(titleFnt(20)).foregroundStyle(theme.ink1)
            Text("Burned-in annotations become part of the page and can't be edited again.").font(fnt(13)).foregroundStyle(theme.ink3)
            choice("all", "Everything", "All annotations on every page")
            if selectedCount > 0 { choice("selected", "Only the selection", Formatting.plural(selectedCount, "annotation")) }
            choice("authors", "By author", all.isEmpty ? "No authors found" : "Pick whose annotations to burn in")
            if mode == "authors" {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(all, id: \.self) { name in
                        Toggle(isOn: Binding(get: { authors.contains(name) }, set: { on in if on { authors.insert(name) } else { authors.remove(name) } })) {
                            Text(name).font(fnt(13.5, .medium)).foregroundStyle(theme.ink1)
                        }
                        .tint(theme.accent)
                    }
                }
                .padding(.leading, 28)
            }
            HStack(spacing: 10) {
                Spacer()
                SecondaryButton(label: "Cancel") { editor.mk.flattenSheet = false }
                SecondaryButton(label: "Save to Files", symbol: "folder") { run(share: false) }
                PrimaryButton(label: "Share", symbol: "square.and.arrow.up") { run(share: true) }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .background(theme.bg2)
        .presentationDetents([.medium, .large])
    }

    private func choice(_ id: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode == id ? "largecircle.fill.circle" : "circle").font(fnt(18)).foregroundStyle(mode == id ? theme.accent : theme.ink4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(fnt(14, .semibold)).foregroundStyle(theme.ink1)
                Text(sub).font(fnt(12)).foregroundStyle(theme.ink4)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { mode = id }
    }

    private func run(share: Bool) {
        let scope: FlattenScope
        switch mode {
        case "selected": scope = .selected
        case "authors":
            guard !authors.isEmpty else { app.flash("Pick at least one author"); return }
            scope = .authors(authors)
        default: scope = .all
        }
        guard let data = editor.mkFlattenedData(scope: scope) else { app.flash("Export failed"); return }
        let name = editor.doc.name.replacingOccurrences(of: ".pdf", with: "") + " — flattened.pdf"
        editor.mk.flattenSheet = false
        if share {
            if let url = PDFExport.write(data, name: name) { editor.shareURL = url } else { app.flash("Export failed") }
        } else {
            app.flash(PDFExport.write(data, name: name, directory: AppModel.exportsDirectory) != nil ? "Saved to Files › Redline › Exports" : "Export failed")
        }
    }
}


/// Crop tool: confirm the area to keep.
struct CropSheet: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let pending = editor.mk.cropPending
        let index = pending.flatMap { editor.mk.pdf?.index(for: $0.page) } ?? editor.pageIndex
        VStack(alignment: .leading, spacing: 12) {
            Text("Crop page \(index + 1)").font(titleFnt(20)).foregroundStyle(theme.ink1)
            Text("Every reader shows only the area you dragged. Nothing is removed from the file; Organize Pages can reset the crop later.")
                .font(fnt(13)).foregroundStyle(theme.ink3)
            HStack {
                Spacer()
                SecondaryButton(label: "Cancel") { editor.mk.cropPending = nil }
                PrimaryButton(label: "Crop", symbol: "crop") {
                    if let p = pending { editor.mkCropPage(p.page, to: p.rect) }
                    editor.mk.cropPending = nil
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(theme.bg2)
        .presentationDetents([.height(200)])
    }
}


/// Turns a photo or scan of a signature into a transparent PNG: near-white paper becomes clear, the ink is kept
/// and the result is trimmed to the ink.
enum SignatureImage {
    static func prepare(_ raw: UIImage) -> (data: Data, size: CGSize)? {
        let maxSide: CGFloat = 1200
        let pixelW = raw.size.width * raw.scale, pixelH = raw.size.height * raw.scale
        let k = min(1, maxSide / max(pixelW, pixelH))
        let w = Int(pixelW * k), h = Int(pixelH * k)
        guard w > 2, h > 2 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let cg = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let img = raw.cgImage else { return nil }
        cg.setFillColor(UIColor.white.cgColor); cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        cg.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
                let light = min(r, g, b)
                if light > 225 {
                    buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0   // paper → transparent
                } else {
                    // ink: darken a little and fade the edge pixels so the stroke looks smooth
                    let a = min(255, (240 - light) * 2)
                    buf[i] = UInt8(r * a / 255); buf[i + 1] = UInt8(g * a / 255); buf[i + 2] = UInt8(b * a / 255); buf[i + 3] = UInt8(a)
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY, let full = cg.makeImage() else { return nil }
        let pad = 6
        let crop = CGRect(x: max(0, minX - pad), y: max(0, minY - pad), width: min(w, maxX + pad) - max(0, minX - pad), height: min(h, maxY + pad) - max(0, minY - pad))
        guard let cut = full.cropping(to: crop) else { return nil }
        let out = UIImage(cgImage: cut)
        guard let data = out.pngData() else { return nil }
        return (data, CGSize(width: crop.width, height: crop.height))
    }
}


/// Editing a line of the page's own text in place: a field over the line, same size; Return or a tap outside
/// writes the change into the page content.
struct PageTextEditBox: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel
    var edit: PageTextEdit
    @FocusState private var focused: Bool

    var body: some View {
        let mk = editor.mk
        let _ = mk.viewportTick
        if let v = mk.pdfView {
            let r = v.convert(edit.rect, from: edit.page)
            let fontSize = max(9, r.height * 0.74)
            TextField("", text: Binding(get: { mk.pageTextDraft }, set: { mk.pageTextDraft = $0 }))
                .font(.system(size: fontSize))
                .foregroundStyle(Color.black)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit { editor.mkCommitPageTextEdit() }
                .padding(.horizontal, 3)
                .frame(width: max(r.width + 40, 80), height: max(r.height + 6, 22))
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.accent, lineWidth: 1.5))
                .position(x: r.minX - 3 + max(r.width + 40, 80) / 2, y: r.midY)
                .onAppear { focused = true }
        }
    }
}
