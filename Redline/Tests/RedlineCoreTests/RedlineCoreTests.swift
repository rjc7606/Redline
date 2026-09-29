import Foundation
import Testing
@testable import RedlineCore

/// Small fixture set used by the store / calendar / persistence tests.
func fixtureData() -> RedlineData {
    let now = Date()
    var markup = Document(type: .markup, name: "Plan.pdf", created: now - 86400, pages: [.markup(label: "Page 1"), .markup(label: "Page 2")])
    markup.pages[0].strokes = [Stroke(tool: .pen, color: "#000", points: [StrokePoint(1, 1), StrokePoint(5, 5)], width: 2)]
    let journal = Document(type: .journal, name: "Notebook", created: now - 3 * 86400, pages: [
        .journal(template: .blank, paper: .grey, created: now - 3 * 86400),
        .journal(template: .lined, paper: .cream, tags: ["site"], created: now - 86400),
        .journal(template: .dot, paper: .white, created: now)
    ])
    return RedlineData(docs: [markup, journal], settings: AppSettings(author: "Tessa Mahler"))
}

// MARK: Colours & formatting

@Test func hexParsing() {
    #expect(HexColor.normalize("#ff3b30") == "#FF3B30")
    #expect(HexColor.normalize("e8483f") == "#E8483F")
    #expect(HexColor.normalize("#abc") == "#AABBCC")
    #expect(HexColor.normalize("nope") == nil)
    #expect(HexColor.luminance("#ffffff") > 0.99)
    #expect(HexColor.luminance("#000000") < 0.01)
    #expect(HexColor.isUnreadable("#ffffff", dark: false))
    #expect(!HexColor.isUnreadable("#ffffff", dark: true))
    #expect(HexColor.isUnreadable("#1c1c1e", dark: true))
    #expect(HexColor.hsl(0, 0, 100) == "#FFFFFF")
    #expect(HexColor.hsl(0, 100, 50) == "#FF0000")
}

@Test func agoFormatting() {
    let now = Date()
    #expect(Formatting.ago(now - 10, now: now) == "just now")
    #expect(Formatting.ago(now - 5 * 60, now: now) == "5m ago")
    #expect(Formatting.ago(now - 3 * 3600, now: now) == "3h ago")
    #expect(Formatting.ago(now - 2 * 86400, now: now) == "2d ago")
    #expect(Formatting.plural(1, "page") == "1 page")
    #expect(Formatting.plural(3, "reply", "replies") == "3 replies")
    #expect(Avatar.initials("Marco Ortiz") == "MO")
    #expect(Avatar.colors.contains(Avatar.color(for: "Tessa Mahler")))
}

// MARK: Styles & palettes

@Test func stylePresetDefaults() {
    var st = ToolStyles()
    #expect(st.presets(for: .pen).count == 4)
    #expect(st.current(for: .pen).width == 2.4)
    #expect(st.current(for: .marker).opacity == 0.55)
    #expect(st.current(for: .highlighter).width == 22)
    #expect(st.current(for: .rect).fillPattern == FillPattern.none)
    #expect(st.presets(for: .textbox)[1].background == "#FFF9C4")
    st.select(2, for: .pen)
    #expect(st.current(for: .pen).color == "#007AFF")
    st.update(.pen) { $0.width = 5 }
    #expect(st.current(for: .pen).width == 5)
    #expect(st.presets(for: .pen)[0].width == 2.4)
    st.reset(.pen)
    #expect(st.current(for: .pen).width == 2.4)
    #expect(ToolStyles.widthRange(for: .fineliner) == 0.5...3)
    #expect(ToolStyles.quickPalette.count == 12)
    #expect(Spectrum.grid.count == 120)
}

