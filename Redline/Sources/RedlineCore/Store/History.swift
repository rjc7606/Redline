// Snapshot-based undo/redo, capped at 100 entries per document.

import Foundation

public struct History<Value: Sendable & Equatable>: Sendable {
    public private(set) var past: [Value] = []
    public private(set) var future: [Value] = []
    public var cap: Int

    public init(cap: Int = 100) { self.cap = cap }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Call before applying a change: remembers `current` and clears redo.
    public mutating func record(_ current: Value) {
        past.append(current)
        if past.count > cap { past.removeFirst(past.count - cap) }
        future.removeAll()
    }

    /// Returns the value to restore, pushing `current` onto the redo stack.
    public mutating func undo(current: Value) -> Value? {
        guard let v = past.popLast() else { return nil }
        future.append(current)
        return v
    }

    public mutating func redo(current: Value) -> Value? {
        guard let v = future.popLast() else { return nil }
        past.append(current)
        return v
    }

    public mutating func clear() { past.removeAll(); future.removeAll() }
}
