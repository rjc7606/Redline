import UIKit
import PDFKit
import RedlineCore

// Redline's own PDF viewer. PDFKit still parses the file, renders page content and owns the annotation model;
// this replaces only PDFView: a UIScrollView stacking the pages vertically, with page content rendered into
// static tiles (background threads) and annotations drawn per page on the main thread so edits show instantly.
// Scrolling, zooming, bounce, fit-width, page tracking and coordinate conversion are all ours.

/// Vertical page stack with the slice of PDFView's API the markup code uses (same member names).
@MainActor
final class PDFStackView: UIScrollView, UIScrollViewDelegate {
    static let gap: CGFloat = 24
    static let margin: CGFloat = 16

    var document: PDFDocument? { didSet { if document !== oldValue { rebuild() } } }
    /// Everything scrolls and zooms inside this view; the touch overlay is added to it by the coordinator.
    let documentView = UIView()

    private var tiles: [PDFPageTileView] = []
    private var annotationViews: [PDFAnnotationsView] = []
    private var frames: [CGRect] = []        // page frames in documentView coords at the base scale
    private var signature: [String] = []     // page identity + rotation, to notice structural edits
    private var lastWidth: CGFloat = 0
    private var currentIndex = -1

    /// Points per PDF unit before any pinch in progress; `scaleFactor` is the effective scale.
    private(set) var baseScale: CGFloat = 1
    var minScaleFactor: CGFloat = 0.25
    var maxScaleFactor: CGFloat = 6
    var scaleFactor: CGFloat {
        get { baseScale * zoomScale }
        set { setScale(newValue) }
    }

    var onViewportChange: (() -> Void)?
    /// Per page: which annotations carry a comment badge (drawn on the annotation layer, right after the annotation,
    /// so anything moved over it covers the badge too).
    var badgeProvider: ((PDFPage) -> (PDFAnnotation) -> Bool)? { didSet { for v in annotationViews { v.badges = badgeProvider } } }
    var onPageChange: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        bounces = true
        bouncesZoom = true
        isDirectionalLockEnabled = false
        delaysContentTouches = false
        canCancelContentTouches = true
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 0.5
        maximumZoomScale = 4
        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        panGestureRecognizer.allowedTouchTypes = direct      // the Pencil never scrolls
        pinchGestureRecognizer?.allowedTouchTypes = direct
        addSubview(documentView)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Pages

