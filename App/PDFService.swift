import UIKit
import PDFKit
import RedlineCore

/// Wraps a PDFPage so it can cross into the render actor (PDFKit pages are safe to draw off the main thread one at a time).
struct RenderablePage: @unchecked Sendable {
    let page: PDFPage
}

/// Drawing helpers shared by the viewer, thumbnails and exports (not main-actor bound: tiles and the render
/// queue draw on background threads).
enum PDFDraw {
    /// Page content only, through Core Graphics: `PDFPage.draw(with:to:)` always paints the annotations with
    /// PDFKit's own look (solid markers, per-segment opacity), so Redline never uses it. The context is the display
    /// box, y up; PDFKit's page transform applies the rotation.
    static func content(of page: PDFPage, in cg: CGContext) {
        guard let ref = page.pageRef else { return }
        cg.saveGState()
        cg.concatenate(page.transform(for: .cropBox))
        cg.clip(to: page.bounds(for: .cropBox))
        cg.drawPDFPage(ref)
        cg.restoreGState()
    }

    /// Page content plus annotations (thumbnails, exports).
    static func page(_ page: PDFPage, in cg: CGContext) {
        content(of: page, in: cg)
        annotations(of: page, in: cg)
    }

    /// Draws a page's annotations into a context set up like `content(of:in:)` (display box, y up): foreign ones
    /// through PDFKit from their appearance streams, Redline's own through their drawing subclasses.
    static func annotations(of page: PDFPage, in cg: CGContext, include: (PDFAnnotation) -> Bool = { _ in true },
                            after: ((PDFAnnotation, CGContext) -> Void)? = nil) {
        cg.saveGState()
        cg.concatenate(page.transform(for: .cropBox))
        for a in page.annotations where a.shouldDisplay && !a.isPopup && !a.isReply && !a.isStateAnnotation && include(a) {
            a.draw(with: .cropBox, in: cg)
            after?(a, cg)
        }
        cg.restoreGState()
    }

    /// Whole page (content + annotations) as an image `width` points wide, rendered now on the calling thread.
    static func image(of page: PDFPage, width: CGFloat, scale: CGFloat = 1) -> UIImage {
        let disp = PDFService.displaySize(page)
        let size = CGSize(width: width, height: max(1, (width * disp.height / max(1, disp.width)).rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.saveGState()
            cg.scaleBy(x: size.width / max(1, disp.width), y: size.height / max(1, disp.height))
            cg.translateBy(x: 0, y: disp.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .high
            self.page(page, in: cg)
            cg.restoreGState()
        }
    }
}

/// Serial background renderer: one page at a time, never on the main thread.
actor PDFRenderQueue {
    static let shared = PDFRenderQueue()

    /// Renders `page` into a white bitmap of `size` pixels, scaling its displayed size `disp` to fit exactly.
    func render(_ wrapped: RenderablePage, size: CGSize, disp: CGSize) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.saveGState()
            cg.scaleBy(x: size.width / disp.width, y: size.height / disp.height)
            cg.translateBy(x: 0, y: disp.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .high
            PDFDraw.page(wrapped.page, in: cg)
            cg.restoreGState()
        }
    }
}

/// PDFKit access for imported markups: page images (rendered asynchronously, cached), thumbnails,
/// and text-line geometry so highlights snap to the page's text.
@MainActor
@Observable
final class PDFService {
    /// Bumped whenever a background render finishes; views read it to refresh.
    private(set) var revision = 0

    @ObservationIgnored private var docs: [String: PDFDocument] = [:]
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private var imageOrder: [String] = []
    @ObservationIgnored private var thumbs: [String: UIImage] = [:]
    @ObservationIgnored private var pending: Set<String> = []
    /// PDFs opened in place: "ext:<id>" → their resolved URL (security scope held while registered).
    @ObservationIgnored private var external: [String: URL] = [:]
    private let maxImages = 12

    func register(_ file: String, url: URL) { external[file] = url; docs[file] = nil }

