// Sample content shown on first launch (mirrors the prototype's seed).

import Foundation

public enum Seed {
    public static func data(now: Date = Date()) -> RedlineData {
        let day = 86400.0, hour = 3600.0
        let me = "Tessa Mahler"

        func S(_ tool: Tool, _ color: String, _ pts: [StrokePoint], width: Double? = nil, comment: ID? = nil, text: String? = nil) -> Stroke {
            Stroke(tool: tool, color: color, points: pts, width: width, text: text, commentID: comment)
        }
        func circle(_ cx: Double, _ cy: Double, _ r: Double) -> [StrokePoint] {
            (0...40).map { i in
                let a = Double(i) / 40 * .pi * 2
                return StrokePoint(cx + cos(a) * r * 1.02, cy + sin(a) * r * 0.98, 0.5)
            }
        }
        func ln(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> [StrokePoint] { [StrokePoint(a, b), StrokePoint(c, d)] }
        func wave(_ x: Double, _ y: Double, _ n: Int) -> [StrokePoint] {
            (0...n).map { i in StrokePoint(x + Double(i) * 6, y + sin(Double(i) * 0.9) * 5, 0.5) }
        }

        // Markup: Meridian Tower L2 drawings
        let c1 = IDGen.make(), c2 = IDGen.make(), c3 = IDGen.make(), c4 = IDGen.make()
        var p1 = Page.markup(label: "A-101 Floor Plan", artwork: "plan", created: now - 9 * day)
        var p2 = Page.markup(label: "A-201 Elevations", artwork: "elev", created: now - 9 * day)
        let p3 = Page.markup(label: "S-301 Wall Details", artwork: "detail", created: now - 9 * day)
        p1.strokes = [
            S(.cloud, "#FF3B30", [StrokePoint(608, 130), StrokePoint(800, 250)], width: 2.5, comment: c1),
            S(.textbox, "#FF3B30", [StrokePoint(560, 100)], width: 5, comment: c2, text: "RFI-042 — confirm stair opening width"),
            S(.highlighter, "#FFCC00", ln(240, 651, 500, 651), width: 22, comment: c3),
            S(.stamps, "#34C759", [StrokePoint(480, 505)], comment: c4, text: "APPROVED")
        ]
        p1.strokes[1].background = "#FFFFFF"; p1.strokes[1].backgroundOpacity = 1
        p1.strokes[1].borderColor = "#FF3B30"; p1.strokes[1].borderOpacity = 1; p1.strokes[1].borderWidth = 1.5
        p1.strokes[2].opacity = 0.4
        p1.fields = [
            FormField(type: .text, name: "reviewed_by", x: 862, y: 360, w: 112, h: 30, tab: 1, required: true),
            FormField(type: .check, name: "approved", x: 862, y: 400, w: 26, h: 26, tab: 2),
            FormField(type: .date, name: "review_date", x: 862, y: 436, w: 112, h: 30, tab: 3, validation: .date)
        ]
        p2.strokes = [S(.pen, "#007AFF", ln(200, 200, 600, 200), width: 2.4, comment: IDGen.make())]
        let c5 = p2.strokes[0].commentID!
        let markup = Document(type: .markup, name: "Meridian Tower — L2 Drawings", created: now - 9 * day, modified: now - 2 * hour,
                              pages: [p1, p2, p3], comments: [
            Comment(id: c1, pageID: p1.id, kind: "cloud", author: "Marco Ortiz", time: now - 26 * hour, status: .open,
                    text: "Stair opening reads 3'-2\" here but 3'-6\" on S-201. Confirm before framing.", color: "#FF3B30",
                    replies: [Reply(author: me, time: now - 20 * hour, text: "Checking with structural — will post the answer on RFI-042.")]),
            Comment(id: c2, pageID: p1.id, kind: "textbox", author: "Marco Ortiz", time: now - 26 * hour, status: .open,
                    text: "RFI-042 — confirm stair opening width", color: "#FF3B30"),
            Comment(id: c3, pageID: p1.id, kind: "highlighter", author: me, time: now - 5 * hour, status: .accepted,
                    text: "General note updated in the assembly schedule.", color: "#FFCC00"),
            Comment(id: c4, pageID: p1.id, kind: "stamps", author: me, time: now - 3 * day, status: .completed,
                    text: "Approved for framing.", color: "#34C759"),
            Comment(id: c5, pageID: p2.id, kind: "pen", author: "Marco Ortiz", time: now - 3 * day, status: .completed,
                    text: "Dimension string was missing here.", color: "#007AFF")
        ], bookmarks: [p1.id, p3.id])

        let permit = Document(type: .markup, name: "Permit Set — Rev C", created: now - 12 * day, modified: now - day,
                              pages: (1...4).map { Page.markup(label: "Sheet \($0)", artwork: $0 == 1 ? "plan" : ($0 == 2 ? "elev" : "detail"), created: now - 12 * day) })

        // Drawing: kitchen remodel with layers
        func L(_ name: String, _ kind: LayerKind, _ op: Double, _ strokes: [Stroke]) -> Layer {
            Layer(name: name, kind: kind, opacity: op, strokes: strokes)
        }
        let dp1 = Page(layers: [
            L("Base", .base, 0, [
                S(.pen, "#1c1c1e", [StrokePoint(160, 160), StrokePoint(760, 160), StrokePoint(760, 560), StrokePoint(160, 560), StrokePoint(160, 160)], width: 2.4),
                S(.pen, "#1c1c1e", ln(460, 160, 460, 560), width: 2.4),
                S(.pen, "#1c1c1e", ln(160, 380, 460, 380), width: 2.4)
            ]),
            L("Layer 1 — Option A", .trace, 0.55, [
                S(.felt, "#e8483f", [StrokePoint(460, 250), StrokePoint(620, 250), StrokePoint(620, 560)], width: 4.2),
                S(.fineliner, "#e8483f", circle(540, 460, 40), width: 1.3)
            ]),
            L("Layer 2 — Furniture", .trace, 0.4, [
                S(.pen, "#007AFF", [StrokePoint(200, 200), StrokePoint(300, 200), StrokePoint(300, 260), StrokePoint(200, 260), StrokePoint(200, 200)], width: 2.4),
                S(.pen, "#007AFF", [StrokePoint(200, 420), StrokePoint(340, 420), StrokePoint(340, 520), StrokePoint(200, 520), StrokePoint(200, 420)], width: 2.4)
            ])
        ], created: now - 4 * day)
        let dp2 = Page(layers: [L("Base", .base, 0, [S(.pen, "#1c1c1e", circle(500, 350, 120), width: 2.4)])], created: now - 4 * day)
        let drawing = Document(type: .drawing, name: "Kitchen remodel — plan set", created: now - 4 * day, modified: now - day, pages: [dp1, dp2])

        // Journal: field notebook
        func jp(_ dOff: Double, _ tpl: PageTemplate, _ paper: Paper, _ tags: [String], _ strokes: [Stroke]) -> Page {
            var p = Page.journal(template: tpl, paper: paper, tags: tags, created: now - dOff * day)
            p.modified = now - max(0, dOff - 1) * day
            p.strokes = strokes
            return p
        }
        let journal = Document(type: .journal, name: "Field notebook", created: now - 24 * day, modified: now - hour, pages: [
            jp(24, .blank, .dark, [], [S(.felt, "#f7f0dc", wave(150, 400, 50), width: 4.2)]),
            jp(24, .lined, .cream, ["site visit", "meridian"], [S(.fineliner, "#1c1c1e", wave(70, 120, 60), width: 1.3), S(.fineliner, "#1c1c1e", wave(70, 152, 45), width: 1.3), S(.fineliner, "#1c1c1e", wave(70, 184, 55), width: 1.3)]),
            jp(19, .lined, .cream, ["meridian", "rfi"], [S(.fineliner, "#1c1c1e", wave(70, 120, 50), width: 1.3), S(.pen, "#e8483f", circle(300, 320, 60), width: 2.4)]),
            jp(12, .grid, .white, ["detail", "sketch"], [S(.pen, "#1c1c1e", [StrokePoint(120, 200), StrokePoint(480, 200), StrokePoint(480, 520), StrokePoint(120, 520), StrokePoint(120, 200)], width: 2.4), S(.pen, "#1c1c1e", ln(120, 360, 480, 360), width: 2.4)]),
            jp(6, .dot, .white, ["ideas"], [S(.marker, "#ffd60a", ln(80, 140, 400, 140), width: 14), S(.fineliner, "#1c1c1e", wave(80, 142, 50), width: 1.3)]),
            jp(2, .lined, .cream, ["site visit", "closeout"], [S(.fineliner, "#1c1c1e", wave(70, 120, 58), width: 1.3), S(.fineliner, "#1c1c1e", wave(70, 152, 40), width: 1.3)]),
            jp(0, .blank, .white, [], [])
        ])
        let sketch = Document(type: .journal, name: "Sketchbook", created: now - 40 * day, modified: now - 6 * day, pages: [
            jp(40, .blank, .blue, [], []),
            jp(40, .blank, .grey, ["study"], [S(.felt, "#1c1c1e", circle(300, 380, 150), width: 4.2)]),
            jp(6, .blank, .grey, [], [])
        ])

        return RedlineData(docs: [markup, permit, drawing, journal, sketch], settings: AppSettings(author: me))
    }
}
