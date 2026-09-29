import SwiftUI
import RedlineCore

struct SidebarView: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            SegmentControl(options: editor.sideTabs.map { SegmentOption(value: $0, label: $0.label) },
                           selection: Binding(get: { editor.sideTab }, set: { editor.sideTab = $0 }),
                           fontSize: 10.5, vPad: 4, hPad: 4, radius: 8, fill: true)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            switch editor.sideTab {
            case .comments: CommentsPanel(editor: editor)
            case .bookmarks: BookmarksPanel(editor: editor)
            case .outline: OutlinePanel(editor: editor)
            case .forms: FormsPanel(editor: editor)
            case .pages: PagesPanel(editor: editor)
            case .layers: LayersPanel(editor: editor)
            case .tags: TagsPanel(editor: editor)
            }
        }
        .frame(width: editor.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
    }
}

// MARK: - Comments

struct CommentsPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(AuthorFilter.allCases, id: \.self) { f in
                    let on = editor.authorFilter == f
                    Text(f.rawValue).font(fnt(11, .bold))
                        .foregroundStyle(on ? theme.bg : theme.ink2)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(on ? theme.ink1 : theme.hov))
                        .onTapGesture { editor.authorFilter = f }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 6) {
                    let items = editor.visibleComments
                    ForEach(items) { item in
                        CommentCard(editor: editor, comment: item.comment, pageIndex: item.pageIndex, strokeCount: item.strokeCount)
                    }
                    if items.isEmpty {
                        Text("No comments yet. Every mark you make becomes a comment with your name and time.")
                            .font(fnt(12)).foregroundStyle(theme.ink4).multilineTextAlignment(.center).lineSpacing(3)
                            .padding(.vertical, 22).padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
    }
}

