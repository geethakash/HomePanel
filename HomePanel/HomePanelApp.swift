import SwiftUI

@main
struct HomePanelApp: App {
    @State private var app = AppModel()

    init() {
        #if DEBUG
        // Tools/make-screenshots.sh: render the demo home to PNGs, then quit.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-screenshots"), args.indices.contains(i + 1) {
            let folder = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ScreenshotRenderer.run(to: folder)
                    exit(0)
                }
            }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PanelRootView()
                .environment(app)
        } label: {
            MenuBarLabel()
                .environment(app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRoot()
                .environment(app)
        }
    }
}
