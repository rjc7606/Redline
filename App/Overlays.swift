import SwiftUI
import UIKit
import RedlineCore

// MARK: - Stamp gallery

struct StampGalleryView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    @State private var creating = false
    @State private var draftText = ""
    @State private var draftColor = "#E0332A"
    @State private var draftDynamic = false

    var body: some View {
        let stamps = app.settings.allStamps
        PopoverCard(width: 320) {
            VStack(alignment: .leading, spacing: 12) {
                section("Static", stamps.filter { !$0.dynamic })
                section("Dynamic — filled in when placed", stamps.filter { $0.dynamic })
                Rectangle().fill(theme.line).frame(height: 1)
                if creating { createForm } else {
                    Button { creating = true; draftText = ""; draftDynamic = false } label: {
                        HStack(spacing: 6) { Image(systemName: "plus").font(fnt(13, .semibold)); Text("Create stamp…").font(fnt(13, .semibold)) }.foregroundStyle(theme.accent)
                    }.buttonStyle(.plain)
                    Text("Long-press a stamp to add it to your Favorites tab.").font(fnt(11)).foregroundStyle(theme.ink4)
                }
            }
        }
        .frame(maxHeight: 560)
    }

    private func section(_ title: String, _ items: [StampDef]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                ForEach(items) { s in
                    let on = editor.stamp.id == s.id && editor.tool == .stamps
                    StampPreview(stamp: s, author: app.author, on: on)
                        .contentShape(Rectangle())
                        .onTapGesture { editor.useStamp(s) }
                        .contextMenu {
                            Button("Add to Favorites tab", systemImage: "star") { editor.pinStamp(s) }
                            if !s.builtIn {
                                Button("Delete stamp", systemImage: "trash", role: .destructive) {
                                    var st = app.settings; st.customStamps?.removeAll { $0.id == s.id }; app.settings = st
                                }
                            }
                        }
                }
            }
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "New stamp")
            SegmentControl(options: [SegmentOption(value: false, label: "Static"), SegmentOption(value: true, label: "Dynamic")], selection: $draftDynamic, fontSize: 12.5, vPad: 5, fill: true)
            FieldText(placeholder: draftDynamic ? "e.g. CHECKED {date} by {initials}" : "Text", text: $draftText, height: 36, font: fnt(14))
            if draftDynamic {
                HStack(spacing: 6) {
                    ForEach(StampDef.tokens, id: \.token) { t in
                        Button { draftText += (draftText.isEmpty ? "" : " ") + t.token } label: {
                            Text(t.label).font(fnt(11.5, .semibold)).foregroundStyle(theme.ink1).padding(.horizontal, 9).frame(height: 26)
                                .background(Capsule().fill(theme.hov2))
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Spectrum.quickPalette, id: \.self) { c in
                    Circle().fill(Color(hex: c)).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(theme.accent, lineWidth: HexColor.same(c, draftColor) ? 2 : 0).padding(-3))
                        .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                        .onTapGesture { draftColor = c }
                }
            }
            if !draftText.isEmpty {
                StampPreview(stamp: StampDef(text: draftText, color: draftColor, dynamic: draftDynamic), author: app.author, on: false).frame(maxWidth: 150)
            }
            HStack {
                Spacer()
                SecondaryButton(label: "Cancel", height: 32) { creating = false }
                PrimaryButton(label: "Save", height: 32) {
                    let t = draftText.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    let s = StampDef(text: t, color: draftColor, dynamic: draftDynamic)
                    var st = app.settings; st.customStamps = (st.customStamps ?? []) + [s]; app.settings = st
                    creating = false
                    editor.useStamp(s)
                }
            }
        }
    }
}

/// A stamp as it will look on the page: bold caps (or a big single mark) in a bordered box, tilted -2°.
struct StampPreview: View {
    @Environment(\.theme) private var theme
    var stamp: StampDef
    var author: String
    var on: Bool
    var body: some View {
        Text(stamp.resolved(author: author))
            .font(fnt(stamp.isMark ? 20 : 12, .bold)).tracking(stamp.isMark ? 0 : 1.2)
            .foregroundStyle(Color(hex: stamp.color)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity).padding(.vertical, stamp.isMark ? 3 : 7).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? theme.hov2 : theme.card.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: stamp.color), lineWidth: 2.5))
            .rotationEffect(.degrees(-2))
    }
}

// MARK: - Favorites tray

