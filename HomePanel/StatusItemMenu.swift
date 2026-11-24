import AppKit
import SwiftUI

/// Right-click (or Control-click) on the menu bar icon shows Settings and Quit.
/// A left click still opens the panel.
///
/// SwiftUI's MenuBarExtra has no context menu, so this watches for right clicks on the app's
/// own status bar button and shows an NSMenu there instead of the panel.
@MainActor
final class StatusItemMenu: NSObject {
    private var monitor: Any?
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            // Local monitors run on the main thread.
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event  // nil: don't open the panel
        }
    }

    /// Shows the menu for a right click on the status bar button; true if it did.
    private func handle(_ event: NSEvent) -> Bool {
        let isSecondary = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isSecondary, let window = event.window, Self.isStatusBarWindow(window),
            let view = window.contentView
        else { return false }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
        return true
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBar")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit HomePanel", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func showSettings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// The menu bar icon. It's always on screen, so it also hands SwiftUI's openSettings action to
/// the app model for the right-click menu.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "house.fill")
            .onAppear { app.registerOpenSettings { openSettings() } }
    }
}
