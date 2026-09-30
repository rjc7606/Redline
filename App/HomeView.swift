import SwiftUI
import UniformTypeIdentifiers
import RedlineCore

extension DocumentType {
    /// Colour that identifies the tool on the home screen.
    var tint: Color { Color(hex: modeChipHex.fg) }
    var blurb: String {
        switch self {
        case .markup: "PDFs with comments any reader can open. Every mark carries an author and a time."
        case .drawing: "Multi-page plan sets with trace-paper layers you can veil, lock and flatten."
        case .journal: "Paged notebooks with paper, templates, tags and a calendar."
        }
    }
    var singular: String {
        switch self { case .markup: "markup"; case .drawing: "plan set"; case .journal: "notebook" }
    }
}

enum HomeSort: String, CaseIterable { case recent = "Recent", name = "Name" }

/// Home: an overview of the three tools, each with its own recents rail, or one tool's full library.
struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let shelf = app.homeShelf {
                Group {
                    if shelf == .markup { MarkupLibrary() } else { ShelfLibrary(shelf: shelf) }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                HomeOverview()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: app.homeShelf)
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

// MARK: - Overview (three tool shelves)

struct HomeOverview: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    Text("Redline").font(fnt(30, .heavy)).foregroundStyle(theme.ink1)
                    Spacer()
                    SearchField(text: $app.homeQuery).frame(maxWidth: 320)
                    BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
                }
                ForEach(DocumentType.allCases, id: \.self) { t in
                    ToolShelf(type: t, query: app.homeQuery)
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
        }
        .background(theme.bg)
    }
}

/// One tool's band: identity header, New button, and a horizontal rail of recent documents.
struct ToolShelf: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var type: DocumentType
    var query: String

    var body: some View {
        let all = app.store.documents(on: type)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let docs = q.isEmpty ? Array(all.prefix(12)) : all.filter { $0.name.lowercased().contains(q) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Button { open() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: type.symbol)
                            .font(fnt(21, .semibold)).foregroundStyle(type.tint)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(type.tint.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(type.shelfLabel).font(fnt(22, .bold)).foregroundStyle(theme.ink1)
                                Text("\(all.count)").font(fnt(12, .bold)).foregroundStyle(theme.ink4)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(theme.hov))
                                Image(systemName: "chevron.right").font(fnt(13, .semibold)).foregroundStyle(theme.ink4)
                            }
                            Text(type.blurb).font(fnt(12.5)).foregroundStyle(theme.ink3).lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Button { app.settings.shelf = type; app.newDraft = NewDocumentDraft(type: type) } label: {
                    HStack(spacing: 7) { Image(systemName: "plus").font(fnt(14, .bold)); Text("New").font(fnt(13.5, .bold)) }
                        .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(type.tint))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.newLabel)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(docs) { d in
                        DocTile(doc: d).frame(width: type == .journal ? 150 : 190)
                    }
                    if docs.isEmpty {
                        EmptyShelfCard(type: type, searching: !q.isEmpty) { app.settings.shelf = type; app.newDraft = NewDocumentDraft(type: type) }
                    } else if q.isEmpty && all.count > docs.count {
                        Button { open() } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "square.grid.2x2").font(fnt(22, .medium))
                                Text("See all \(all.count)").font(fnt(13, .bold))
                            }
                            .foregroundStyle(type.tint)
                            .frame(width: 150).aspectRatio(type == .journal ? 0.78 : 1.32, contentMode: .fit)
                            .background(RoundedRectangle(cornerRadius: 8).fill(type.tint.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(type.tint.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.line, lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(type.tint).frame(width: 5).padding(.vertical, 18).offset(x: -1)
        }
    }

    private func open() {
        app.settings.shelf = type
        app.homeSort = .recent
        app.homeShelf = type
    }
}

