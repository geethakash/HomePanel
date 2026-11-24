import SwiftUI

@main
struct HomePanelApp: App {
    @State private var app = AppModel()

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