struct CommentCard: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @Bindable var editor: WorkspaceModel
    var comment: Comment
    var pageIndex: Int
    var strokeCount: Int

    var body: some View {
        let open = editor.selectedComment == comment.id
        let kindTool = Tool(rawValue: comment.kind)
        let isInk = kindTool?.isPen ?? false
        let label = (kindTool?.label ?? "Mark") + (isInk ? " · " + Formatting.plural(strokeCount, "stroke") : "")
        let chip = comment.status.chip
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: comment.color)).frame(width: 10, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.12), lineWidth: 1))
                Image(systemName: commentSymbol(for: comment.kind)).font(fnt(12)).foregroundStyle(theme.ink3)
                Text(label).font(fnt(12.5, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                Spacer(minLength: 2)
                Text("p.\(pageIndex + 1)").font(fnt(10.5)).foregroundStyle(theme.ink4)
                Button { editor.deleteComment(comment.id) } label: {
                    Image(systemName: "xmark").font(fnt(10, .bold)).foregroundStyle(theme.ink4).frame(width: 18, height: 18)
                }.buttonStyle(.plain).opacity(0.5)
            }
            HStack(spacing: 6) {
                AvatarView(name: comment.author, size: 20)
                Text(comment.author).font(fnt(11.5, .semibold)).foregroundStyle(theme.ink2).lineLimit(1)
                Text(Formatting.ago(comment.time)).font(fnt(10.5)).foregroundStyle(theme.ink4)
                Spacer(minLength: 2)
                Menu {
                    ForEach(CommentStatus.allCases, id: \.self) { s in Button(s.rawValue) { editor.setStatus(comment.id, s) } }
                } label: {
                    Text(comment.status.rawValue).font(fnt(10.5, .bold)).foregroundStyle(Color(hex: chip.fg))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: chip.fg, alpha: chip.alpha)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.line, lineWidth: 1))
                }
            }
            if open {
                TextField("Add comment text…", text: Binding(get: { comment.text }, set: { editor.setCommentText(comment.id, $0) }), axis: .vertical)
                    .lineLimit(2...6).font(fnt(12.5)).foregroundStyle(theme.ink1)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                ForEach(comment.replies) { r in
                    HStack(alignment: .top, spacing: 7) {
                        AvatarView(name: r.author, size: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(r.author).font(fnt(11, .bold)).foregroundStyle(theme.ink1)
                                Text(Formatting.ago(r.time)).font(fnt(10)).foregroundStyle(theme.ink4)
                            }
                            Text(r.text).font(fnt(12)).foregroundStyle(theme.ink2).lineSpacing(2)
                        }
                    }
                    .padding(.leading, 6)
                    .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 2) }
                }
                HStack(spacing: 6) {
                    TextField("Reply…", text: $editor.replyDraft)
                        .font(fnt(12)).foregroundStyle(theme.ink1).padding(.horizontal, 9).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                        .onSubmit { editor.addReply(comment.id) }
                    Button { editor.addReply(comment.id) } label: {
                        Text("Reply").font(fnt(12, .bold)).foregroundStyle(.white).padding(.horizontal, 10).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent))
                    }.buttonStyle(.plain)
                }
            } else {
                if !comment.text.isEmpty { Text(comment.text).font(fnt(12)).foregroundStyle(theme.ink2).lineLimit(2).lineSpacing(2) }
                if !comment.replies.isEmpty { Text(Formatting.plural(comment.replies.count, "reply", "replies")).font(fnt(11, .semibold)).foregroundStyle(theme.accent) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(open ? theme.accent : (editor.session == comment.id ? theme.accent.opacity(0.4) : theme.line), lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { editor.selectComment(comment.id) }
    }
}

// MARK: - Forms

struct FormsPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Add field")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                        ForEach(FieldType.panelTypes, id: \.self) { ft in
                            let t = ToolCatalog.tool(for: ft)
                            let on = editor.tool == t
                            HStack(spacing: 7) {
                                Image(systemName: ft.symbol).font(fnt(14, .medium))
                                Text(ft.label).font(fnt(12, .semibold)).lineLimit(1)
                            }
                            .foregroundStyle(on ? .white : theme.ink2)
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(on ? theme.accent : theme.card))
                            .contentShape(Rectangle())
                            .onTapGesture { editor.pick(t) }
                        }
                    }
                    Text("Pick a type, then tap the page to place it. Use Select to fill or edit a field.")
                        .font(fnt(11)).foregroundStyle(theme.ink4).lineSpacing(2)
                }
                if let fid = editor.selectedField, let f = editor.page.fields.first(where: { $0.id == fid }) {
                    FieldEditor(editor: editor, field: f)
                }
                if !editor.page.fields.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Fields on this page · tab order")
                        ForEach(editor.page.fields.sorted { $0.tab < $1.tab }) { f in
                            HStack(spacing: 8) {
                                Text("\(f.tab)").font(fnt(10, .heavy)).foregroundStyle(theme.ink4).frame(width: 14)
                                Image(systemName: f.type.symbol).font(fnt(12)).foregroundStyle(theme.ink3)
                                Text(f.name).font(fnt(12, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                                Spacer()
                                if f.required { Text("*").font(fnt(12, .heavy)).foregroundStyle(theme.danger) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(editor.selectedField == f.id ? theme.accentSoft : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { editor.selectedField = f.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 12)
        }
    }
}

struct FieldEditor: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var field: FormField

    private func bind(_ get: @escaping (FormField) -> String, _ set: @escaping (inout FormField, String) -> Void) -> Binding<String> {
        Binding(get: { get(field) }, set: { v in editor.editField(field.id) { set(&$0, v) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(field.type.label + " field").font(fnt(12, .heavy)).foregroundStyle(theme.ink1)
                Spacer()
                Button("Delete") { editor.deleteField(field.id) }.font(fnt(11, .bold)).foregroundStyle(theme.danger).buttonStyle(.plain)
            }
            labelled("Name") { FieldText(placeholder: "name", text: bind({ $0.name }, { $0.name = $1.replacingOccurrences(of: " ", with: "_") }), height: 30, font: fnt(12.5)) }
            if !field.type.isToggleLike && field.type != .sig {
                labelled("Value") {
                    if field.type.hasOptions {
                        Picker("Value", selection: bind({ $0.value }, { $0.value = $1 })) {
                            Text("—").tag("")
                            ForEach(field.optionList, id: \.self) { o in Text(o).tag(o) }
                        }.pickerStyle(.menu).font(fnt(12.5))
                    } else {
                        FieldText(placeholder: field.name, text: bind({ $0.value }, { $0.value = $1 }), height: 30, font: fnt(12.5))
                    }
                }
            }
            labelled("Default value") { FieldText(placeholder: "", text: bind({ $0.defaultValue }, { $0.defaultValue = $1 }), height: 30, font: fnt(12.5)) }
            if field.type.hasOptions {
                labelled("Options (one per line)") {
                    TextField("", text: bind({ $0.options }, { $0.options = $1 }), axis: .vertical).lineLimit(3...6).font(fnt(12.5))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.bg)).overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.line, lineWidth: 1))
                }
            }
            HStack(spacing: 8) {
                labelled("Tab order") {
                    FieldText(placeholder: "1", text: Binding(get: { String(field.tab) }, set: { v in editor.editField(field.id) { $0.tab = Int(v) ?? 1 } }), height: 30, font: fnt(12.5))
                        .keyboardType(.numberPad)
                }
                labelled("Validation") {
                    Picker("Validation", selection: Binding(get: { field.validation }, set: { v in editor.editField(field.id) { $0.validation = v } })) {
                        ForEach(ValidationRule.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).font(fnt(12.5))
                }
            }
            labelled("Calculation") { FieldText(placeholder: "e.g. qty * unit_price", text: bind({ $0.calculation }, { $0.calculation = $1 }), height: 30, mono: true) }
            Toggle(isOn: Binding(get: { field.required }, set: { v in editor.editField(field.id, undoable: true) { $0.required = v } })) {
                Text("Required").font(fnt(12.5, .semibold)).foregroundStyle(theme.ink1)
            }.tint(theme.accent)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(fnt(10.5, .bold)).foregroundStyle(theme.ink4)
            c()
        }
    }
}

