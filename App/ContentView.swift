import SwiftUI
import RedlineCore

struct ContentView: View {
    var body: some View {
        Text(Redline.greeting(for: "iPad"))
            .font(.largeTitle)
    }
}
