import SwiftUI

@main
struct HomePanelApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        MenuBarExtra("HomePanel", systemImage: "house.fill") {
            PanelRootView()
                .environment(app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRoot()
                .environment(app)
        }
    }
}