@Test func paletteOperations() {
    var ps = PaletteStore()
    #expect(ps.defaultPalette.id == "redline")
    #expect(ps.ordered.first?.id == "redline")
    let p = ps.addNew()
    #expect(p.colors == PaletteStore.newPaletteSeed)
    ps.rename(p.id, to: "Site")
    #expect(ps.palette(p.id)?.name == "Site")
    ps.setSwatch(p.id, index: 0, hex: "#123456")
    #expect(ps.palette(p.id)?.colors[0] == "#123456")
    let n = ps.addSwatch(p.id)
    #expect(n == 4)
    ps.removeSwatch(p.id, index: 4)
    #expect(ps.palette(p.id)?.colors.count == 4)
    ps.makeDefault(p.id)
    #expect(ps.ordered.first?.id == p.id)
    // built-ins are locked
    ps.rename("redline", to: "X")
    #expect(ps.palette("redline")?.name == "Redline")
    ps.delete("redline")
    #expect(ps.palette("redline") != nil)
    ps.delete(p.id)
    #expect(ps.palette(p.id) == nil)
    #expect(ps.defaultID == "redline")
}

// MARK: Geometry

@Test func svgPathParsing() {
    let p = SVGPath.parse("M4 5.5h16v13H4z")
    #expect(p.ops.count == 5)
    #expect(p.ops[0] == .move(Point(4, 5.5)))
    #expect(p.ops[1] == .line(Point(20, 5.5)))
    #expect(p.ops[2] == .line(Point(20, 18.5)))
    #expect(p.ops[4] == .close)
    let arc = SVGPath.parse("M3.5 12a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0 -17 0")
    #expect(arc.ops.count > 3)
    let b = arc.bounds
    #expect(abs(b.minX - 3.5) < 0.6 && abs(b.maxX - 20.5) < 0.6)
    let glyphs = ToolCatalog.info.values.compactMap(\.glyph)
    for g in glyphs { #expect(!SVGPath.parse(g).isEmpty) }
}

@Test func strokeGeometry() {
    let ink = Stroke(tool: .pen, color: "#000", points: [StrokePoint(0, 0), StrokePoint(10, 0), StrokePoint(20, 5)], width: 3)
    let r = StrokeGeometry.render(ink)!
    #expect(r.strokeWidth == 3)
    #expect(r.fillColor == nil)
    var pr = ink; pr.weight = .pressure
    let r2 = StrokeGeometry.render(pr)!
    #expect(r2.fillColor == "#000" && r2.strokeColor == nil)
    let rect = Stroke(tool: .rect, color: "#f00", points: [StrokePoint(10, 10), StrokePoint(110, 60)], fill: "#0f0", fillPattern: .solid)
    let rr = StrokeGeometry.render(rect)!
    #expect(rr.fillColor == "#0f0")
    #expect(rr.path.bounds == Rect(x: 10, y: 10, w: 100, h: 50))
    let dashed = Stroke(tool: .line, color: "#f00", points: [StrokePoint(0, 0), StrokePoint(50, 0)], width: 2, lineStyle: .dash)
    #expect(StrokeGeometry.render(dashed)!.dash == [6, 4])
    let cloud = StrokeGeometry.cloud(Rect(x: 0, y: 0, w: 100, h: 60), radius: 10)
    #expect(cloud.ops.count > 10)
    let check = Stroke(tool: .check, color: "#0a0", points: [StrokePoint(50, 50)])
    #expect(StrokeGeometry.render(check) != nil)
    #expect(StrokeGeometry.render(Stroke(tool: .textbox, color: "#000", points: [StrokePoint(1, 1)], text: "hi")) == nil)
    let b = StrokeGeometry.bounds(of: check)
    #expect(b.contains(Point(50, 50)))
}

@Test func hitTesting() {
    let s = Stroke(tool: .pen, color: "#000", points: [StrokePoint(0, 0), StrokePoint(100, 0)], width: 2)
    #expect(Hit.strokeTouches(s, point: Point(50, 5), radius: 10))
    #expect(!Hit.strokeTouches(s, point: Point(50, 40), radius: 10))
    let poly = [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)]
    #expect(Hit.polygon(poly, contains: Point(5, 5)))
    #expect(!Hit.polygon(poly, contains: Point(15, 5)))
    let simplified = Hit.simplify([Point(0, 0), Point(1, 0.1), Point(2, -0.1), Point(3, 0), Point(3, 10)], tolerance: 1)
    #expect(simplified == [Point(0, 0), Point(3, 0), Point(3, 10)])
}

