// Value-level document operations. The app records undo snapshots around
// these; the functions themselves are pure mutations.

import Foundation

// MARK: - Strokes & comments

public struct StrokeContext: Sendable, Equatable {
    public var pageIndex: Int
    public var layerID: ID?
    public init(pageIndex: Int, layerID: ID? = nil) { self.pageIndex = pageIndex; self.layerID = layerID }
}

public extension Document {
    /// Strokes on a page (or on a layer for drawings).
    func strokes(at ctx: StrokeContext) -> [Stroke] {
        guard pages.indices.contains(ctx.pageIndex) else { return [] }
        let p = pages[ctx.pageIndex]
        if type == .drawing {
            guard let l = p.layers.first(where: { $0.id == ctx.layerID }) ?? p.layers.last else { return [] }
            return l.strokes
        }
        return p.strokes
    }

    mutating func editStrokes(at ctx: StrokeContext, _ body: (inout [Stroke]) -> Void) {
        guard pages.indices.contains(ctx.pageIndex) else { return }
        if type == .drawing {
            let li = pages[ctx.pageIndex].layers.firstIndex { $0.id == ctx.layerID } ?? (pages[ctx.pageIndex].layers.count - 1)
            guard li >= 0 else { return }
            body(&pages[ctx.pageIndex].layers[li].strokes)
        } else {
            body(&pages[ctx.pageIndex].strokes)
        }
        touch(pageIndex: ctx.pageIndex)
    }

    mutating func touch(pageIndex: Int? = nil, now: Date = Date()) {
        modified = now
        if let i = pageIndex, pages.indices.contains(i) { pages[i].modified = now }
    }

    /// Adds a stroke. For markups every stroke becomes (or joins) a comment:
    /// consecutive ink strokes join the open `session` comment; everything else starts a new one.
    /// Returns the comment id used (markup only).
    @discardableResult
    mutating func addStroke(_ strokeIn: Stroke, at ctx: StrokeContext, author: String, session: ID?, now: Date = Date()) -> ID? {
        var stroke = strokeIn
        var cid: ID? = nil
        if type == .markup, pages.indices.contains(ctx.pageIndex) {
            let pageID = pages[ctx.pageIndex].id
            if stroke.tool.kind == .ink, let s = session, let i = comments.firstIndex(where: { $0.id == s && $0.pageID == pageID }) {
                comments[i].time = now
                cid = s
            } else {
                let c = Comment(pageID: pageID, kind: stroke.tool.rawValue, author: author, time: now,
                                text: (stroke.tool.kind == .text || stroke.tool.kind == .stampGallery || stroke.tool.kind == .stampPreset) ? (stroke.text ?? "") : "",
                                color: stroke.color)
                comments.append(c)
                cid = c.id
            }
            stroke.commentID = cid
        }
        editStrokes(at: ctx) { $0.append(stroke) }
        return cid
    }

    mutating func removeStrokes(ids: Set<ID>, at ctx: StrokeContext) {
        editStrokes(at: ctx) { $0.removeAll { ids.contains($0.id) } }
        pruneComments()
    }

    mutating func updateStrokes(ids: Set<ID>, at ctx: StrokeContext, _ body: (inout Stroke) -> Void) {
        editStrokes(at: ctx) { arr in
            for i in arr.indices where ids.contains(arr[i].id) { body(&arr[i]) }
        }
    }

    /// Duplicates strokes offset by 18pt; returns the new ids.
    @discardableResult
    mutating func duplicateStrokes(ids: [ID], at ctx: StrokeContext) -> [ID] {
        var newIDs: [ID] = []
        editStrokes(at: ctx) { arr in
            let copies = arr.filter { ids.contains($0.id) }.map { s -> Stroke in
                var c = s.shifted(dx: 18, dy: 18)
                c.id = IDGen.make()
                newIDs.append(c.id)
                return c
            }
            arr.append(contentsOf: copies)
        }
        return newIDs
    }

    /// Drops comments whose linked strokes are all gone.
    mutating func pruneComments() {
        guard type == .markup else { return }
        let linked = Set(pages.flatMap { $0.strokes.compactMap(\.commentID) })
        comments.removeAll { !linked.contains($0.id) }
    }