    private func pageSignature() -> [String] {
        guard let doc = document else { return [] }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0) }.map { "\(ObjectIdentifier($0).hashValue):\($0.rotation):\($0.bounds(for: .cropBox))" }
    }

    /// Rebuilds the tiles if pages were added, removed, reordered or rotated.
    func syncPages() { if pageSignature() != signature { rebuild() } }

    private func rebuild() {
        tiles.forEach { $0.removeFromSuperview() }
        annotationViews.forEach { $0.removeFromSuperview() }
        tiles = []; annotationViews = []; frames = []
        signature = pageSignature()
        guard let doc = document else { contentSize = .zero; return }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let tile = PDFPageTileView(page: page)
            let ann = PDFAnnotationsView(page: page)
            ann.badges = badgeProvider
            documentView.insertSubview(tile, at: 0)
            documentView.insertSubview(ann, aboveSubview: tile)
            tiles.append(tile); annotationViews.append(ann)
        }
        // keep the overlay (added by the coordinator) on top
        for sub in documentView.subviews where !(sub is PDFPageTileView) && !(sub is PDFAnnotationsView) { documentView.bringSubviewToFront(sub) }
        layoutPages()   // keeps the current scale (rotate / insert / delete); the first layout fits the width
    }

    private func layoutPages() {
        guard let doc = document, doc.pageCount > 0 else { contentSize = .zero; return }
        let sizes = (0..<doc.pageCount).map { doc.page(at: $0).map(PDFService.displaySize) ?? CGSize(width: 612, height: 792) }
        let maxW = sizes.map(\.width).max() ?? 612
        let m = PDFStackView.margin
        var y = m
        frames = []
        // Frames change synchronously and without implicit animation, so a tile never shows at its old size.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, s) in sizes.enumerated() {
            let w = s.width * baseScale, h = s.height * baseScale
            let f = CGRect(x: m + (maxW * baseScale - w) / 2, y: y, width: w, height: h)
            frames.append(f)
            if tiles.indices.contains(i) { tiles[i].frame = f; tiles[i].scale = baseScale; annotationViews[i].frame = f; annotationViews[i].scale = baseScale }
            y += h + PDFStackView.gap
        }
        CATransaction.commit()
        let size = CGSize(width: maxW * baseScale + 2 * m, height: y - PDFStackView.gap + m)
        documentView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        for sub in documentView.subviews where !(sub is PDFPageTileView) && !(sub is PDFAnnotationsView) { sub.frame = documentView.bounds }
        updateInsets()
        onViewportChange?()
    }

    /// Centres content smaller than the view and bounces only along an axis where the content is larger.
    private func updateInsets() {
        let w = contentSize.width * zoomScale, h = contentSize.height * zoomScale
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - h) / 2), left: max(0, (bounds.width - w) / 2),
                                    bottom: max(0, (bounds.height - h) / 2), right: max(0, (bounds.width - w) / 2))
        alwaysBounceVertical = h > bounds.height + 0.5
        alwaysBounceHorizontal = w > bounds.width + 0.5
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 50, document != nil else { return }
        if lastWidth == 0 { lastWidth = w; fitWidth() }
        else if abs(w - lastWidth) > 0.5 { let r = w / lastWidth; lastWidth = w; setScale(baseScale * r) }   // same fill after a resize
        else { updateInsets() }
    }

    /// Fits the widest page to the view's width.
    func fitWidth() {
        guard let doc = document, doc.pageCount > 0, bounds.width > 50 else { return }
        let maxW = (0..<doc.pageCount).compactMap { doc.page(at: $0) }.map { PDFService.displaySize($0).width }.max() ?? 612
        baseScale = max(minScaleFactor, min(maxScaleFactor, (bounds.width - 2 * PDFStackView.margin) / max(1, maxW)))
        layoutPages()
        setContentOffset(CGPoint(x: -contentInset.left, y: -contentInset.top), animated: false)
    }

    /// Changes the base scale around the view's centre.
    func setScale(_ newScale: CGFloat) {
        let s = max(minScaleFactor, min(maxScaleFactor, newScale))
        guard abs(s - baseScale) > 0.0001 else { return }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let doc = documentView.convert(centre, from: self)
        let ratio = s / baseScale
        baseScale = s
        if zoomScale != 1 { zoomScale = 1 }
        layoutPages()
        tiles.forEach { $0.refresh() }
        setContentOffset(clamped(CGPoint(x: doc.x * ratio - bounds.width / 2, y: doc.y * ratio - bounds.height / 2)), animated: false)
        notifyPage()
    }

    private func clamped(_ o: CGPoint) -> CGPoint {
        let maxX = max(-contentInset.left, contentSize.width * zoomScale - bounds.width + contentInset.right)
        let maxY = max(-contentInset.top, contentSize.height * zoomScale - bounds.height + contentInset.bottom)
        return CGPoint(x: min(max(-contentInset.left, o.x), maxX), y: min(max(-contentInset.top, o.y), maxY))
    }

    /// Redraws the annotation layer of the visible pages (cheap; called when annotations change).
    func refreshAnnotations() {
        for (i, v) in annotationViews.enumerated() where frames.indices.contains(i) && isVisible(frames[i]) { v.setNeedsDisplay() }
    }

    private func isVisible(_ f: CGRect) -> Bool {
        let vis = documentView.convert(bounds, from: self)
        return f.insetBy(dx: -40, dy: -40).intersects(vis)
    }

    // MARK: - PDFView-shaped API

    var currentPage: PDFPage? { currentIndex >= 0 ? document?.page(at: currentIndex) : document?.page(at: 0) }

    var visiblePages: [PDFPage] {
        guard let doc = document else { return [] }
        return frames.indices.filter { isVisible(frames[$0]) }.compactMap { doc.page(at: $0) }
    }

    func index(of page: PDFPage) -> Int? {
        guard let doc = document else { return nil }
        let i = doc.index(for: page)
        return i >= 0 && i < frames.count ? i : nil
    }

    // A scroll view's own coordinate space scrolls with the content (bounds.origin == contentOffset). The page
    // conversions below use *visible* coordinates instead — (0,0) at the top-left of what's on screen — which is
    // what PDFView's did and what the SwiftUI overlays (popup, inline editor, selection bar) position with.
    func visible(fromBounds p: CGPoint) -> CGPoint { CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY) }
    func boundsPoint(fromVisible p: CGPoint) -> CGPoint { CGPoint(x: p.x + bounds.minX, y: p.y + bounds.minY) }

    /// Page under a point in visible coordinates (nearest page when between pages).
    func page(for point: CGPoint, nearest: Bool) -> PDFPage? {
        guard let doc = document, !frames.isEmpty else { return nil }
        let d = documentView.convert(boundsPoint(fromVisible: point), from: self)
        if let i = frames.firstIndex(where: { $0.contains(d) }) { return doc.page(at: i) }
        guard nearest else { return nil }
        var best = 0, dist = CGFloat.infinity
        for (i, f) in frames.enumerated() {
            let dy = d.y < f.minY ? f.minY - d.y : (d.y > f.maxY ? d.y - f.maxY : 0)
            let dx = d.x < f.minX ? f.minX - d.x : (d.x > f.maxX ? d.x - f.maxX : 0)
            let dd = hypot(dx, dy)
            if dd < dist { dist = dd; best = i }
        }
        return doc.page(at: best)
    }

    /// Page space (PDF user space, y up) → visible coordinates.
    func convert(_ p: CGPoint, from page: PDFPage) -> CGPoint {
        guard let i = index(of: page) else { return .zero }
        let d = p.applying(PDFService.pageToDisplay(page))
        return visible(fromBounds: convert(CGPoint(x: frames[i].minX + d.x * baseScale, y: frames[i].minY + d.y * baseScale), from: documentView))
    }

    /// Visible coordinates → page space.
    func convert(_ p: CGPoint, to page: PDFPage) -> CGPoint {
        guard let i = index(of: page) else { return p }
        let dv = documentView.convert(boundsPoint(fromVisible: p), from: self)
        let d = CGPoint(x: (dv.x - frames[i].minX) / baseScale, y: (dv.y - frames[i].minY) / baseScale)
        return d.applying(PDFService.pageToDisplay(page).inverted())
    }

    func convert(_ r: CGRect, from page: PDFPage) -> CGRect { bounding([r.origin, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].map { convert($0, from: page) }) }
    func convert(_ r: CGRect, to page: PDFPage) -> CGRect { bounding([r.origin, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].map { convert($0, to: page) }) }

    private func bounding(_ pts: [CGPoint]) -> CGRect {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    /// Scrolls so the page's top sits just below the top edge.
    func go(to page: PDFPage) {
        guard let i = index(of: page) else { return }
        let y = frames[i].minY * zoomScale - PDFStackView.margin
        setContentOffset(clamped(CGPoint(x: contentOffset.x, y: y)), animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { documentView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        notifyPage()
        onViewportChange?()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateInsets()
        onViewportChange?()
    }

    /// Bake the pinch into the base scale so the tiles re-render sharp and the overlay draws at 1:1.
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        setScale(baseScale * scale)
    }

    private func notifyPage() {
        guard !frames.isEmpty else { return }
        let c = documentView.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
        var best = 0, dist = CGFloat.infinity
        for (i, f) in frames.enumerated() {
            let d = c.y < f.minY ? f.minY - c.y : (c.y > f.maxY ? c.y - f.maxY : 0)
            if d < dist { dist = d; best = i }
        }
        if best != currentIndex { currentIndex = best; onPageChange?(best) }
    }
}

// MARK: - Page content tiles (background rendering, page content only)

/// Draws page content into a tiled layer. The drawing object is deliberately not main-actor bound: CATiledLayer
/// renders on background threads, and PDFKit page drawing is safe there as long as nothing else draws the page.
final class PDFPageTileView: UIView {
    let page: PDFPage
    var scale: CGFloat = 1 { didSet { if scale != oldValue { refresh() } } }
    private let tiled = NoFadeTiledLayer()
    private let drawer: PDFPageTileDrawer

    /// The tiled sublayer follows the frame immediately (not on the next layout pass), with no animation.
    override var frame: CGRect {
        didSet {
            guard frame.size != oldValue.size else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            tiled.frame = bounds
            CATransaction.commit()
        }
    }

    init(page: PDFPage) {
        self.page = page
        self.drawer = PDFPageTileDrawer(page: page)
        super.init(frame: .zero)
        backgroundColor = .white
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        tiled.delegate = drawer
        tiled.levelsOfDetail = 4
        tiled.levelsOfDetailBias = 3
        tiled.contentsScale = UIScreen.main.scale
        tiled.tileSize = CGSize(width: 512 * UIScreen.main.scale, height: 512 * UIScreen.main.scale)
        layer.addSublayer(tiled)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if tiled.frame != bounds {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            tiled.frame = bounds
            CATransaction.commit()
        }
        drawer.scale = scale
    }

    func refresh() {
        drawer.scale = scale
        tiled.setNeedsDisplay()
    }
}

/// CATiledLayer fades new tiles in; that read as a flash after every zoom.
final class NoFadeTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }
}

