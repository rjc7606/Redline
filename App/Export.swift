import SwiftUI
import UIKit
import RedlineCore

/// Renders pages with the same renderer as the screen and packages them as PDF / PNG.
@MainActor
enum PDFExporter {
    static func export(editor: WorkspaceModel, kind: ExportKind) -> URL? {
        let doc = editor.doc
        let base = doc.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".pdf", with: "")
        switch kind {
        case .png:
            guard let img = pageImage(editor: editor, pageIndex: editor.pageIndex, mode: .asSeen), let data = img.pngData() else { return nil }
            return write(data, name: "\(base) — page \(editor.pageIndex + 1).png")
        case .pdf(let mode):
            return write(pdf(editor: editor, pages: Array(doc.pages.indices), mode: mode, report: false), name: "\(base).pdf")
        case .commentReport:
            return write(pdf(editor: editor, pages: Array(doc.pages.indices), mode: .asSeen, report: true), name: "\(base) — annotated.pdf")
        case .taggedPDF:
            guard let tag = editor.tagFilter else { return nil }
            let pages = doc.pages.indices.filter { doc.pages[$0].tags.contains(tag) }
            guard !pages.isEmpty else { return nil }
            return write(pdf(editor: editor, pages: pages, mode: .asSeen, report: false), name: "\(base) — \(tag).pdf")
        }
    }

    static func pageImage(editor: WorkspaceModel, pageIndex: Int, mode: LayerMode) -> UIImage? {
        var input = editor.renderInput(page: pageIndex, zoom: 1, interactive: false)
        switch mode {
        case .asSeen: break
        case .fullStrength: input.page.layers = input.page.layers.map { var l = $0; l.opacity = 0; return l }
        case .baseOnly: input.page.layers = Array(input.page.layers.prefix(1))
        }
        let f = editor.frameSize(page: pageIndex)
        let view = PageCanvas(input: input, size: f).environment(\.theme, Theme(.light))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    private static func pdf(editor: WorkspaceModel, pages: [Int], mode: LayerMode, report: Bool) -> Data {
        let doc = editor.doc
        let first = editor.frameSize(page: pages.first ?? 0)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first))
        return renderer.pdfData { c in
            for i in pages {
                let f = editor.frameSize(page: i)
                c.beginPage(withBounds: CGRect(origin: .zero, size: f), pageInfo: [:])
                if let img = pageImage(editor: editor, pageIndex: i, mode: mode) { img.draw(in: CGRect(origin: .zero, size: f)) }
            }
            if report, !doc.comments.isEmpty {
                c.beginPage(withBounds: CGRect(origin: .zero, size: first), pageInfo: [:])
                let para = NSMutableParagraphStyle(); para.lineSpacing = 3
                let title = NSAttributedString(string: "Comments — \(doc.name)\n\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 18), .paragraphStyle: para])
                let body = NSMutableAttributedString(attributedString: title)
                let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
                for cm in doc.comments.sorted(by: { ($0.pageID, $0.time) < ($1.pageID, $1.time) }) {
                    let pi = (doc.pageIndex(of: cm.pageID) ?? 0) + 1
                    let head = "p.\(pi) · \(cm.author) · \(df.string(from: cm.time)) · \(cm.status.rawValue)\n"
                    body.append(NSAttributedString(string: head, attributes: [.font: UIFont.boldSystemFont(ofSize: 11), .paragraphStyle: para]))
                    if !cm.text.isEmpty { body.append(NSAttributedString(string: cm.text + "\n", attributes: [.font: UIFont.systemFont(ofSize: 11), .paragraphStyle: para])) }
                    for r in cm.replies {
                        body.append(NSAttributedString(string: "    ↳ \(r.author): \(r.text)\n", attributes: [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor.darkGray, .paragraphStyle: para]))
                    }
                    body.append(NSAttributedString(string: "\n"))
                }
                body.draw(in: CGRect(x: 40, y: 40, width: first.width - 80, height: first.height - 80))
            }
        }
    }

    private static func write(_ data: Data, name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RedlineExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}
