import UIKit
import PDFKit
import RedlineCore

/// PDFKit access for imported markups: page rendering at the document's canvas size,
/// and text-line geometry so highlights snap to the page's text.
@MainActor
final class PDFService {
    private var docs: [String: PDFDocument] = [:]
    private var images: [String: UIImage] = [:]
    private var imageOrder: [String] = []
    private let maxImages = 12

    /// Imported PDFs live in Documents/PDFs so they show up in the Files app.
    static var directory: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PDFs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func url(for file: String) -> URL { PDFService.directory.appendingPathComponent(file) }

    func document(_ file: String) -> PDFDocument? {
        if let d = docs[file] { return d }
        guard let d = PDFDocument(url: url(for: file)) else { return nil }
        docs[file] = d
        return d
    }

    func page(_ file: String, _ index: Int) -> PDFPage? { document(file)?.page(at: index) }

    func forget(_ file: String) {
        docs[file] = nil
        for k in images.keys where k.hasPrefix(file + "#") { images[k] = nil }
        imageOrder.removeAll { $0.hasPrefix(file + "#") }
    }

    // MARK: geometry

    /// Size of the page as displayed (rotation applied), in PDF points.
    static func displaySize(_ page: PDFPage) -> CGSize {
        let b = page.bounds(for: .mediaBox)
        return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// Page space → displayed space (origin top-left, y down, PDF points).
    static func pageToDisplay(_ page: PDFPage) -> CGAffineTransform {
        let size = displaySize(page)
        let flip = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: size.height))
        return page.transform(for: .mediaBox).concatenating(flip)
    }

    /// Logical canvas size (1000 wide) matching the page's aspect ratio.
    static func canvasSize(for page: PDFPage) -> Size {
        let s = displaySize(page)
        guard s.width > 0, s.height > 0 else { return Metrics.sheetCanvas }
        return Size(1000, (1000 * s.height / s.width).rounded())
    }

    // MARK: rendering

    /// Renders a page at 2× the canvas size (white background).
    func image(file: String, index: Int, canvas: Size) -> UIImage? {
        let key = "\(file)#\(index)"
        if let img = images[key] { return img }
        guard let page = page(file, index) else { return nil }
        let disp = PDFService.displaySize(page)
        guard disp.width > 0, disp.height > 0 else { return nil }
        let scale = 2.0
        let size = CGSize(width: canvas.w * scale, height: canvas.h * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.saveGState()
            cg.scaleBy(x: size.width / disp.width, y: size.height / disp.height)
            cg.translateBy(x: 0, y: disp.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .high
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
        images[key] = img
        imageOrder.append(key)
        if imageOrder.count > maxImages { let old = imageOrder.removeFirst(); images[old] = nil }
        return img
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

    /// Whether the page has any selectable text at all (used to fall back to freehand highlighting).
    func hasText(file: String, index: Int) -> Bool {
        guard let page = page(file, index) else { return false }
        return (page.numberOfCharacters) > 0
    }
}
