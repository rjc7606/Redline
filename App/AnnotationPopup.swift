import SwiftUI
import RedlineCore

/// Floating card next to the selected annotation: comment text, status, replies, and a Properties editor
/// that changes the annotation itself (colour, fill, thickness…).
struct AnnotationPopup: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @Bindable var editor: WorkspaceModel
    var pageIndex: Int

    private let width: CGFloat = 300
    @FocusState private var commentFocused: Bool

    var body: some View {
        if let cid = editor.selectedComment, let c = editor.doc.comments.first(where: { $0.id == cid }), let b = editor.selectionBounds {
            let z = editor.zoom
            let frame = editor.frameSize(page: pageIndex)
            let fw = frame.width * z, fh = frame.height * z
            let bottom = editor.viewPoint(fromPage: Point(b.center.x, b.maxY), page: pageIndex)
            let top = editor.viewPoint(fromPage: Point(b.center.x, b.minY), page: pageIndex)
            let estHeight: CGFloat = editor.annotationProps ? 520 : 260
            let x = min(max(8, bottom.x - width / 2), max(8, fw - width - 8))
            let below = bottom.y + 14 + estHeight <= fh || top.y - estHeight - 14 < 0
            let y = below ? bottom.y + 14 : max(8, top.y - estHeight - 14)
            let kindTool = Tool(rawValue: c.kind)
            let strokeCount = editor.doc.strokeIDs(for: c.id).count
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: c.color)).frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.12), lineWidth: 1))
                    Image(systemName: commentSymbol(for: c.kind)).font(fnt(13)).foregroundStyle(theme.ink3)
                    Text((kindTool?.label ?? "Mark") + (strokeCount > 1 ? " · \(strokeCount) marks" : "")).font(fnt(13, .bold)).foregroundStyle(theme.ink1).lineLimit(1)
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(CommentStatus.allCases, id: \.self) { s in Button(s.rawValue) { editor.setStatus(c.id, s) } }
                    } label: {
                        let chip = c.status.chip
                        Text(c.status.rawValue).font(fnt(10.5, .bold)).foregroundStyle(Color(hex: chip.fg))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: chip.fg, alpha: chip.alpha)))
                    }
                    Button { editor.closeAnnotationPopup() } label: {
                        Image(systemName: "xmark").font(fnt(11, .bold)).foregroundStyle(theme.ink3).frame(width: 24, height: 24)
                            .background(Circle().fill(theme.hov))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    AvatarView(name: c.author, size: 18)
                    Text(c.author).font(fnt(11.5, .semibold)).foregroundStyle(theme.ink2).lineLimit(1)
                    Text(Formatting.ago(c.time)).font(fnt(10.5)).foregroundStyle(theme.ink4)
                    Spacer()
                }
                TextField("Add a comment…", text: Binding(get: { c.text }, set: { editor.setCommentText(c.id, $0) }), axis: .vertical)
                    .lineLimit(1...5).font(fnt(13)).foregroundStyle(theme.ink1)
                    .focused($commentFocused)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                if !c.replies.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(c.replies) { r in
                                HStack(alignment: .top, spacing: 7) {
                                    AvatarView(name: r.author, size: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(r.author).font(fnt(11, .bold)).foregroundStyle(theme.ink1)
                                            Text(Formatting.ago(r.time)).font(fnt(10)).foregroundStyle(theme.ink4)
                                        }
                                        Text(r.text).font(fnt(12)).foregroundStyle(theme.ink2)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 6)
                        .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 2) }
                    }
                    .frame(maxHeight: 120)
                }
                HStack(spacing: 6) {
                    TextField("Reply…", text: $editor.replyDraft)
                        .font(fnt(12)).foregroundStyle(theme.ink1).padding(.horizontal, 9).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                        .onSubmit { editor.addReply(c.id) }
                    Button { editor.addReply(c.id) } label: {
                        Text("Reply").font(fnt(12, .bold)).foregroundStyle(.white).padding(.horizontal, 10).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Button { editor.annotationProps.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3").font(fnt(13, .semibold))
                            Text("Properties").font(fnt(12.5, .bold))
                            Image(systemName: "chevron.down").font(fnt(10, .bold)).rotationEffect(.degrees(editor.annotationProps ? 180 : 0))
                        }
                        .foregroundStyle(editor.annotationProps ? .white : theme.ink2)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(editor.annotationProps ? theme.accent : theme.bg3))
                    }.buttonStyle(.plain)
                    Spacer()
                    Button { editor.deleteComment(c.id); editor.closeAnnotationPopup() } label: {
                        HStack(spacing: 6) { Image(systemName: "trash").font(fnt(13, .semibold)); Text("Delete").font(fnt(12.5, .bold)) }
                            .foregroundStyle(theme.danger).padding(.horizontal, 12).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg3))
                    }.buttonStyle(.plain)
                }
                if editor.annotationProps, let preset = editor.selectedPreset(), let tool = editor.selectedStrokeTool {
                    Rectangle().fill(theme.line).frame(height: 1)
                    ScrollView(showsIndicators: false) {
                        StylePopoverView(editor: editor, stroke: preset, apply: { body in editor.updateSelectedStyle(body) }, forTool: tool, showPresets: false)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .padding(12)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
                .popShadow(theme))
            .offset(x: x, y: y)
            .popIn()
            .onAppear { if editor.annotationFocusComment { commentFocused = true; editor.annotationFocusComment = false } }
        }
    }
}
