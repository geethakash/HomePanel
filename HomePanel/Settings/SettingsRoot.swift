import AppKit
import HAKit
import SwiftUI

/// The Settings window: the first-run setup until HomePanel is connected and has rooms,
/// then the General and Rooms tabs.
struct SettingsRoot: View {
    @Environment(AppModel.self) private var app
    @AppStorage("setupDismissed") private var setupDismissed = false
    @State private var tab = "general"

    var body: some View {
        Group {
            if app.forceSetup || (app.needsSetup && !setupDismissed) {
                SetupWizard(startAtServer: app.forceSetup) {
                    setupDismissed = true
                    app.forceSetup = false
                }
            } else {
                TabView(selection: $tab) {
                    Tab("General", systemImage: "gearshape", value: "general") {
                        ConnectionSettings()
                    }
                    Tab("Rooms", systemImage: "square.grid.2x2", value: "rooms") {
                        RoomsEditor()
                    }
                }
            }
        }
        .onAppear {
            NSApp.activate()
            if let requested = app.settingsTab {
                tab = requested
                app.settingsTab = nil
            }
        }
        .onChange(of: app.settingsTab) { _, requested in
            if let requested {
                tab = requested
                app.settingsTab = nil
            }
        }
        .background(WindowVisibilityReader { app.settingsVisibilityChanged($0) })
    }
}