@Test func partialErase() {
    let s = Stroke(tool: .pen, color: "#000", points: [StrokePoint(0, 0), StrokePoint(100, 0)], width: 2)
    #expect(Hit.erase(s, at: Point(50, 40), radius: 10) == nil)
    let pieces = Hit.erase(s, at: Point(50, 0), radius: 5)!
    #expect(pieces.count == 2)
    #expect(pieces[0].id == s.id && pieces[1].id != s.id)
    #expect(pieces[0].points.last!.x < 45 && pieces[1].points.first!.x > 55)
    let gone = Hit.erase(s, at: Point(50, 0), radius: 80)!
    #expect(gone.isEmpty)
    let stamp = Stroke(tool: .stamps, color: "#000", points: [StrokePoint(50, 50)], text: "OK")
    #expect(Hit.erase(stamp, at: Point(50, 50), radius: 4) == nil)
    let box = Stroke(tool: .rect, color: "#000", points: [StrokePoint(0, 0), StrokePoint(100, 100)])
    #expect(Hit.erase(box, at: Point(50, 0), radius: 10) == nil)
    var doc = Document(type: .markup, name: "m", pages: [.markup()])
    let ctx = StrokeContext(pageIndex: 0)
    doc.addStroke(s, at: ctx, author: "Me", session: nil)
    let erased = doc.erase(at: Point(50, 0), radius: 5, at: ctx)
    #expect(erased)
    #expect(doc.pages[0].strokes.count == 2 && doc.comments.count == 1)
    #expect(doc.pages[0].strokes.allSatisfy { $0.commentID == doc.comments[0].id })
    let untouched = doc.erase(at: Point(50, 300), radius: 5, at: ctx)
    #expect(!untouched)
}

@Test func textAnchoredMarkup() {
    let hl = Stroke(tool: .highlighter, color: "#ff0", points: [StrokePoint(10, 10), StrokePoint(200, 30)], width: 22,
                    rects: [Rect(x: 10, y: 5, w: 100, h: 12), Rect(x: 0, y: 20, w: 60, h: 12)])
    let r = StrokeGeometry.render(hl)!
    #expect(r.fillColor == "#ff0" && r.strokeColor == nil && r.multiply)
    let b = StrokeGeometry.bounds(of: hl)
    #expect(b.minX <= 0 && b.maxX >= 110)
    let ul = Stroke(tool: .underline, color: "#f00", points: [StrokePoint(0, 0)], rects: [Rect(x: 0, y: 0, w: 50, h: 10)])
    #expect(StrokeGeometry.render(ul)!.strokeColor == "#f00")
    let shifted = hl.shifted(dx: 5, dy: 5)
    #expect(shifted.rects?[0].x == 15)
    var doc = Document(type: .markup, name: "m", pages: [.markup()], sheetSize: Size(1000, 1294))
    #expect(doc.canvasSize == Size(1000, 1294))
    doc.sheetSize = nil
    #expect(doc.canvasSize == Metrics.sheetCanvas)
}

// MARK: History & store

@Test func historyUndoRedo() {
    var h = History<Int>(cap: 3)
    h.record(1); h.record(2); h.record(3); h.record(4)
    #expect(h.past == [2, 3, 4])
    #expect(h.undo(current: 5) == 4)
    #expect(h.canRedo)
    #expect(h.redo(current: 4) == 5)
    #expect(!h.canRedo)
}

@Test func storeMutationsAndUndo() {
    var store = RedlineStore(data: fixtureData())
    let doc = store.documents(on: .markup)[0]
    let ctx = StrokeContext(pageIndex: 0)
    let before = store.document(doc.id)!.pages[0].strokes.count
    store.mutate(doc.id) { d in
        d.addStroke(Stroke(tool: .pen, color: "#000", points: [StrokePoint(1, 1), StrokePoint(2, 2)]), at: ctx, author: "Me", session: nil)
    }
    #expect(store.document(doc.id)!.pages[0].strokes.count == before + 1)
    #expect(store.canUndo(doc.id))
    store.undo(doc.id)
    #expect(store.document(doc.id)!.pages[0].strokes.count == before)
    store.redo(doc.id)
    #expect(store.document(doc.id)!.pages[0].strokes.count == before + 1)
}