    mutating func deleteComment(_ id: ID) {
        comments.removeAll { $0.id == id }
        for i in pages.indices { pages[i].strokes.removeAll { $0.commentID == id } }
        touch()
    }

    mutating func addReply(to id: ID, author: String, text: String, now: Date = Date()) {
        guard let i = comments.firstIndex(where: { $0.id == id }) else { return }
        comments[i].replies.append(Reply(author: author, time: now, text: text))
        touch(now: now)
    }

    mutating func editComment(_ id: ID, _ body: (inout Comment) -> Void) {
        guard let i = comments.firstIndex(where: { $0.id == id }) else { return }
        body(&comments[i])
    }

    /// Stroke ids linked to a comment.
    func strokeIDs(for commentID: ID) -> [ID] {
        pages.flatMap { $0.strokes.filter { $0.commentID == commentID }.map(\.id) }
    }
}

// MARK: - Form fields

public extension Document {
    @discardableResult
    mutating func placeField(_ type: FieldType, at p: Point, pageIndex: Int) -> FormField? {
        guard pages.indices.contains(pageIndex) else { return nil }
        let sz = type.defaultSize
        let n = pages[pageIndex].fields.count + 1
        let f = FormField(type: type, name: "\(type.rawValue)_\(n)", x: (p.x - sz.w / 2).rounded(), y: (p.y - sz.h / 2).rounded(),
                          w: sz.w, h: sz.h, tab: n, options: type.hasOptions ? "Option A\nOption B" : "")
        pages[pageIndex].fields.append(f)
        touch(pageIndex: pageIndex)
        return f
    }

    mutating func editField(_ id: ID, pageIndex: Int, _ body: (inout FormField) -> Void) {
        guard pages.indices.contains(pageIndex), let i = pages[pageIndex].fields.firstIndex(where: { $0.id == id }) else { return }
        body(&pages[pageIndex].fields[i])
    }

    mutating func deleteField(_ id: ID, pageIndex: Int) {
        guard pages.indices.contains(pageIndex) else { return }
        pages[pageIndex].fields.removeAll { $0.id == id }
        touch(pageIndex: pageIndex)
    }
}

// MARK: - Layers (Drawing)

public enum FlattenMode: String, Sendable { case keep, ink }

public extension Document {
    /// Adds "Layer N" (trace, veil .5) above the active layer; returns its id.
    @discardableResult
    mutating func addTraceLayer(pageIndex: Int, above activeID: ID?) -> ID? {
        guard pages.indices.contains(pageIndex) else { return nil }
        let n = pages[pageIndex].layers.filter(\.isTrace).count + 1
        let L = Layer(name: "Layer \(n)", kind: .trace, opacity: 0.5)
        let i = pages[pageIndex].layers.firstIndex { $0.id == activeID }
        pages[pageIndex].layers.insert(L, at: i.map { $0 + 1 } ?? pages[pageIndex].layers.count)
        touch(pageIndex: pageIndex)
        return L.id
    }

    mutating func editLayer(_ id: ID, pageIndex: Int, _ body: (inout Layer) -> Void) {
        guard pages.indices.contains(pageIndex), let i = pages[pageIndex].layers.firstIndex(where: { $0.id == id }) else { return }
        body(&pages[pageIndex].layers[i])
    }

    /// Can "Keep as trace" be offered for flattening `layerID` down (or all layers)?
    func canKeepVeil(pageIndex: Int, layerID: ID?) -> Bool {
        guard pages.indices.contains(pageIndex) else { return false }
        let ls = pages[pageIndex].layers
        guard let id = layerID else { return ls.count > 2 }
        guard let i = ls.firstIndex(where: { $0.id == id }), i > 0 else { return false }
        return ls[i - 1].isTrace
    }