struct EmptyShelfCard: View {
    @Environment(\.theme) private var theme
    var type: DocumentType
    var searching: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: searching ? "magnifyingglass" : "plus").font(fnt(22, .medium))
                Text(searching ? "No matches" : "Create your first \(type.singular)").font(fnt(13, .bold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(searching ? theme.ink4 : type.tint)
            .frame(width: 190).aspectRatio(1.32, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
        .buttonStyle(.plain)
        .disabled(searching)
    }
}

/// Rounded search field with a magnifier.
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
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.bg3))
    }
}

// MARK: - One tool's full library

struct ShelfLibrary: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var shelf: DocumentType

    var body: some View {
        @Bindable var app = app
        let q = app.homeQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var docs = app.store.documents(on: shelf).filter { q.isEmpty || $0.name.lowercased().contains(q) }
        if app.homeSort == .name { docs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Button { app.homeShelf = nil } label: {
                        HStack(spacing: 2) { Image(systemName: "chevron.left").font(fnt(17, .semibold)); Text("Home").font(fnt(15)) }
                            .foregroundStyle(theme.accent)
                    }.buttonStyle(.plain)
                    Image(systemName: shelf.symbol).font(fnt(19, .semibold)).foregroundStyle(shelf.tint)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(shelf.tint.opacity(0.14)))
                    Text(shelf.shelfLabel).font(fnt(30, .heavy)).foregroundStyle(theme.ink1)
                    Spacer()
                    SearchField(text: $app.homeQuery).frame(maxWidth: 260)
                    SegmentControl(options: HomeSort.allCases.map { SegmentOption(value: $0, label: $0.rawValue) }, selection: $app.homeSort, fontSize: 12.5, vPad: 6, hPad: 12)
                    Button { app.settings.shelf = shelf; app.newDraft = NewDocumentDraft(type: shelf) } label: {
                        HStack(spacing: 7) { Image(systemName: "plus").font(fnt(14, .bold)); Text(shelf.newLabel).font(fnt(13.5, .bold)) }
                            .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(shelf.tint))
                    }.buttonStyle(.plain)
                    BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
                }
                if docs.isEmpty {
                    Text(q.isEmpty ? "Nothing here yet." : "No \(shelf.shelfLabel.lowercased()) match \"\(app.homeQuery)\".")
                        .font(fnt(14)).foregroundStyle(theme.ink4).frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: shelf == .journal ? 150 : 190), spacing: 22)], spacing: 26) {
                        ForEach(docs) { d in DocTile(doc: d) }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
        }
        .background(theme.bg)
    }
}

