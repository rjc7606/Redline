import SwiftUI
import UniformTypeIdentifiers
import RedlineCore

extension DocumentType {
    /// Colour that identifies the tool on the home screen.
    var tint: Color { Color(hex: modeChipHex.fg) }
    var singular: String {
        switch self { case .markup: "markup"; case .drawing: "drawing"; case .journal: "notebook" }
    }
    /// Rail title on the Home "Recents" pane.
    var railLabel: String {
        switch self { case .markup: "Recent markups"; case .drawing: "Recent drawings"; case .journal: "Recent notebooks" }
    }
}

enum HomeSort: String, CaseIterable { case recent = "Recent", name = "Name" }

/// Home (handoff v2): a two-column file browser. The left column lists every tool's places; the right pane shows
/// the Recents rails, a Markups folder, or a Drawings / Notes gallery.
struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        HomeBrowser()
            .sheet(isPresented: Binding(get: { app.newDraft != nil }, set: { if !$0 { app.newDraft = nil } })) {
                NewDocumentSheet()
            }
            .alert("Delete document?", isPresented: Binding(get: { app.pendingDelete != nil }, set: { if !$0 { app.pendingDelete = nil } })) {
                Button("Delete", role: .destructive) { if let id = app.pendingDelete { app.deleteDocument(id) }; app.pendingDelete = nil }
                Button("Cancel", role: .cancel) { app.pendingDelete = nil }
            } message: {
                Text("\"\(app.pendingDelete.flatMap { app.store.document($0)?.name } ?? "")\" will be removed from this iPad.")
            }
    }
}

/// Rounded search field with a magnifier (34 tall, radius 9, `field` background).
struct SearchField: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(fnt(14, .semibold)).foregroundStyle(theme.ink4)
            TextField("Search", text: $text).font(fnt(14)).textFieldStyle(.plain).foregroundStyle(theme.ink1)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(fnt(14)).foregroundStyle(theme.ink4) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.field))
    }
}

// MARK: - Document tile

/// Library tile (handoff v2): 132-wide page thumbnail at the page's aspect (notebooks: 104 × 140 cover),
/// name 13/600, meta 11.5/500. No badges on the face; delete lives in the context menu.
struct DocTile<Extra: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var doc: Document
    /// Show the library folder under the name (Recents / Favorites / search results).
    var showFolder = false
    /// Extra context-menu items (library actions).
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            face
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if doc.isFavorite { Image(systemName: "star.fill").font(fnt(10)).foregroundStyle(Color(hex: "#FF9500")) }
                    Text(doc.name).font(fnt(13, .semibold)).foregroundStyle(theme.ink1).lineLimit(1).truncationMode(.middle)
                }
                Text(meta).font(fnt(11.5, .medium)).foregroundStyle(theme.ink4).lineLimit(1)
                if showFolder {
                    Text("Redline" + (doc.folderPath.isEmpty ? "" : " › " + doc.folderPath.replacingOccurrences(of: "/", with: " › ")))
                        .font(fnt(11)).foregroundStyle(theme.ink4).lineLimit(1)
                }
            }
        }
        .frame(width: tileWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { app.openDocument(doc.id) }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.right.square") { app.openDocument(doc.id) }
            extra()
            Button("Delete", systemImage: "trash", role: .destructive) { app.pendingDelete = doc.id }
        }
    }

    private var tileWidth: CGFloat { doc.type == .journal ? Metrics.notebookTile.w : Metrics.docTile }

    private var meta: String {
        let ago = Formatting.ago(doc.modified)
        switch doc.type {
        case .markup: return Formatting.plural(doc.pages.count, "page") + " · " + ago
        case .drawing: return Formatting.plural(doc.pages.count, "page") + " · " + Formatting.plural(doc.layerCount, "layer") + " · " + ago
        case .journal: return Formatting.plural(max(0, doc.pages.count - 1), "page") + " · " + Formatting.plural(doc.tagCounts().count, "tag") + " · " + ago
        }
    }

    /// Markup and drawing tiles take the shape of the first page.
    private var pageAspect: CGFloat { CGFloat(max(0.5, min(2.0, doc.canvasSize.w / doc.canvasSize.h))) }

    @ViewBuilder
    private var face: some View {
        switch doc.type {
        case .markup:
            ZStack { Color.white; DocumentThumbnail(doc: doc) }
                .frame(width: Metrics.docTile, height: (Metrics.docTile / pageAspect).rounded())
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line, lineWidth: 1))
                .pageShadow(theme)
        case .drawing:
            // Page stack (three sheets offset 3 pt, the front one rendered) on a bg3 backing box.
            let w = Metrics.docTile - 30, h = ((Metrics.docTile - 30) / pageAspect).rounded()
            ZStack(alignment: .topLeading) {
                ForEach([2, 1], id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .frame(width: w, height: h).offset(x: CGFloat(i) * 3, y: CGFloat(i) * 3)
                }
                ZStack { Color.white; DocumentThumbnail(doc: doc) }
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(theme.line, lineWidth: 1))
            }
            .padding(12)
            .frame(width: Metrics.docTile, height: h + 30, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.bg3))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line, lineWidth: 1))
            .pageShadow(theme)
        case .journal:
            // The cover page, rendered with its styling and ink, is the thumbnail (GoodNotes-style).
            let shape = UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
            ZStack(alignment: .topLeading) {
                Color(hex: doc.coverHex)
                DocumentThumbnail(doc: doc)
            }
            .frame(width: Metrics.notebookTile.w, height: Metrics.notebookTile.h)
            .clipShape(shape)
            .overlay(shape.stroke(theme.line, lineWidth: 1))
            .pageShadow(theme)
        }
    }
}