    /// Merges layer `layerID` onto the one beneath (or all traces onto the base when nil).
    /// Returns the id of the layer that should become active.
    @discardableResult
    mutating func flatten(pageIndex: Int, layerID: ID?, mode: FlattenMode) -> ID? {
        guard pages.indices.contains(pageIndex) else { return nil }
        var ls = pages[pageIndex].layers
        defer { pages[pageIndex].layers = ls; touch(pageIndex: pageIndex) }
        guard let id = layerID else {
            guard var base = ls.first else { return nil }
            let traces = ls.dropFirst()
            let ink = traces.flatMap(\.strokes)
            if mode == .ink {
                base.strokes.append(contentsOf: ink)
                ls = [base]
                return base.id
            }
            var veil = 1.0
            for t in traces { veil *= (1 - t.opacity) }
            let merged = Layer(name: "Layer (merged)", kind: .trace, opacity: 1 - veil, strokes: ink)
            ls = [base, merged]
            return merged.id
        }
        guard let i = ls.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
        let L = ls[i]
        ls[i - 1].strokes.append(contentsOf: L.strokes)
        if mode == .keep, ls[i - 1].isTrace {
            ls[i - 1].opacity = 1 - (1 - ls[i - 1].opacity) * (1 - L.opacity)
        }
        ls.remove(at: i)
        return ls[i - 1].id
    }
}

// MARK: - Pages

public extension Document {
    @discardableResult
    mutating func insertPage(after index: Int, now: Date = Date()) -> Int {
        let np: Page
        switch type {
        case .markup: np = .markup(label: "Inserted Page", created: now)
        case .drawing: np = .drawing(created: now)
        case .journal:
            let prev = pages.last ?? .journal(template: .lined, paper: .cream)
            np = .journal(template: prev.template, paper: prev.paper, created: now)
        }
        let at = min(pages.count, max(0, index + 1))
        pages.insert(np, at: at)
        touch(now: now)
        return at
    }

    /// Journal: append a page cloning the previous template/paper; returns its index.
    @discardableResult
    mutating func appendJournalPage(now: Date = Date()) -> Int {
        insertPage(after: pages.count - 1, now: now)
    }

    mutating func duplicatePage(at i: Int, now: Date = Date()) {
        guard pages.indices.contains(i) else { return }
        var cp = pages[i]
        cp.id = IDGen.make()
        cp.label = cp.label.isEmpty ? "" : cp.label + " copy"
        cp.strokes = cp.strokes.map { var s = $0; s.id = IDGen.make(); s.commentID = nil; return s }
        cp.fields = cp.fields.map { var f = $0; f.id = IDGen.make(); return f }
        cp.layers = cp.layers.map { var l = $0; l.id = IDGen.make(); l.strokes = l.strokes.map { var s = $0; s.id = IDGen.make(); return s }; return l }
        pages.insert(cp, at: i + 1)
        touch(now: now)
    }

    /// Deletes a page (never the last one). Returns false if refused.
    @discardableResult
    mutating func deletePage(at i: Int) -> Bool {
        guard pages.count > 1, pages.indices.contains(i) else { return false }
        let pg = pages.remove(at: i)
        comments.removeAll { $0.pageID == pg.id }
        bookmarks.removeAll { $0 == pg.id }
        touch()
        return true
    }

    mutating func rotatePage(at i: Int) {
        guard pages.indices.contains(i) else { return }
        pages[i].rotation = (pages[i].rotation + 90) % 360
        touch(pageIndex: i)
    }

    mutating func movePage(from: Int, to: Int) {
        guard pages.indices.contains(from), to >= 0, to < pages.count, from != to else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: to)
        touch()
    }

    mutating func toggleBookmark(pageIndex i: Int) {
        guard pages.indices.contains(i) else { return }
        let id = pages[i].id
        if bookmarks.contains(id) { bookmarks.removeAll { $0 == id } } else { bookmarks.append(id) }
    }

    // MARK: Journal tags

    mutating func addTag(_ raw: String, pageIndex i: Int) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, pages.indices.contains(i), !pages[i].tags.contains(name) else { return }
        pages[i].tags.append(name)
        touch(pageIndex: i)
    }

    mutating func removeTag(_ name: String, pageIndex i: Int) {
        guard pages.indices.contains(i) else { return }
        pages[i].tags.removeAll { $0 == name }
        touch(pageIndex: i)
    }

    /// All tags with counts, most used first.
    func tagCounts() -> [(name: String, count: Int)] {
        var m: [String: Int] = [:]
        for p in pages { for t in p.tags { m[t, default: 0] += 1 } }
        return m.map { (name: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
