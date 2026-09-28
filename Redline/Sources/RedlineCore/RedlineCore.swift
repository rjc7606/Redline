// Platform-independent app logic. No SwiftUI/UIKit here so it still builds on Windows.

public enum Redline {
    public static func greeting(for name: String) -> String {
        "Hello, \(name)!"
    }
}