// MARK: - Pages

struct PagesPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(editor.doc.pages.enumerated()), id: \.element.id) { i, pg in
                    let on = i == editor.pageIndex
                    HStack(spacing: 10) {
                        PageThumbnail(editor: editor, pageIndex: i, width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.type == .journal ? BookGeometry.longLabel(for: i) : (pg.label.isEmpty ? "Page \(i + 1)" : pg.label))
                                .font(fnt(12.5, .bold)).foregroundStyle(theme.ink1).lineLimit(1)
                            Text(meta(pg, i)).font(fnt(10.5)).foregroundStyle(theme.ink4).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button { editor.deletePage(at: i) } label: {
                            Image(systemName: "xmark").font(fnt(10, .bold)).foregroundStyle(theme.ink4).frame(width: 20, height: 20)
                        }.buttonStyle(.plain).opacity(0.4)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(on ? theme.accentSoft : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { editor.setPage(i); if editor.type == .journal { editor.journalView = .book } }
                }
                Button { editor.addPage() } label: {
                    HStack(spacing: 6) { Image(systemName: "plus").font(fnt(13, .bold)); Text("Add page").font(fnt(12.5, .bold)) }
                        .foregroundStyle(theme.accent).frame(maxWidth: .infinity).padding(9)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 12)
        }
    }

    private func meta(_ pg: Page, _ i: Int) -> String {
        switch editor.type {
        case .markup: return Formatting.plural(editor.doc.comments.filter { $0.pageID == pg.id }.count, "comment") + " · " + Formatting.plural(pg.fields.count, "field")
        case .drawing: return Formatting.plural(max(0, pg.layers.count - 1), "layer")
        case .journal: return (pg.tags.isEmpty ? "no tags" : pg.tags.joined(separator: ", ")) + " · " + Formatting.date(pg.created)
        }
    }
}

