import SwiftUI
import UIKit
import RedlineCore

/// Native vertical scroll of every page (Markup / Drawing): rubber-band bounce back to the margin on all
/// four sides, direction-locked finger scrolling, finger pinch-zoom (re-rendered sharp when the pinch ends).
/// Only direct (finger) touches scroll or zoom; the Apple Pencil goes straight to the pages.
struct PagesScrollView: UIViewRepresentable {
    var editor: WorkspaceModel
    var app: AppModel
    var theme: Theme

    static let margin: CGFloat = 24
    static let spacing: CGFloat = 24

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.delegate = context.coordinator
        sv.bounces = true
        sv.alwaysBounceVertical = true
        sv.alwaysBounceHorizontal = true
        sv.isDirectionalLockEnabled = true
        sv.delaysContentTouches = false
        sv.canCancelContentTouches = true
        sv.minimumZoomScale = 0.5
        sv.maximumZoomScale = 3
        sv.bouncesZoom = true
        sv.showsHorizontalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.backgroundColor = .clear
        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        sv.panGestureRecognizer.allowedTouchTypes = direct
        sv.pinchGestureRecognizer?.allowedTouchTypes = direct

        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        host.view.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor)
        ])
        context.coordinator.host = host
        context.coordinator.scrollView = sv
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        context.coordinator.editor = editor
        context.coordinator.host?.rootView = AnyView(content)
        context.coordinator.scheduleLayout()
        if let req = editor.scrollRequest { context.coordinator.scroll(to: req) }
    }

    private var content: some View {
        VStack(spacing: PagesScrollView.spacing) {
            ForEach(0..<editor.pageCount, id: \.self) { i in
                PageView(editor: editor, pageIndex: i, ownGestures: false)
            }
        }
        .environment(app)
        .environment(\.theme, theme)
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var editor: WorkspaceModel
        var host: UIHostingController<AnyView>?
        weak var scrollView: UIScrollView?
        private var lastFitWidth: CGFloat = 0
        private var pendingScroll: Int? = nil

        init(editor: WorkspaceModel) { self.editor = editor }

        // MARK: layout

        func scheduleLayout() {
            Task { @MainActor [weak self] in
                guard let self, let sv = self.scrollView else { return }
                self.fitIfNeeded(sv)
                self.centerContent(sv)
            }
        }

        /// First layout: fit to width. Later width changes (sidebar opening, rotation, Split View) rescale the
        /// pages so they keep filling the same share of the view, and keep the same content in view.
        private func fitIfNeeded(_ sv: UIScrollView) {
            let w = sv.bounds.width
            guard w > 0, w != lastFitWidth else { return }
            let previous = lastFitWidth
            lastFitWidth = w
            if previous <= 0 {
                let z = Double(w - 2 * PagesScrollView.margin) / editor.canvas.w
                editor.zoom = max(Metrics.minZoom, min(Metrics.maxZoom, (z * 100).rounded(.down) / 100))
                return
            }
            let factor = Double(w) / Double(previous)
            let old = editor.zoom
            editor.zoom = max(Metrics.minZoom, min(Metrics.maxZoom, old * factor))
            let applied = editor.zoom / old
            let offset = CGPoint(x: (sv.contentOffset.x + sv.contentInset.left) * applied - sv.contentInset.left,
                                 y: (sv.contentOffset.y + sv.contentInset.top) * applied - sv.contentInset.top)
            Task { @MainActor [weak self] in
                guard let self, let sv = self.scrollView else { return }
                self.centerContent(sv)
                sv.setContentOffset(offset, animated: false)
            }
        }

        /// Margin on every side; centres the pages when they are narrower / shorter than the viewport.
        func centerContent(_ sv: UIScrollView) {
            let m = PagesScrollView.margin
            let cw = sv.contentSize.width, ch = sv.contentSize.height
            let fw = sv.bounds.width, fh = sv.bounds.height
            let side = max(m, (fw - cw) / 2)
            let top = max(m, (fh - ch) / 2)
            let inset = UIEdgeInsets(top: top, left: side, bottom: max(m, top), right: side)
            if sv.contentInset != inset { sv.contentInset = inset }
        }

        private func pageHeight(_ i: Int) -> CGFloat { editor.frameSize(page: i).height * editor.zoom }

        private func pageOriginY(_ i: Int) -> CGFloat {
            var y: CGFloat = 0
            for j in 0..<i { y += pageHeight(j) + PagesScrollView.spacing }
            return y
        }

        // MARK: programmatic scrolling

        func scroll(to i: Int) {
            guard pendingScroll != i else { return }
            pendingScroll = i
            Task { @MainActor [weak self] in
                guard let self, let sv = self.scrollView else { return }
                let y = self.pageOriginY(i) * sv.zoomScale - sv.contentInset.top
                let maxY = max(-sv.contentInset.top, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: min(max(-sv.contentInset.top, y), maxY)), animated: true)
                self.editor.scrollRequest = nil
                self.pendingScroll = nil
            }
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent(scrollView) }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Bake the pinch into the render zoom, then reset the transform keeping the same content position.
            let offset = scrollView.contentOffset
            editor.zoom = max(Metrics.minZoom, min(Metrics.maxZoom, editor.zoom * Double(scale)))
            scrollView.zoomScale = 1
            Task { @MainActor [weak self] in
                guard let self, let sv = self.scrollView else { return }
                self.centerContent(sv)
                sv.setContentOffset(offset, animated: false)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard editor.pageCount > 0 else { return }
            // The current page is the one under the upper part of the viewport.
            let probe = (scrollView.contentOffset.y + scrollView.bounds.height * 0.4) / max(0.01, scrollView.zoomScale)
            var index = 0
            var y: CGFloat = 0
            for i in 0..<editor.pageCount {
                let h = pageHeight(i)
                if probe < y + h + PagesScrollView.spacing / 2 { index = i; break }
                y += h + PagesScrollView.spacing
                index = i
            }
            if index != editor.pageIndex && pendingScroll == nil { editor.pageIndex = index }
        }
    }
}