final class PDFPageTileDrawer: NSObject, CALayerDelegate, @unchecked Sendable {
    let page: PDFPage
    nonisolated(unsafe) var scale: CGFloat = 1
    init(page: PDFPage) { self.page = page }

    nonisolated func draw(_ layer: CALayer, in ctx: CGContext) {
        let b = layer.bounds
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(b)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: b.height)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.interpolationQuality = .high
        PDFDraw.content(of: page, in: ctx)   // content only; PDFAnnotationsView draws the annotations
        ctx.restoreGState()
    }
}

// MARK: - Annotation layer (main thread, instant)

/// Draws every annotation of one page: PDFKit draws foreign ones from their appearance streams, Redline's own
/// subclasses draw themselves. Invalidated whenever annotations change; only visible pages redraw.
final class PDFAnnotationsView: UIView {
    let page: PDFPage
    var scale: CGFloat = 1 { didSet { if scale != oldValue { setNeedsDisplay() } } }

    init(page: PDFPage) {
        self.page = page
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    var badges: ((PDFPage) -> (PDFAnnotation) -> Bool)? = nil

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        cg.translateBy(x: 0, y: bounds.height)
        cg.scaleBy(x: scale, y: -scale)
        let unit = 1 / max(0.01, scale)
        if let has = badges?(page) {
            PDFDraw.annotations(of: page, in: cg, after: { a, cg in
                if has(a) { BadgeDrawer.draw(cg, at: BadgeDrawer.center(for: a, unit: unit), color: a.color, unit: unit, yUp: true) }
            })
        } else {
            PDFDraw.annotations(of: page, in: cg)
        }
        cg.restoreGState()
    }
}