extension DocTile where Extra == EmptyView {
    init(doc: Document, showFolder: Bool = false) {
        self.doc = doc
        self.showFolder = showFolder
        self.extra = { EmptyView() }
    }
}

// MARK: - New document sheet

struct NewDocumentSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @State private var importing = false

    var body: some View {
        if let draft = app.newDraft {
            let d = Binding(get: { app.newDraft ?? draft }, set: { app.newDraft = $0 })
            VStack(alignment: .leading, spacing: 18) {
                Text(draft.type.newSheetTitle).font(titleFnt(20)).foregroundStyle(theme.ink1)
                FieldText(placeholder: "Name", text: d.name, height: 40, font: fnt(15))
                if draft.type == .markup {
                    VStack(spacing: 8) {
                        Button { importing = true } label: {
                            HStack(spacing: 8) { Image(systemName: "square.and.arrow.up").font(fnt(17, .medium)); Text(draft.pdfFile == nil ? "Import a PDF" : "PDF imported · \(draft.pdfPages ?? 0) pages").font(fnt(14, .semibold)) }
                                .foregroundStyle(theme.accent).frame(maxWidth: .infinity).padding(22)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        }.buttonStyle(.plain)
                        Text("or create a new PDF on the paper below").font(fnt(12)).foregroundStyle(theme.ink4)
                    }
                    .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.pdf]) { result in
                        if case .success(let url) = result, let r = app.importPDF(from: url) {
                            app.newDraft?.pdfFile = r.file
                            app.newDraft?.pdfPages = r.pages
                            app.newDraft?.sheetSize = r.sheetSize
                            if app.newDraft?.name.isEmpty ?? false { app.newDraft?.name = url.deletingPathExtension().lastPathComponent }
                        } else {
                            app.flash("Could not import that PDF")
                        }
                    }
                    if draft.pdfFile == nil {
                        HStack(alignment: .top, spacing: 22) {
                            // Live model of the page: paper, colour and orientation (max height 260 so the sheet fits 11" portrait).
                            VStack(spacing: 8) {
                                TemplateSwatch(template: draft.template, paper: draft.paper)
                                    .aspectRatio(draft.landscape ? 1.294 : 0.773, contentMode: .fit)
                                    .frame(height: draft.landscape ? 170 : 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.line2, lineWidth: 1))
                                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                                    .animation(.easeInOut(duration: 0.2), value: draft.landscape)
                                Text("US Letter · \(draft.landscape ? "Landscape" : "Portrait")").font(fnt(11.5, .semibold)).foregroundStyle(theme.ink4)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionLabel(text: "Paper")
                                    HStack(spacing: 8) {
                                        ForEach(PageTemplate.allCases, id: \.self) { t in
                                            let on = draft.template == t
                                            VStack(spacing: 5) {
                                                TemplateSwatch(template: t, paper: draft.paper)
                                                    .frame(width: 44, height: 56)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(on ? theme.accent : theme.line, lineWidth: on ? 2 : 1))
                                                Text(t.label).font(fnt(11, .semibold)).foregroundStyle(on ? theme.accent : theme.ink2)
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture { app.newDraft?.template = t }
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionLabel(text: "Color")
                                    HStack(spacing: 10) {
                                        ForEach(Paper.pagePresets, id: \.self) { p in
                                            Circle().fill(Color(hex: p.hex)).frame(width: 36, height: 36)
                                                .overlay(Circle().stroke(theme.line2, lineWidth: 1))
                                                .overlay(Circle().stroke(theme.accent, lineWidth: draft.paper == p ? 2 : 0).padding(-4))
                                                .onTapGesture { app.newDraft?.paper = p }
                                                .accessibilityLabel(p.label)
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionLabel(text: "Orientation")
                                    SegmentControl(options: [SegmentOption(value: false, label: "Portrait"), SegmentOption(value: true, label: "Landscape")],
                                                   selection: Binding(get: { app.newDraft?.landscape ?? false }, set: { app.newDraft?.landscape = $0 }), fontSize: 12.5, vPad: 6, fill: true)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Cover")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(Covers.palette, id: \.self) { c in
                                let on = HexColor.same(draft.coverColor, c)
                                Circle().fill(Color(hex: c)).frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 1))
                                    .overlay(Circle().stroke(theme.accent, lineWidth: on ? 2 : 0).padding(-4))
                                    .onTapGesture { app.newDraft?.coverColor = c }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Template")
                        HStack(spacing: 10) {
                            ForEach(PageTemplate.allCases, id: \.self) { t in
                                let on = draft.template == t
                                VStack(spacing: 6) {
                                    TemplateSwatch(template: t, paper: draft.paper)
                                        .aspectRatio(0.78, contentMode: .fit)
                                        .frame(maxHeight: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(on ? theme.accent : theme.line, lineWidth: on ? 2 : 1))
                                    Text(t.label).font(fnt(12, .semibold)).foregroundStyle(on ? theme.accent : theme.ink2)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { app.newDraft?.template = t }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Paper")
                        HStack(spacing: 10) {
                            ForEach(Paper.allCases, id: \.self) { p in
                                Circle().fill(Color(hex: p.hex)).frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(theme.line2, lineWidth: 1))
                                    .overlay(Circle().stroke(theme.accent, lineWidth: draft.paper == p ? 2 : 0).padding(-4))
                                    .onTapGesture { app.newDraft?.paper = p }
                                    .accessibilityLabel(p.label)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    SecondaryButton(label: "Cancel") { app.newDraft = nil }
                    PrimaryButton(label: "Create", tint: draft.type.tint) { app.createFromDraft() }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: Metrics.modalWidth)
            .background(theme.bg2)
            .presentationDetents([.medium, .large])
        }
    }
}

/// First page of a markup rendered with all its marks (same renderer as the canvas).
struct DocumentThumbnail: View {
    @Environment(AppModel.self) private var app
    var doc: Document
    var body: some View {
        GeometryReader { g in
            if doc.type == .markup, let f = doc.pdfFile {
                let _ = app.pdf.revision
                if let img = app.pdf.thumbnail(file: f, index: 0) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                } else {
                    Color(hex: "#f4f4f6")
                }
            } else if let pg = doc.pages.first {
                let c = doc.canvasSize
                let z = g.size.width / c.w
                let _ = app.pdf.revision
                let img = doc.pdfFile.flatMap { app.pdf.thumbnail(file: $0, index: pg.pdfPageIndex ?? 0) }
                let input = PageRenderInput(page: pg, docType: doc.type, canvas: c, transform: .identity, zoom: z, activeLayer: nil, live: nil,
                                            selection: [], eraseHits: [], highlightComment: nil, selectedField: nil, showFieldTags: false,
                                            lasso: nil, marquee: nil, blueprint: app.settings.blueprint, pdfImage: img,
                                            pdfLoading: doc.pdfFile != nil && img == nil, drawingPaper: doc.paper,
                                            accentHex: "#007AFF", showSelection: false,
                                            coverTitle: doc.type == .journal ? doc.name : nil, coverHex: doc.type == .journal ? doc.coverHex : nil)
                PageCanvas(input: input, size: CGSize(width: c.w * z, height: c.h * z), async: true)
            }
        }
    }
}

struct TemplateSwatch: View {
    var template: PageTemplate
    var paper: Paper
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: paper.hex)))
            var c = ctx
            let k = size.width / 200
            c.scaleBy(x: k, y: k)
            PageRenderer.drawTemplate(template, paperDark: paper.isDark, in: c, W: 200, H: size.height / k)
        }
    }
}