/// Small non-interactive page preview.
struct PageThumbnail: View {
    var editor: WorkspaceModel
    var pageIndex: Int
    var width: Double
    var body: some View {
        let f = editor.frameSize(page: pageIndex)
        let z = width / f.width
        let input = editor.renderInput(page: pageIndex, zoom: z, interactive: false)
        PageCanvas(input: input, size: CGSize(width: f.width * z, height: f.height * z))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
    }
}

// MARK: - Layers

struct LayersPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Button { editor.addLayer() } label: {
                    HStack(spacing: 6) { Image(systemName: "plus").font(fnt(13, .bold)); Text("Add layer").font(fnt(12.5, .bold)) }
                        .foregroundStyle(theme.accent).frame(maxWidth: .infinity).padding(9)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }.buttonStyle(.plain)
                ForEach(editor.page.layers.reversed()) { L in
                    LayerRow(editor: editor, layer: L)
                }
                if editor.page.layers.count > 2 {
                    Button { editor.flatten = FlattenRequest(layerID: nil) } label: {
                        HStack(spacing: 6) { Image(systemName: "square.stack.3d.down.right").font(fnt(13, .semibold)); Text("Flatten all").font(fnt(12.5, .bold)) }
                            .foregroundStyle(theme.ink2).frame(maxWidth: .infinity).padding(9)
                            .background(RoundedRectangle(cornerRadius: 9).fill(theme.bg3))
                    }.buttonStyle(.plain).padding(.top, 4)
                }
                Text("Layers veil everything beneath them. Ink on each layer stays full strength; hidden layers lift their veil.")
                    .font(fnt(11)).foregroundStyle(theme.ink4).lineSpacing(3).padding(.vertical, 6).padding(.horizontal, 2)
            }
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 12)
        }
    }
}

struct LayerRow: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var layer: Layer

    var body: some View {
        let active = (editor.activeLayerObject?.id) == layer.id
        let menuOpen = editor.layerMenu == layer.id
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                LayerThumbnail(layer: layer, canvas: editor.canvas)
                    .frame(width: 64, height: 45)
                    .background(RoundedRectangle(cornerRadius: 5).fill(layer.kind == .base ? Color.white : Color.white.opacity(0.3 + layer.opacity * 0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(layer.name).font(fnt(12.5, .bold)).foregroundStyle(theme.ink1).lineLimit(1)
                Spacer(minLength: 0)
                Button { editor.editLayer(layer.id) { $0.visible.toggle() } } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash").font(fnt(14, .medium)).foregroundStyle(layer.visible ? theme.ink2 : theme.ink4).frame(width: 26, height: 26)
                }.buttonStyle(.plain)
                Button { editor.layerMenu = menuOpen ? nil : layer.id; editor.activeLayer = layer.id } label: {
                    Image(systemName: "ellipsis").font(fnt(14, .medium)).foregroundStyle(theme.ink3).frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(menuOpen ? theme.hov : .clear))
                }.buttonStyle(.plain)
            }
            if menuOpen {
                VStack(spacing: 6) {
                    if layer.isTrace {
                        HStack(spacing: 8) {
                            Text("Veil").font(fnt(10.5, .bold)).foregroundStyle(theme.ink4).frame(width: 28, alignment: .leading)
                            Slider(value: Binding(get: { layer.opacity }, set: { v in editor.editLayer(layer.id, undoable: false) { $0.opacity = v } }), in: 0...1).tint(theme.accent)
                            Text("\(Int((layer.opacity * 100).rounded()))%").font(fnt(11, .bold)).foregroundStyle(theme.ink1).frame(width: 32, alignment: .trailing)
                        }.padding(.leading, 2)
                    }
                    menuItem("Rename", "pencil") { editor.renameLayerID = layer.id; editor.renameDraft = layer.name; editor.layerRenameVisible = true; editor.layerMenu = nil }
                    menuItem(layer.locked ? "Unlock layer" : "Lock layer", layer.locked ? "lock.fill" : "lock.open", tint: layer.locked ? theme.accent : theme.dis) { editor.editLayer(layer.id) { $0.locked.toggle() } }
                    if layer.isTrace {
                        menuItem("Flatten down", "arrow.down.to.line") { editor.flatten = FlattenRequest(layerID: layer.id); editor.layerMenu = nil }
                    }
                }
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(active ? theme.accent : theme.line, lineWidth: 1.5))
        .opacity(layer.visible ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { editor.activeLayer = layer.id }
    }

    private func menuItem(_ label: String, _ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(fnt(13, .medium)).foregroundStyle(tint ?? theme.ink2)
                Text(label).font(fnt(12, .semibold)).foregroundStyle(theme.ink2)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Renders the last 80 strokes of a layer at thumbnail size (minimum stroke width 6).
struct LayerThumbnail: View {
    var layer: Layer
    var canvas: Size
    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            let k = min(size.width / canvas.w, size.height / canvas.h)
            c.translateBy(x: (size.width - canvas.w * k) / 2, y: (size.height - canvas.h * k) / 2)
            c.scaleBy(x: k, y: k)
            for s in layer.strokes.suffix(80) {
                guard let r = StrokeGeometry.render(s) else { continue }
                let p = r.path.path()
                if let f = r.fillColor { c.fill(p, with: .color(Color(hex: f, alpha: r.fillOpacity))) }
                if let sc = r.strokeColor { c.stroke(p, with: .color(Color(hex: sc, alpha: r.strokeOpacity)), style: StrokeStyle(lineWidth: max(r.strokeWidth, 6), lineCap: .round, lineJoin: .round)) }
            }
        }
    }
}