struct DocTile<Extra: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var doc: Document
    /// Show the library folder under the name (Recents / Favorites / search results).
    var showFolder = false
    /// Extra context-menu items (library actions).
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                Button { app.pendingDelete = doc.id } label: {
                    Image(systemName: "xmark").font(fnt(11, .heavy)).foregroundStyle(theme.ink4).frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.85)))
                }.buttonStyle(.plain).padding(6).opacity(0.5)
            }
            .aspectRatio(tileAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if doc.isFavorite { Image(systemName: "star.fill").font(fnt(10)).foregroundStyle(Color(hex: "#FF9500")) }
                    Text(doc.name).font(fnt(13.5, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                }
                Text(Formatting.tileMeta(pages: doc.pages.count, modified: doc.modified)).font(fnt(11.5)).foregroundStyle(theme.ink4)
                if showFolder {
                    Text("Redline" + (doc.folderPath.isEmpty ? "" : " › " + doc.folderPath.replacingOccurrences(of: "/", with: " › ")))
                        .font(fnt(11)).foregroundStyle(theme.ink4).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.openDocument(doc.id) }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.right.square") { app.openDocument(doc.id) }
            extra()
            Button("Delete", systemImage: "trash", role: .destructive) { app.pendingDelete = doc.id }
        }
    }

    /// Markup tiles take the shape of the document's first page.
    private var tileAspect: CGFloat {
        switch doc.type {
        case .journal: 0.78
        case .drawing: 1.32
        case .markup: CGFloat(max(0.5, min(2.0, doc.canvasSize.w / doc.canvasSize.h)))
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch doc.type {
        case .markup:
            ZStack(alignment: .bottomLeading) {
                Color.white
                DocumentThumbnail(doc: doc)
                badge("doc.text", Formatting.plural(doc.pages.count, "page"))
                Text("PDF").font(fnt(9, .heavy)).tracking(0.5).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#e8483f")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
            }
        case .drawing:
            ZStack(alignment: .bottomLeading) {
                theme.bg3
                RoundedRectangle(cornerRadius: 3).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: "#c9c9cf"))).padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 30))
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.75)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: "#c9c9cf"))).padding(EdgeInsets(top: 12, leading: 24, bottom: 24, trailing: 24))
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.6)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: "#c9c9cf")))
                    .overlay(GlyphView(d: "M14 44V16h30v28zM44 30h22M66 16v28", size: 90, color: Color(hex: "#e8483f")).scaleEffect(0.7))
                    .padding(EdgeInsets(top: 6, leading: 30, bottom: 30, trailing: 18))
                badge("square.stack", Formatting.plural(doc.layerCount, "layer"))
            }
        case .journal:
            let paper = doc.pages.first?.paper ?? .cream
            let fg = paper.isDark ? Color(hex: "#f2f2f7") : Color(hex: "#1c1c1e")
            ZStack(alignment: .topLeading) {
                Color(hex: paper.hex)
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: 14).frame(maxHeight: .infinity)
                Text(doc.name).font(fnt(14, .heavy)).foregroundStyle(fg).lineLimit(3).padding(.leading, 26).padding(.trailing, 14).padding(.top, 22)
                HStack(spacing: 4) { Image(systemName: "tag").font(fnt(10)); Text(Formatting.plural(doc.tagCounts().count, "tag")).font(fnt(10, .semibold)) }
                    .foregroundStyle(fg.opacity(0.75)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 26).padding(.bottom, 12)
            }
        }
    }

    private func badge(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol).font(fnt(10)); Text(text).font(fnt(10, .bold)) }
            .foregroundStyle(Color(hex: "#6d6d72")).padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.9)))
            .padding(8)
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
                Text(draft.type.newSheetTitle).font(fnt(20, .heavy)).foregroundStyle(theme.ink1)
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
                            // Live model of the page: paper, colour and orientation.
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
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? theme.accent : theme.line, lineWidth: on ? 2 : 1))
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
                                            Circle().fill(Color(hex: p.hex)).frame(width: 34, height: 34)
                                                .overlay(Circle().stroke(theme.line2, lineWidth: 1))
                                                .overlay(Circle().stroke(theme.accent, lineWidth: draft.paper == p ? 2.5 : 0).padding(-4))
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
                        SectionLabel(text: "Template")
                        HStack(spacing: 10) {
                            ForEach(PageTemplate.allCases, id: \.self) { t in
                                let on = draft.template == t
                                VStack(spacing: 6) {
                                    TemplateSwatch(template: t, paper: draft.paper)
                                        .aspectRatio(0.78, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? theme.accent : theme.line, lineWidth: 1.5))
                                        .shadow(color: on ? theme.accent.opacity(0.25) : .clear, radius: 0, x: 0, y: 0)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.accent.opacity(on ? 0.25 : 0), lineWidth: 6).padding(-3))
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
                                    .overlay(Circle().stroke(theme.line, lineWidth: 1))
                                    .overlay(Circle().stroke(theme.accent.opacity(draft.paper == p ? 0.35 : 0), lineWidth: 3).padding(-3))
                                    .onTapGesture { app.newDraft?.paper = p }
                                    .accessibilityLabel(p.label)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    SecondaryButton(label: "Cancel", height: 36) { app.newDraft = nil }
                    PrimaryButton(label: "Create") { app.createFromDraft() }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: Metrics.modalWidth)
            .background(theme.popSolid)
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
                                            accentHex: "#007AFF", showSelection: false)
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
