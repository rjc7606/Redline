import SwiftUI
import UIKit
import RedlineCore

// MARK: - Stamp gallery

struct StampGalleryView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        PopoverCard(width: 296) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Stamps — tap, then tap the page")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(ToolCatalog.stampPresets, id: \.text) { s in
                        let on = editor.stampText == s.text && editor.tool == .stamps
                        Text(s.text).font(fnt(12, .heavy)).tracking(1.2).foregroundStyle(Color(hex: s.color))
                            .frame(maxWidth: .infinity).padding(.vertical, 7).padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? theme.hov : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: s.color), lineWidth: 2.5))
                            .rotationEffect(.degrees(-2))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editor.stampText = s.text; editor.stampColor = s.color; editor.tool = .stamps; editor.popover = nil
                                app.flash("Tap the page to place \"\(s.text)\"")
                            }
                    }
                }
                Rectangle().fill(theme.line).frame(height: 1).padding(.top, 2)
                Button { app.flash("Custom stamps — coming soon") } label: {
                    Text("+ Create Custom Stamp…").font(fnt(13, .semibold)).foregroundStyle(theme.accent)
                }.buttonStyle(.plain)
            }
        }
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
                            Text(tab.label.uppercased()).font(fnt(10.5, .heavy)).tracking(0.7).foregroundStyle(Color(hex: "#aeaeb2")).padding(.horizontal, 2)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                                ForEach(tab.tools, id: \.self) { t in
                                    let count = editor.pinCount(t)
                                    HStack(spacing: 8) {
                                        ToolIcon(tool: t, size: 17, color: theme.ink2)
                                        Text(t.label).font(fnt(12, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                                        Spacer(minLength: 0)
                                        if count > 0 {
                                            Text("\(count)").font(fnt(10, .heavy)).foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.24), radius: 20, y: 12))
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
                Text(title).font(fnt(18, .heavy)).foregroundStyle(theme.ink1)
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
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    @State private var insertMenu = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Organize Pages").font(fnt(21, .heavy)).foregroundStyle(theme.ink1)
                Spacer()
                PrimaryButton(label: "Done", height: 32) { editor.organizeOpen = false }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
            Text("Drag to reorder · tap a page to open it").font(fnt(12)).foregroundStyle(theme.ink4).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 4)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 24)], spacing: 24) {
                    ForEach(Array(editor.doc.pages.enumerated()), id: \.element.id) { i, pg in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                PageThumbnail(editor: editor, pageIndex: i, width: 210)
                                    .frame(maxWidth: .infinity)
                                HStack(spacing: 8) {
                                    orgButton("rotate.right", tint: theme.ink2) { editor.rotatePage(at: i) }
                                    orgButton("doc.on.doc", tint: theme.ink2) { editor.duplicatePage(at: i) }
                                    orgButton("trash", tint: theme.danger) { editor.deletePage(at: i) }
                                }
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(theme.popSolid).shadow(color: .black.opacity(0.18), radius: 2, y: 1))
                                .padding(6)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == editor.pageIndex ? theme.accent : .clear, lineWidth: 2.5).padding(-2))
                            .contentShape(Rectangle())
                            .onTapGesture { editor.setPage(i); editor.organizeOpen = false }
                            .draggable(pg.id)
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = items.first, let from = editor.doc.pageIndex(of: id) else { return false }
                                editor.movePage(from: from, to: i)
                                return true
                            }
                            HStack(spacing: 6) {
                                Text("\(i + 1)").font(fnt(11.5, .bold)).foregroundStyle(theme.ink4)
                                Text(pg.label.isEmpty ? "Page \(i + 1)" : pg.label).font(fnt(11.5)).foregroundStyle(theme.ink3).lineLimit(1)
                            }
                        }
                    }
                    Menu {
                        Button("Blank Page") { editor.addPage() }
                        Button("Append PDF…") { app.flash("Append PDF — coming soon") }
                        Button("Extract Pages…") { app.flash("Extract pages — coming soon") }
                    } label: {
                        HStack(spacing: 7) { Image(systemName: "plus").font(fnt(13, .bold)); Text("Insert Page").font(fnt(13, .semibold)) }
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity).aspectRatio(1.414, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
        .background(theme.bg2)
    }

    private func orgButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(fnt(13, .medium)).foregroundStyle(tint).frame(width: 30, height: 26)
        }.buttonStyle(.plain)
    }
}
