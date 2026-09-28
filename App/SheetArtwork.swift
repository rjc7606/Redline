import SwiftUI
import RedlineCore

/// Vector artwork for the sample plan set (ported from the prototype's SVG sheets).
/// Drawn in a 1000×707 page coordinate space.
enum SheetArtwork {
    static func draw(kind: String, in ctx: GraphicsContext, ink: Color) {
        switch kind {
        case "plan": drawPlan(ctx, ink)
        case "elev": drawElevation(ctx, ink)
        case "detail": drawDetail(ctx, ink)
        default: drawBlank(ctx, ink)
        }
    }

    private static func stroke(_ d: String, _ ctx: GraphicsContext, _ ink: Color, width: Double = 1, opacity: Double = 1, dash: [CGFloat] = []) {
        ctx.stroke(SVGPath.parse(d).path(), with: .color(ink.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }

    private static func text(_ s: String, _ x: Double, _ y: Double, _ ctx: GraphicsContext, _ ink: Color, size: Double = 9, weight: Font.Weight = .regular,
                             opacity: Double = 1, anchor: UnitPoint = .bottomLeading, tracking: Double = 0) {
        let t = Text(s).font(.system(size: size, weight: weight)).tracking(tracking).foregroundStyle(ink.opacity(opacity))
        ctx.draw(t, at: CGPoint(x: x, y: y), anchor: anchor)
    }

    private static func titleBlock(_ ctx: GraphicsContext, _ ink: Color, title: String, sheet: String) {
        stroke("M18 18h964v671H18z", ctx, ink, width: 2.5)
        stroke("M24 24h952v659H24z", ctx, ink, width: 1, opacity: 0.55)
        stroke("M852 24v659", ctx, ink, width: 1.5)
        text("REDLINE", 864, 52, ctx, ink, size: 13, weight: .bold, tracking: 1)
        text("GENERAL CONTRACTORS", 864, 68, ctx, ink, size: 9, opacity: 0.7)
        text("PROJECT", 864, 120, ctx, ink, size: 9, opacity: 0.7)
        text("MERIDIAN TOWER", 864, 136, ctx, ink, size: 11, weight: .semibold)
        text("LEVEL 2 — CORE & SHELL", 864, 150, ctx, ink, size: 10)
        text("SHEET TITLE", 864, 200, ctx, ink, size: 9, opacity: 0.7)
        text(title, 864, 216, ctx, ink, size: 11, weight: .semibold)
        text("SCALE", 864, 266, ctx, ink, size: 9, opacity: 0.7); text("1/8\" = 1'-0\"", 920, 266, ctx, ink, size: 9)
        text("DATE", 864, 282, ctx, ink, size: 9, opacity: 0.7); text("08.14.26", 920, 282, ctx, ink, size: 9)
        text("DRAWN", 864, 298, ctx, ink, size: 9, opacity: 0.7); text("T.M.", 920, 298, ctx, ink, size: 9)
        text("REV", 864, 314, ctx, ink, size: 9, opacity: 0.7); text("C", 920, 314, ctx, ink, size: 9)
        text("SHEET NO.", 864, 640, ctx, ink, size: 9, opacity: 0.7)
        text(sheet, 864, 672, ctx, ink, size: 26, weight: .bold)
        stroke("M852 84h130M852 100h130M852 176h130M852 242h130M852 322h130M852 620h130", ctx, ink, width: 1, opacity: 0.55)
    }

    private static func drawBlank(_ ctx: GraphicsContext, _ ink: Color) {
        stroke("M18 18h964v671H18z", ctx, ink, width: 2.5, opacity: 0.35)
        let t = Text("Blank page — tap a tool to mark up").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink.opacity(0.35))
        ctx.draw(t, at: CGPoint(x: 500, y: 353), anchor: .center)
    }

    private static func drawPlan(_ ctx: GraphicsContext, _ ink: Color) {
        titleBlock(ctx, ink, title: "FLOOR PLAN — LEVEL 2", sheet: "A-101")
        // column grid bubbles
        for (x, l) in [(120.0, "A"), (400.0, "B"), (640.0, "C"), (810.0, "D")] {
            ctx.stroke(Path(ellipseIn: CGRect(x: x - 13, y: 39, width: 26, height: 26)), with: .color(ink.opacity(0.85)), lineWidth: 1.2)
            text(l, x, 52, ctx, ink, size: 11, weight: .semibold, anchor: .center)
        }
        stroke("M120 65v560M400 65v560M640 65v560M810 65v560", ctx, ink, width: 0.8, opacity: 0.45, dash: [14, 5, 3, 5])
        // walls
        stroke("M120 130h690v470H120z", ctx, ink, width: 3)
        stroke("M128 138h674v454H128z", ctx, ink, width: 1.2)
        stroke("M400 138v150M400 330v90", ctx, ink, width: 2)
        stroke("M128 420h180M350 420h160M560 420v172", ctx, ink, width: 2)
        stroke("M640 138v120", ctx, ink, width: 2)
        // door swings
        stroke("M400 288a42 42 0 0 1 42 42", ctx, ink, width: 1, opacity: 0.8)
        stroke("M400 288l42 42", ctx, ink, width: 1, opacity: 0.8, dash: [2, 3])
        stroke("M308 420a42 42 0 0 1 42-42", ctx, ink, width: 1, opacity: 0.8)
        stroke("M700 592v-60a30 30 0 0 0-30-30", ctx, ink, width: 1, opacity: 0.8)
        // stair
        stroke("M660 150h120v90H660z", ctx, ink, width: 1.1)
        stroke("M675 150v90M690 150v90M705 150v90M720 150v90M735 150v90M750 150v90M765 150v90", ctx, ink, width: 1.1)
        stroke("M660 195h120", ctx, ink, width: 1.1, dash: [3, 3])
        // furniture
        stroke("M150 450h120v60H150zM290 450h120v60H290zM150 525h120v60H150zM290 525h120v60H290z", ctx, ink, width: 1.1, opacity: 0.9)
        stroke("M600 460h90v46h-90zM600 483h90M720 460h60v120h-60zM720 520h60", ctx, ink, width: 1.1, opacity: 0.9)
        // labels
        text("OFFICE 201", 230, 270, ctx, ink, size: 11, weight: .semibold, anchor: .bottom, tracking: 0.5)
        text("CONF 202", 520, 270, ctx, ink, size: 11, weight: .semibold, anchor: .bottom, tracking: 0.5)
        text("OPEN WORK 203", 280, 620, ctx, ink, size: 10, opacity: 0.7, anchor: .bottom, tracking: 0.5)
        text("MECH 204", 645, 540, ctx, ink, size: 11, weight: .semibold, anchor: .bottom, tracking: 0.5)
        text("STAIR 2", 720, 175, ctx, ink, size: 9, opacity: 0.8, anchor: .bottom)
        text("1,240 SF", 280, 240, ctx, ink, size: 9, opacity: 0.65, anchor: .bottom)
        // dimensions
        stroke("M120 95h280M400 95h240M640 95h170M120 90v10M400 90v10M640 90v10M810 90v10M95 130v470M90 130h10M90 600h10", ctx, ink, width: 0.8, opacity: 0.65)
        text("28'-0\"", 260, 88, ctx, ink, size: 9, opacity: 0.75, anchor: .bottom)
        text("24'-0\"", 520, 88, ctx, ink, size: 9, opacity: 0.75, anchor: .bottom)
        text("17'-0\"", 725, 88, ctx, ink, size: 9, opacity: 0.75, anchor: .bottom)
        ctx.drawLayer { l in
            l.translateBy(x: 88, y: 365); l.rotate(by: .degrees(-90))
            let t = Text("47'-0\"").font(.system(size: 9)).foregroundStyle(ink.opacity(0.75))
            l.draw(t, at: .zero, anchor: .center)
        }
        // north arrow
        ctx.stroke(Path(ellipseIn: CGRect(x: 783, y: 628, width: 34, height: 34)), with: .color(ink.opacity(0.8)), lineWidth: 1.2)
        stroke("M800 658v-26l6 8", ctx, ink, width: 1.2, opacity: 0.8)
        text("N", 800, 637, ctx, ink, size: 8, anchor: .bottom)
        text("GENERAL NOTE: ALL PARTITIONS TYPE P-1 U.N.O. — SEE A-601 FOR ASSEMBLIES.", 130, 655, ctx, ink, size: 10, opacity: 0.8)
        text("COORDINATE MECH OPENINGS WITH M-201 PRIOR TO FRAMING.", 130, 670, ctx, ink, size: 10, opacity: 0.8)
    }

    private static func drawElevation(_ ctx: GraphicsContext, _ ink: Color) {
        titleBlock(ctx, ink, title: "EXTERIOR ELEVATIONS", sheet: "A-201")
        stroke("M70 300h700", ctx, ink, width: 2.5)
        stroke("M120 120h560v180H120z", ctx, ink, width: 1.6)
        stroke("M120 120l30-28h560l-30 28M680 120l30-28v180l-30 28", ctx, ink, width: 1.2)
        stroke("M120 180h560M120 240h560", ctx, ink, width: 1)
        var windows = Path()
        for row in [135.0, 195.0] { for i in 0..<9 { windows.addRect(CGRect(x: 150 + Double(i) * 60, y: row, width: 34, height: 30)) } }
        windows.addRect(CGRect(x: 150, y: 255, width: 34, height: 45)); windows.addRect(CGRect(x: 370, y: 252, width: 60, height: 48)); windows.addRect(CGRect(x: 630, y: 255, width: 34, height: 45))
        ctx.stroke(windows, with: .color(ink), lineWidth: 1)
        var hatch = Path()
        var x = 70.0
        while x <= 742 { hatch.move(to: CGPoint(x: x, y: 305)); hatch.addLine(to: CGPoint(x: x + 14, y: 297)); x += 28 }
        ctx.stroke(hatch, with: .color(ink.opacity(0.6)), lineWidth: 0.8)
        text("NORTH ELEVATION", 120, 340, ctx, ink, size: 12, weight: .bold, tracking: 1)
        text("SCALE: 1/8\" = 1'-0\"", 255, 340, ctx, ink, size: 9, opacity: 0.7)
        stroke("M70 620h700", ctx, ink, width: 2.5)
        stroke("M120 440h560v180H120z", ctx, ink, width: 1.6)
        stroke("M120 500h560M120 560h560", ctx, ink, width: 1)
        var w2 = Path()
        for row in [455.0, 515.0] { for i in 0..<4 { w2.addRect(CGRect(x: 160 + Double(i) * 140, y: row, width: 80, height: 30)) } }
        w2.addRect(CGRect(x: 360, y: 572, width: 80, height: 48))
        ctx.stroke(w2, with: .color(ink), lineWidth: 1)
        text("EAST ELEVATION", 120, 655, ctx, ink, size: 12, weight: .bold, tracking: 1)
        text("SCALE: 1/8\" = 1'-0\"", 240, 655, ctx, ink, size: 9, opacity: 0.7)
        stroke("M760 120h30M760 180h30M760 240h30M760 300h30M775 120v180", ctx, ink, width: 0.8, opacity: 0.65)
        for (y, l) in [(124.0, "T.O. PARAPET"), (184.0, "LEVEL 3"), (244.0, "LEVEL 2"), (304.0, "LEVEL 1")] { text(l, 795, y, ctx, ink, size: 8.5, opacity: 0.75) }
    }

    private static func drawDetail(_ ctx: GraphicsContext, _ ink: Color) {
        titleBlock(ctx, ink, title: "TYP. WALL DETAILS", sheet: "S-301")
        // wall section layers
        let brick = CGRect(x: 330, y: 90, width: 26, height: 480)
        ctx.drawLayer { l in
            l.clip(to: Path(brick))
            var p = Path(); var d = 300.0
            while d < 900 { p.move(to: CGPoint(x: d, y: 570)); p.addLine(to: CGPoint(x: d + 480, y: 90)); d += 7 }
            l.stroke(p, with: .color(ink.opacity(0.45)), lineWidth: 1)
        }
        ctx.stroke(Path(brick), with: .color(ink), lineWidth: 1.4)
        ctx.stroke(Path(CGRect(x: 356, y: 90, width: 10, height: 480)), with: .color(ink), lineWidth: 1.2)
        let stud = CGRect(x: 366, y: 90, width: 44, height: 480)
        ctx.drawLayer { l in
            l.clip(to: Path(stud))
            var p = Path(); var d = -200.0
            while d < 700 { p.move(to: CGPoint(x: d, y: 90)); p.addLine(to: CGPoint(x: d + 480, y: 570)); d += 10 }
            l.stroke(p, with: .color(ink.opacity(0.3)), lineWidth: 0.8)
        }
        ctx.stroke(Path(stud), with: .color(ink), lineWidth: 1.4)
        ctx.stroke(Path(CGRect(x: 410, y: 90, width: 6, height: 480)), with: .color(ink), lineWidth: 1.2)
        ctx.stroke(Path(CGRect(x: 416, y: 90, width: 8, height: 480)), with: .color(ink), lineWidth: 1.2)
        stroke("M300 90h150M300 570h150", ctx, ink, width: 2)
        stroke("M260 570h230v40H260z", ctx, ink, width: 1.6)
        var hatch = Path()
        var x = 260.0
        while x <= 470 { hatch.move(to: CGPoint(x: x, y: 610)); hatch.addLine(to: CGPoint(x: x + 14, y: 601)); x += 23 }
        ctx.stroke(hatch, with: .color(ink.opacity(0.6)), lineWidth: 0.8)
        stroke("M343 140h-90M253 140h-8M361 190h-108M388 240h-135M413 290h-160M420 340h-167M424 160l90-30h8", ctx, ink, width: 0.9, opacity: 0.9)
        for (y, l) in [(137.0, "BRICK VENEER"), (187.0, "1\" AIR GAP"), (237.0, "6\" MTL. STUD @ 16\" O.C."), (287.0, "EXT. SHEATHING, TYP."), (337.0, "5/8\" GYP. BD., PTD.")] {
            text(l, 130, y, ctx, ink, size: 10, opacity: 0.9)
        }
        text("R-19 BATT INSUL.", 522, 127, ctx, ink, size: 10, opacity: 0.9)
        text("CONC. FTG. — SEE S-101", 255, 640, ctx, ink, size: 10, opacity: 0.9)
        ctx.stroke(Path(ellipseIn: CGRect(x: 586, y: 386, width: 68, height: 68)), with: .color(ink), lineWidth: 1.4)
        stroke("M586 420h68", ctx, ink, width: 1)
        text("3", 620, 414, ctx, ink, size: 13, weight: .bold, anchor: .bottom)
        text("S-301", 620, 440, ctx, ink, size: 10, anchor: .bottom)
        stroke("M620 386V300a40 40 0 0 0-40-40H460", ctx, ink, width: 0.9, opacity: 0.7)
        text("TYP. EXTERIOR WALL SECTION", 260, 675, ctx, ink, size: 12, weight: .bold, tracking: 1)
        text("SCALE: 3/4\" = 1'-0\"", 470, 675, ctx, ink, size: 9, opacity: 0.7)
    }
}