@Test func markupCommentsGroupInkSessions() {
    var doc = Document(type: .markup, name: "t", pages: [.markup()])
    let ctx = StrokeContext(pageIndex: 0)
    let first = doc.addStroke(Stroke(tool: .pen, color: "#000", points: [StrokePoint(0, 0), StrokePoint(1, 1)]), at: ctx, author: "Me", session: nil)
    #expect(first != nil && doc.comments.count == 1)
    let second = doc.addStroke(Stroke(tool: .pen, color: "#000", points: [StrokePoint(2, 2), StrokePoint(3, 3)]), at: ctx, author: "Me", session: first)
    #expect(second == first && doc.comments.count == 1)
    let text = doc.addStroke(Stroke(tool: .textbox, color: "#f00", points: [StrokePoint(5, 5)], text: "Note"), at: ctx, author: "Me", session: first)
    #expect(text != first && doc.comments.count == 2)
    #expect(doc.comments[1].text == "Note")
    #expect(doc.strokeIDs(for: first!).count == 2)
    doc.deleteComment(first!)
    #expect(doc.pages[0].strokes.count == 1 && doc.comments.count == 1)
    doc.removeStrokes(ids: Set(doc.pages[0].strokes.map(\.id)), at: ctx)
    #expect(doc.comments.isEmpty)
}

@Test func layerFlattening() {
    var doc = Document(type: .drawing, name: "d", pages: [.drawing()])
    let l1 = doc.addTraceLayer(pageIndex: 0, above: doc.pages[0].layers[0].id)!
    let l2 = doc.addTraceLayer(pageIndex: 0, above: l1)!
    #expect(doc.pages[0].layers.map(\.name) == ["Base", "Layer 1", "Layer 2"])
    doc.editStrokes(at: StrokeContext(pageIndex: 0, layerID: l2)) { $0.append(Stroke(tool: .pen, color: "#000", points: [StrokePoint(0, 0)])) }
    #expect(doc.canKeepVeil(pageIndex: 0, layerID: l2))
    #expect(!doc.canKeepVeil(pageIndex: 0, layerID: l1))
    let active = doc.flatten(pageIndex: 0, layerID: l2, mode: .keep)
    #expect(active == l1)
    #expect(doc.pages[0].layers.count == 2)
    #expect(abs(doc.pages[0].layers[1].opacity - 0.75) < 1e-9)
    #expect(doc.pages[0].layers[1].strokes.count == 1)
    _ = doc.addTraceLayer(pageIndex: 0, above: l1)
    let base = doc.flatten(pageIndex: 0, layerID: nil, mode: .ink)
    #expect(base == doc.pages[0].layers[0].id && doc.pages[0].layers.count == 1)
    #expect(doc.pages[0].layers[0].strokes.count == 1)
}

@Test func pageOperations() {
    var doc = Document(type: .journal, name: "j", pages: [.journal(template: .blank, paper: .grey), .journal(template: .lined, paper: .cream)])
    let i = doc.appendJournalPage()
    #expect(i == 2 && doc.pages[2].template == .lined && doc.pages[2].paper == .cream)
    doc.addTag(" Site Visit ", pageIndex: 2)
    doc.addTag("site visit", pageIndex: 1)
    #expect(doc.tagCounts().first?.name == "site visit" && doc.tagCounts().first?.count == 2)
    doc.removeTag("site visit", pageIndex: 2)
    #expect(doc.pages[2].tags.isEmpty)
    let deleted = doc.deletePage(at: 2)
    #expect(deleted && doc.pages.count == 2)
    var single = Document(type: .markup, name: "m", pages: [.markup()])
    let refused = single.deletePage(at: 0)
    #expect(!refused && single.pages.count == 1)
    var m = Document(type: .markup, name: "m", pages: [.markup(label: "A")])
    m.pages[0].template = .grid
    let ins = m.insertPage(after: 0)
    #expect(ins == 1 && m.pages[1].template == .grid)
    m.deletePage(at: 1)
    m.duplicatePage(at: 0)
    #expect(m.pages.count == 2 && m.pages[1].label == "A copy")
    m.rotatePage(at: 0)
    #expect(m.pages[0].rotation == 90)
    m.movePage(from: 1, to: 0)
    #expect(m.pages[0].label == "A copy")
    m.toggleBookmark(pageIndex: 0)
    #expect(m.bookmarks.count == 1)
}