// MARK: - Tags (Notes)

struct TagsPanel: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel

    var body: some View {
        let q = editor.tagQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let all = editor.doc.tagCounts()
        let pages = editor.doc.pages.enumerated().filter { _, pg in
            (editor.tagFilter == nil || pg.tags.contains(editor.tagFilter!)) && (q.isEmpty || pg.tags.contains { $0.contains(q) })
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                FieldText(placeholder: "Search tags or pages", text: $editor.tagQuery, height: 32, font: fnt(12.5))
                FlowChips(items: all.filter { q.isEmpty || $0.name.contains(q) }.map { ($0.name, $0.count) }, selected: editor.tagFilter) { name in
                    editor.tagFilter = editor.tagFilter == name ? nil : name
                }
                SectionLabel(text: editor.tagFilter.map { "\(pages.count) pages tagged \"\($0)\"" } ?? (q.isEmpty ? "Tap a tag to filter" : "\(pages.count) matching pages"))
                if editor.tagFilter != nil || !q.isEmpty {
                    ForEach(pages, id: \.element.id) { i, pg in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: pg.paper.hex)).frame(width: 36, height: 48)
                                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(BookGeometry.longLabel(for: i)).font(fnt(12.5, .bold)).foregroundStyle(theme.ink1)
                                Text(pg.tags.isEmpty ? "no tags" : pg.tags.joined(separator: ", ")).font(fnt(10.5)).foregroundStyle(theme.ink4).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(i == editor.pageIndex ? theme.accentSoft : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { editor.setPage(i); editor.journalView = .book }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 12)
        }
    }
}

/// Wrapping row of tag chips with counts.
struct FlowChips: View {
    @Environment(\.theme) private var theme
    var items: [(String, Int)]
    var selected: String?
    var onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(items, id: \.0) { name, count in
                let on = selected == name
                HStack(spacing: 5) {
                    Text(name).font(fnt(11.5, .bold))
                    Text("\(count)").font(fnt(11.5, .bold)).opacity(0.6)
                }
                .foregroundStyle(on ? .white : theme.ink2)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(on ? theme.accent : theme.card))
                .onTapGesture { onTap(name) }
            }
        }
    }
}

/// Minimal wrapping layout.
struct FlowLayout: Layout {
    var spacing: Double = 5
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x = 0.0, y = 0.0, rowH = 0.0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH = 0.0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