    /// Modification date on disk.
    func modificationDate(_ file: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: file).path))?[.modificationDate] as? Date
    }
    @ObservationIgnored private var loadedDates: [String: Date] = [:]
    @ObservationIgnored private var lastChecks: [String: Date] = [:]

    /// Drops everything cached for a file (document, page images, thumbnails) so it reloads from disk; the
    /// in-place registration is kept.
    func reload(_ file: String) {
        docs[file] = nil
        loadedDates[file] = nil
        for k in images.keys where k.hasPrefix(file + "#") { images[k] = nil }
        for k in thumbs.keys where k.hasPrefix("t:" + file + "#") { thumbs[k] = nil }
        imageOrder.removeAll { $0.hasPrefix(file + "#") }
        revision += 1
    }

    /// Reloads a cached file if it changed on disk since it was loaded (checked at most every few seconds).
    func refreshIfChanged(_ file: String) {
        let now = Date()
        if let last = lastChecks[file], now.timeIntervalSince(last) < 4 { return }
        lastChecks[file] = now
        guard docs[file] != nil, let loaded = loadedDates[file], let mod = modificationDate(file), mod.timeIntervalSince(loaded) > 1 else { return }
        reload(file)
    }

    /// Records the on-disk date as "what we have" (after our own save).
    func noteSaved(_ file: String) { loadedDates[file] = modificationDate(file) ?? Date() }
    /// When the cached document was read from disk (or last saved) — shared by every window showing it.
    func loadedDate(_ file: String) -> Date? { loadedDates[file] }
    func isExternal(_ file: String) -> Bool { file.hasPrefix("ext:") }
    func externalURL(_ file: String) -> URL? { external[file] }

    /// Library PDFs: Documents/PDFs (visible in the Files app), or the PDFs folder of the chosen library folder.
    static var directory: URL { LibraryHub.shared.pdfDirectory }

    /// Drops every cached document and image (the library moved); in-place registrations are kept.
    func resetCaches() {
        docs = [:]; images = [:]; thumbs = [:]; imageOrder = []; loadedDates = [:]; lastChecks = [:]
        revision += 1
    }

    func url(for file: String) -> URL { external[file] ?? PDFService.directory.appendingPathComponent(file) }

    func document(_ file: String) -> PDFDocument? {
        if let d = docs[file] { return d }
        // Coordinated read: a file in iCloud Drive that isn't downloaded yet is fetched first.
        var loaded: PDFDocument? = nil
        var err: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: url(for: file), options: [], error: &err) { u in loaded = PDFDocument(url: u) }
        guard let d = loaded else { return nil }
        docs[file] = d
        loadedDates[file] = modificationDate(file) ?? Date()
        return d
    }

    func page(_ file: String, _ index: Int) -> PDFPage? { document(file)?.page(at: index) }

    /// Drops cached page images and thumbnails (the PDF changed) but keeps the loaded document.
    func invalidateImages(_ file: String) {
        for k in images.keys where k.hasPrefix(file + "#") { images[k] = nil }
        for k in thumbs.keys where k.hasPrefix("t:" + file + "#") { thumbs[k] = nil }
        imageOrder.removeAll { $0.hasPrefix(file + "#") }
        revision += 1
    }

    func forget(_ file: String) {
        docs[file] = nil
        external[file] = nil
        for k in images.keys where k.hasPrefix(file + "#") { images[k] = nil }
        for k in thumbs.keys where k.hasPrefix("t:" + file + "#") { thumbs[k] = nil }
        imageOrder.removeAll { $0.hasPrefix(file + "#") }
        revision += 1
    }

    // MARK: geometry

    /// Size of the page as displayed (rotation applied), in PDF points.
    nonisolated static func displaySize(_ page: PDFPage) -> CGSize {
        let b = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// Page space → displayed space (origin top-left, y down, PDF points).
    nonisolated static func pageToDisplay(_ page: PDFPage) -> CGAffineTransform {
        let size = displaySize(page)
        let flip = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: size.height))
        return page.transform(for: .cropBox).concatenating(flip)
    }

    /// Logical canvas size (1000 wide) matching the page's aspect ratio.
    nonisolated static func canvasSize(for page: PDFPage) -> Size {
        let s = displaySize(page)
        guard s.width > 0, s.height > 0 else { return Metrics.sheetCanvas }
        return Size(1000, (1000 * s.height / s.width).rounded())
    }

    // MARK: rendering (async)

    /// Full page at 2× the canvas size. Returns the cached image, or nil while it renders in the background.
    func image(file: String, index: Int, canvas: Size) -> UIImage? {
        let key = "\(file)#\(index)"
        if let img = images[key] { return img }
        request(key: key, file: file, index: index, width: canvas.w * 2, thumb: false)
        return nil
    }

    /// Small (400 px wide) rendering for the home tiles; nil while it renders.
    func thumbnail(file: String, index: Int) -> UIImage? {
        refreshIfChanged(file)
        let key = "t:\(file)#\(index)"
        if let t = thumbs[key] { return t }
        request(key: key, file: file, index: index, width: 400, thumb: true)
        return nil
    }

    private func request(key: String, file: String, index: Int, width: Double, thumb: Bool) {
        guard !pending.contains(key), let page = page(file, index) else { return }
        let disp = PDFService.displaySize(page)
        guard disp.width > 0, disp.height > 0 else { return }
        pending.insert(key)
        let size = CGSize(width: width, height: (width * disp.height / disp.width).rounded())
        let wrapped = RenderablePage(page: page)
        Task { [weak self] in
            let img = await PDFRenderQueue.shared.render(wrapped, size: size, disp: disp)
            self?.store(key: key, image: img, thumb: thumb)
        }
    }

    private func store(key: String, image: UIImage, thumb: Bool) {
        pending.remove(key)
        if thumb {
            thumbs[key] = image
        } else {
            images[key] = image
            imageOrder.append(key)
            if imageOrder.count > maxImages { let old = imageOrder.removeFirst(); images[old] = nil }
        }
        revision += 1
    }

    // MARK: text

    /// Text-line rectangles (canvas coordinates) covered by a drag from `a` to `b` on the page.
    func textLineRects(file: String, index: Int, from a: Point, to b: Point, canvas: Size) -> [Rect] {
        guard let page = page(file, index) else { return [] }
        let disp = PDFService.displaySize(page)
        guard disp.width > 0, canvas.w > 0 else { return [] }
        let k = disp.width / canvas.w
        let fwd = PDFService.pageToDisplay(page)
        let inv = fwd.inverted()
        let pa = CGPoint(x: a.x * k, y: a.y * k).applying(inv)
        let pb = CGPoint(x: b.x * k, y: b.y * k).applying(inv)
        guard let sel = page.selection(from: pa, to: pb) else { return [] }
        var out: [Rect] = []
        for line in sel.selectionsByLine() {
            let r = line.bounds(for: page)
            if r.isEmpty || r.width < 0.5 { continue }
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
                .map { $0.applying(fwd) }
                .map { Point($0.x / k, $0.y / k) }
            out.append(Rect.bounding(corners))
        }
        return out
    }

    /// Whether the page has any selectable text at all.
    func hasText(file: String, index: Int) -> Bool {
        guard let page = page(file, index) else { return false }
        return page.numberOfCharacters > 0
    }
}
