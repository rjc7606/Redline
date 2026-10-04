import SwiftUI
import RedlineCore

@main
struct RedlineApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.preferredColorScheme)
                .onOpenURL { url in model.openPDF(from: url) }
                // Leaving the foreground (switching apps, lock, termination) writes everything pending.
                .onChange(of: scenePhase) { _, phase in if phase != .active { model.flushSaves() } else { model.refreshOpenPDFs() } }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = app.theme(systemDark: colorScheme == .dark)
        ZStack {
            theme.bg.ignoresSafeArea()
            switch app.screen {
            case .home:
                HomeView()
            case .workspace:
                if let editor = app.editor {
                    WorkspaceView(editor: editor)
                        .id(editor.docID)
                } else {
                    HomeView()
                }
            }
            if app.settingsOpen {
                SettingsView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(50)
            }
            if let t = app.toast {
                VStack {
                    Spacer()
                    ToastView(text: t).padding(.bottom, 24)
                }
                .allowsHitTesting(false)
                .zIndex(100)
            }
        }
        .environment(\.theme, theme)
        .animation(.easeInOut(duration: 0.2), value: app.settingsOpen)
        .onChange(of: app.settings.theme) { _, _ in app.scheduleSave() }
    }
}