struct FavoritesTrayView: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        PopoverCard(width: 600) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ToolCatalog.markupTabs) { tab in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tab.label.uppercased()).font(fnt(10.5, .bold)).tracking(0.7).foregroundStyle(Color(hex: "#aeaeb2")).padding(.horizontal, 2)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                                ForEach(tab.tools, id: \.self) { t in
                                    let count = editor.pinCount(t)
                                    HStack(spacing: 8) {
                                        ToolIcon(tool: t, size: 17, color: theme.ink2)
                                        Text(t.label).font(fnt(12, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                                        Spacer(minLength: 0)
                                        if count > 0 {
                                            Text("\(count)").font(fnt(10, .bold)).foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                                                .background(Capsule().fill(theme.accent))
                                        }
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(count > 0 ? theme.accent.opacity(0.09) : .clear))
                                    .contentShape(Rectangle())
                                    .onTapGesture { editor.togglePin(t) }
                                }
                            }
                        }
                    }
                    Text("Tap a tool to add it to this Favorites tab. Long-press a tool in the strip for its presets; use its context menu to reorder or remove.")
                        .font(fnt(11)).foregroundStyle(theme.ink4)
                }
            }
            .frame(maxHeight: 430)
        }
    }
}

// MARK: - Export

struct ExportOption: Identifiable {
    var id: String
    var label: String
    var desc: String
    var symbol: String
    var kind: ExportKind
}

enum ExportKind: Equatable {
    case pdf(LayerMode)
    case png
    case commentReport
    case taggedPDF
    /// Flattened PDF written to Documents/Exports (visible in the Files app).
    case saveToFiles
}

enum LayerMode: Equatable { case asSeen, fullStrength, baseOnly }

extension WorkspaceModel {
    var exportOptions: [ExportOption] {
        switch type {
        case .markup: [
            ExportOption(id: "annotated", label: "Share PDF", desc: "The PDF with its annotations — editable in any PDF app", symbol: "doc.text", kind: .pdf(.asSeen)),
            ExportOption(id: "flat", label: "Share flattened PDF", desc: "Annotations burned into the pages", symbol: "doc.badge.gearshape", kind: .commentReport),
            ExportOption(id: "png", label: "Image of this page", desc: "PNG", symbol: "photo", kind: .png),
            ExportOption(id: "files", label: "Save flattened to Files", desc: "On My iPad › Redline › Exports", symbol: "folder", kind: .saveToFiles)
        ]
        case .drawing: [
            ExportOption(id: "seen", label: "PDF — as seen", desc: "Veils applied, exactly like the screen", symbol: "eye", kind: .pdf(.asSeen)),
            ExportOption(id: "full", label: "PDF — every sheet full strength", desc: "No veils; each trace at 100%", symbol: "square.stack", kind: .pdf(.fullStrength)),
            ExportOption(id: "base", label: "PDF — base only", desc: "Drop all layers", symbol: "doc", kind: .pdf(.baseOnly)),
            ExportOption(id: "png", label: "Image of this page", desc: "PNG at 2×", symbol: "photo", kind: .png),
            ExportOption(id: "files", label: "Save to Files", desc: "PDF in On My iPad › Redline › Exports", symbol: "folder", kind: .saveToFiles)
        ]
        case .journal: [
            ExportOption(id: "book", label: "PDF — whole book", desc: "Every page in order", symbol: "book", kind: .pdf(.asSeen)),
            ExportOption(id: "tagged", label: "PDF — tagged pages", desc: tagFilter.map { "Only pages tagged \"\($0)\"" } ?? "Pick a tag in the Tags panel first", symbol: "tag", kind: .taggedPDF),
            ExportOption(id: "png", label: "Image of this page", desc: "PNG at 2×", symbol: "photo", kind: .png),
            ExportOption(id: "files", label: "Save to Files", desc: "PDF in On My iPad › Redline › Exports", symbol: "folder", kind: .saveToFiles)
        ]
        }
    }
}

struct ExportMenu: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.doc.name).font(fnt(13.5, .bold)).foregroundStyle(theme.ink1).lineLimit(1)
                Text(Formatting.plural(editor.pageCount, "page") + (editor.type == .markup ? " · " + Formatting.plural(editor.doc.comments.count, "comment") : ""))
                    .font(fnt(11.5)).foregroundStyle(theme.ink4)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 8)
            Rectangle().fill(theme.line).frame(height: 1)
            ForEach(editor.exportOptions) { o in
                Button {
                    editor.popover = nil
                    if case .taggedPDF = o.kind, editor.tagFilter == nil { app.flash("Pick a tag in the Tags panel first"); return }
                    if o.kind == .saveToFiles {
                        let ok = editor.isPDF ? PDFExport.run(.saveToFiles, editor: editor) != nil : PDFExporter.export(editor: editor, kind: .saveToFiles) != nil
                        app.flash(ok ? "Saved to Files › Redline › Exports" : "Export failed")
                        return
                    }
                    if editor.isPDF {
                        let url: URL? = (o.kind == .commentReport) ? PDFExport.flattened(editor: editor) : PDFExport.run(o.kind, editor: editor)
                        if let url { editor.shareURL = url } else { app.flash("Export failed") }
                        return
                    }
                    if let url = PDFExporter.export(editor: editor, kind: o.kind) { editor.shareURL = url } else { app.flash("Export failed") }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: o.symbol).font(fnt(17, .medium)).foregroundStyle(theme.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.label).font(fnt(13, .semibold)).foregroundStyle(theme.ink1)
                            Text(o.desc).font(fnt(11)).foregroundStyle(theme.ink4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: Metrics.exportWidth)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
            .shadow(color: theme.popShadow, radius: 20, y: 12))
    }
}

