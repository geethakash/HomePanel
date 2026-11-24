import Foundation
import Observation
import os

/// Loads and saves the panel layout (`config.json` in the App Group container).
@MainActor
@Observable
public final class ConfigStore {
    public private(set) var config: PanelConfig
    @ObservationIgnored public let fileURL: URL
    @ObservationIgnored private let log = Logger(subsystem: "HAKit", category: "ConfigStore")

    /// `<App Group>/Library/Application Support/HomePanel/config.json`,
    /// or `~/Library/Application Support/HomePanel/config.json` without an App Group.
    public static var defaultURL: URL {
        let base =
            SharedConfig.appGroupID
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            .map { $0.appending(path: "Library/Application Support", directoryHint: .isDirectory) }
            ?? URL.applicationSupportDirectory
        return base.appending(path: "HomePanel/config.json")
    }

    /// Loads the saved layout. If there is none, `makeInitial` builds one and it is saved.
    ///
    /// A file that exists but can't be read is moved aside (`config.unreadable-<date>.json`)
    /// rather than overwritten, so a bad edit never loses the layout.
    public init(fileURL: URL = ConfigStore.defaultURL, makeInitial: () -> PanelConfig = { PanelConfig() }) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            do {
                config = try PanelConfig.decode(data)
                return
            } catch {
                let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                    .replacingOccurrences(of: ":", with: "")
                let aside = fileURL.deletingLastPathComponent().appending(path: "config.unreadable-\(stamp).json")
                try? FileManager.default.moveItem(at: fileURL, to: aside)
                Logger(subsystem: "HAKit", category: "ConfigStore")
                    .error("Layout unreadable, moved to \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        config = makeInitial()
        save()
    }

    public var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Applies a change and saves it.
    public func update(_ change: (inout PanelConfig) -> Void) {
        var copy = config
        change(&copy)
        guard copy != config else { return }
        config = copy
        save()
    }

    public func replace(with newConfig: PanelConfig) {
        config = newConfig
        save()
    }

    public func importConfig(from data: Data) throws {
        replace(with: try PanelConfig.decode(data))
    }

    public func exportData() throws -> Data {
        try config.encoded()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try config.encoded().write(to: fileURL, options: .atomic)
        } catch {
            log.error("Couldn't save config: \(error.localizedDescription, privacy: .public)")
        }
    }
}