@Test func formFields() {
    var doc = Document(type: .markup, name: "m", pages: [.markup()])
    let f = doc.placeField(.drop, at: Point(100, 100), pageIndex: 0)!
    #expect(f.name == "drop_1" && f.optionList == ["Option A", "Option B"])
    #expect(f.x == 10 && f.w == 180)
    doc.editField(f.id, pageIndex: 0) { $0.value = "Option B"; $0.required = true }
    #expect(doc.pages[0].fields[0].required)
    doc.deleteField(f.id, pageIndex: 0)
    #expect(doc.pages[0].fields.isEmpty)
}

@Test func createDocuments() {
    var store = RedlineStore(data: RedlineData())
    let j = store.createDocument(type: .journal, name: "  ", template: .dot, paper: .white)
    #expect(j.name == "Untitled notebook" && j.pages.count == 2 && j.pages[0].paper == .grey && j.pages[1].template == .dot)
    let d = store.createDocument(type: .drawing, name: "Plan")
    #expect(d.pages[0].layers.count == 1 && d.pages[0].layers[0].kind == .base)
    let m = store.createDocument(type: .markup, name: "x.pdf", pageCount: 5, pdfFile: "abc.pdf")
    #expect(m.pages.count == 5 && m.pages[4].pdfPageIndex == 4 && m.pdfFile == "abc.pdf")
    #expect(store.count(on: .journal) == 1)
    store.deleteDocument(m.id)
    #expect(store.count(on: .markup) == 0)
}

@Test func persistenceRoundTrip() throws {
    let data = fixtureData()
    let bytes = try data.encode()
    let back = try RedlineData.decode(bytes)
    #expect(back.docs.count == data.docs.count)
    #expect(back.docs[0].pages[0].strokes == data.docs[0].pages[0].strokes)
    #expect(back.settings.author == "Tessa Mahler")
    #expect(back.palettes.palettes.count == 4)
    #expect(Seed.data().docs.isEmpty)
}

// MARK: Journal

@Test func bookGeometry() {
    let single = BookGeometry(pageCount: 5, pageIndex: 2, spread: false)
    #expect(single.visiblePages == [2] && single.nextIndex == 3 && single.prevIndex == 1 && single.canBack)
    let cover = BookGeometry(pageCount: 5, pageIndex: 0, spread: true)
    #expect(cover.visiblePages == [0] && !cover.canBack && cover.nextIndex == 1)
    let mid = BookGeometry(pageCount: 5, pageIndex: 1, spread: true)
    #expect(mid.visiblePages == [1, 2] && mid.prevIndex == 0 && mid.nextIndex == 3)
    let last = BookGeometry(pageCount: 4, pageIndex: 3, spread: true)
    #expect(last.visiblePages == [3] && last.rightSlotEmpty && !last.nextExists)
    #expect(BookGeometry.label(for: 0) == "Cover" && BookGeometry.longLabel(for: 3) == "Page 3")
}

@Test func calendarMonth() {
    let doc = fixtureData().docs.first { $0.type == .journal }!
    let cal = CalendarMonth(document: doc, monthOffset: 0, mode: .created)
    #expect(cal.cells.count == 35 || cal.cells.count == 42)
    #expect(cal.cells.contains { $0.isToday })
    let todayPages = cal.cells.first { $0.isToday }!.pages
    #expect(todayPages.contains(doc.pages.count - 1))
}

@Test func layoutMath() {
    let z = Metrics.fitZoom(canvas: Metrics.sheetCanvas, available: Size(1366 - 232, 1024 - 108))
    #expect(z > 0.9 && z <= 1.4)
    let zs = Metrics.fitZoom(canvas: Metrics.notesCanvas, available: Size(1000, 700), spread: true)
    #expect(zs < 0.9)
    #expect(ToolCatalog.markupTabs.map(\.id) == ["draw", "annotate", "edit", "forms"])
    #expect(Tool.pen.hasPresets && !Tool.eraser.hasPresets)
    #expect(ToolCatalog.tool(for: .list) == .flist)
    #expect(ToolCatalog.pickHint(for: .distance, rulerLocked: false) == "Measure tools are preview-only")
}