/// UIActivityViewController wrapper for sharing exported files.
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Flatten dialog

struct FlattenDialog: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var request: FlattenRequest

    var body: some View {
        let page = editor.page
        let L = request.layerID.flatMap { id in page.layers.first { $0.id == id } }
        let below = L.flatMap { l in page.layers.firstIndex { $0.id == l.id } }.flatMap { i in i > 0 ? page.layers[i - 1] : nil }
        let keepOK = editor.doc.canKeepVeil(pageIndex: editor.pageIndex, layerID: request.layerID)
        let title = L.map { "Flatten \"\($0.name)\" down" } ?? "Flatten all layers"
        let desc = L == nil ? "All layers merge onto the Base." : "Ink merges onto \"\(below?.name ?? "Base")\"."
        let keepDesc = L == nil ? "Base stays untouched; all layer ink collapses onto one layer with the combined veil."
            : (keepOK ? "Ink merges and the layer below keeps a combined veil." : "Not available — the Base has no veil.")
        ModalScrim(dismiss: { editor.flatten = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(titleFnt(18)).foregroundStyle(theme.ink1)
                Text(desc).font(fnt(13)).foregroundStyle(theme.ink3).lineSpacing(3)
                option("Keep as trace", keepDesc, enabled: keepOK) { editor.doFlatten(.keep) }
                option("Ink only", "Merge the ink and discard the veil. Full-strength ink on the sheet below.", enabled: true) { editor.doFlatten(.ink) }
                HStack { Spacer(); Button("Cancel") { editor.flatten = nil }.font(fnt(13.5, .semibold)).foregroundStyle(theme.accent).buttonStyle(.plain) }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(width: Metrics.flattenWidth)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid).shadow(color: Shadows.modal.color, radius: Shadows.modal.radius, y: Shadows.modal.y))
            .popIn()
        }
    }

    private func option(_ title: String, _ desc: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(fnt(13.5, .bold)).foregroundStyle(theme.ink1)
                Text(desc).font(fnt(12)).foregroundStyle(theme.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1.5))
            .opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

// MARK: - Organize pages (Markup)

struct OrganizePagesView: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @State private var selected: Int? = nil

    var body: some View {
        let sel = selected ?? editor.pageIndex
        VStack(spacing: 0) {
            HStack {
                Text("Organize Pages").font(titleFnt(21)).foregroundStyle(theme.ink1)
                Spacer()
                PrimaryButton(label: "Done", height: 32) { editor.organizeOpen = false }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
            Text("Tap a page to select it, tap again to open · drag to reorder").font(fnt(12)).foregroundStyle(theme.ink4).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 4)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 160), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(Array(editor.doc.pages.enumerated()), id: \.element.id) { i, pg in
                        VStack(spacing: 8) {
                            PageThumbnail(editor: editor, pageIndex: i, width: 160)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == sel ? theme.accent : .clear, lineWidth: 2).padding(-3))
                                .contentShape(Rectangle())
                                .onTapGesture { if sel == i { editor.setPage(i); editor.organizeOpen = false } else { selected = i } }
                                .draggable(pg.id)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let id = items.first, let from = editor.doc.pageIndex(of: id) else { return false }
                                    editor.movePage(from: from, to: i)
                                    return true
                                }
                            Text(pg.label.isEmpty ? "Page \(i + 1)" : pg.label).font(fnt(12, .semibold)).foregroundStyle(theme.ink3).lineLimit(1)
                            if i == sel {
                                OrganizeActionPill(rotate: { editor.rotatePage(at: i) }, duplicate: { editor.duplicatePage(at: i) }, delete: { editor.deletePage(at: i); selected = nil })
                            }
                        }
                    }
                    Button { editor.addPage() } label: {
                        BlankPageTile(aspect: CGFloat(editor.canvas.w / editor.canvas.h))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
        .background(theme.bg2)
    }
}
