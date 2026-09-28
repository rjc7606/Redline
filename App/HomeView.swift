import SwiftUI
import UniformTypeIdentifiers
import RedlineCore

struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < Metrics.compactThreshold
            HStack(spacing: 0) {
                if !compact { HomeNav(compact: false).frame(width: Metrics.homeNav) }
                VStack(spacing: 0) {
                    if compact { HomeNav(compact: true) }
                    ShelfContent()
                }
            }
        }
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

struct HomeNav: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var compact: Bool

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                Text("Redline").font(fnt(22, .bold)).foregroundStyle(theme.ink1)
                Spacer()
                SegmentControl(options: DocumentType.allCases.map { SegmentOption(value: $0, label: $0.shelfLabel) },
                               selection: Binding(get: { app.settings.shelf }, set: { app.settings.shelf = $0 }), fontSize: 12.5, vPad: 5, hPad: 10)
                BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
            }
            .padding(.horizontal, 16).padding(.top, 12)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Redline").font(fnt(22, .bold)).foregroundStyle(theme.ink1).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 16)
                SectionLabel(text: "Shelves").padding(.horizontal, 10).padding(.bottom, 6)
                ForEach(DocumentType.allCases, id: \.self) { t in
                    NavRow(label: t.shelfLabel, symbol: t.symbol, active: app.settings.shelf == t, trailing: "\(app.store.count(on: t))") { app.settings.shelf = t }
                }
                Spacer()
                NavRow(label: "Settings", symbol: "gearshape") { app.openSettings() }
            }
            .padding(.horizontal, 12).padding(.vertical, 18)
            .frame(maxHeight: .infinity)
            .background(theme.bg2)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
        }
    }
}

struct ShelfContent: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        let shelf = app.settings.shelf
        let docs = app.store.documents(on: shelf)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Text(shelf.shelfLabel).font(fnt(30, .heavy)).foregroundStyle(theme.ink1)
                    Spacer()
                    PrimaryButton(label: shelf.newLabel, symbol: "plus") { app.newDraft = NewDocumentDraft(type: shelf) }
                }
                if docs.isEmpty {
                    Text("Nothing on this shelf yet.").font(fnt(14)).foregroundStyle(theme.ink4).frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 22)], spacing: 26) {
                        ForEach(docs) { d in DocTile(doc: d) }
                    }
                }
            }
            .padding(.horizontal, 34).padding(.vertical, 26)
        }
    }
}

struct DocTile: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var doc: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                Button { app.pendingDelete = doc.id } label: {
                    Image(systemName: "xmark").font(fnt(11, .heavy)).foregroundStyle(theme.ink4).frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.85)))
                }.buttonStyle(.plain).padding(6).opacity(0.5)
            }
            .aspectRatio(doc.type == .journal ? 0.78 : 1.32, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name).font(fnt(13.5, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                Text(Formatting.tileMeta(pages: doc.pages.count, modified: doc.modified)).font(fnt(11.5)).foregroundStyle(theme.ink4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.openDocument(doc.id) }
        .contextMenu {
            Button("Open") { app.openDocument(doc.id) }
            Button("Delete", role: .destructive) { app.pendingDelete = doc.id }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch doc.type {
        case .markup:
            ZStack(alignment: .bottomLeading) {
                Color.white
                GlyphView(d: "M8 8h184v125H8zM168 8v125M30 30h110v80H30zM85 30v45M30 75h55", size: 200, color: Color(hex: "#22405f"))
                    .scaleEffect(0.9)
                badge("bubble.left", Formatting.plural(doc.comments.count, "comment"))
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
                        Text("or start from the sample plan set below").font(fnt(12)).foregroundStyle(theme.ink4)
                    }
                    .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.pdf]) { result in
                        if case .success(let url) = result, let r = app.importPDF(from: url) {
                            app.newDraft?.pdfFile = r.file
                            app.newDraft?.pdfPages = r.pages
                            if app.newDraft?.name.isEmpty ?? false { app.newDraft?.name = url.deletingPathExtension().lastPathComponent }
                        } else {
                            app.flash("Could not import that PDF")
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
