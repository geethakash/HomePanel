import Observation
import ServiceManagement
import os

/// "Open at login", via the system's login item for this app.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    /// macOS wants the user to allow it in System Settings → General → Login Items.
    private(set) var needsApproval = false
    private(set) var error: String?
    @ObservationIgnored private let log = Logger(subsystem: "HomePanel", category: "LoginItem")

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        error = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = error.localizedDescription
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
