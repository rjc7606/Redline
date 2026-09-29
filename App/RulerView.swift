import SwiftUI
import RedlineCore

/// On-page ruler (display only — WorkspaceModel handles the finger gestures): drag to move, drag the end
/// handles to rotate (snaps every 15°), tap the centre pill to lock. Pens draw along its edge when a stroke
/// starts next to it; with Lock on every stroke is parallel or perpendicular to it. Page coordinates.
struct RulerView: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var pageIndex: Int

    var body: some View {
        let r = editor.ruler
        let z = editor.zoom
        let L = WorkspaceModel.rulerLength * z
        let H = WorkspaceModel.rulerHeight * z
        let center = editor.viewPoint(fromPage: Point(r.x, r.y), page: pageIndex)
        let pageRot = Double(editor.doc.pages[min(pageIndex, editor.pageCount - 1)].rotation)
        let space = "page-\(pageIndex)"
        let deg = Int((r.angle > 90 ? 180 - r.angle : r.angle).rounded())
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.pop)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(theme.line2, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 11, y: 6)
            Canvas { ctx, size in
                var p = Path()
                let n = Int(WorkspaceModel.rulerLength / 10)
                for i in 0...n {
                    let x = (10 + Double(i) * 10) * z + 0.5
                    let len = (i % 10 == 0 ? 14 : (i % 5 == 0 ? 10 : 6)) * z
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: len))
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x, y: size.height - len))
                }
                ctx.stroke(p, with: .color(Color(hex: theme.tokens.ink2)), lineWidth: 1)
                for i in 1...7 {
                    let t = Text("\(i)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: theme.tokens.ink3))
                    ctx.draw(t, at: CGPoint(x: (10 + Double(i) * 100) * z, y: 19 * z + 4), anchor: .center)
                }
            }
            .allowsHitTesting(false)
            HStack {
                rotateHandle(space: space)
                Spacer()
                rotateHandle(space: space)
            }
            .padding(.horizontal, 8)
            HStack(spacing: 8) {
                Text("\(deg)°").font(fnt(15, .bold)).monospacedDigit().foregroundStyle(theme.ink1).frame(minWidth: 40, alignment: .trailing)
                HStack(spacing: 6) {
                    Image(systemName: r.lock ? "lock.fill" : "lock.open").font(fnt(12, .bold))
                    Text(r.lock ? "Locked" : "Lock").font(fnt(12, .bold))
                }
                .foregroundStyle(r.lock ? .white : theme.ink2)
                .padding(.horizontal, 11).frame(height: 28)
                .background(Capsule().fill(r.lock ? theme.accent : theme.card))
                .overlay(Capsule().stroke(r.lock ? theme.accent : theme.line2, lineWidth: 1))
            }
            .rotationEffect(.degrees(r.angle > 90 ? 180 : 0))
        }
        .frame(width: L, height: H)
        .rotationEffect(.degrees(r.angle + pageRot))
        .position(center)
        .accessibilityLabel("Ruler")
    }

    private func rotateHandle(space: String) -> some View {
        Image(systemName: "arrow.clockwise")
            .font(fnt(13, .semibold)).foregroundStyle(theme.ink2)
            .frame(width: 28, height: 28)
            .background(Circle().fill(theme.card))
            .overlay(Circle().stroke(theme.line2, lineWidth: 1))
            .frame(width: 44, height: 44)
    }
}
