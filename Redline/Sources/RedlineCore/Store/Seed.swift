// First-launch state: no documents, default settings, built-in palettes and presets.

import Foundation

public enum Seed {
    public static func data(now: Date = Date()) -> RedlineData {
        RedlineData(docs: [], settings: AppSettings())
    }
}
