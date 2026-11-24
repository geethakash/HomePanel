import Foundation
import Network
import Observation

/// Finds Home Assistant on the local network over Bonjour (`_home-assistant._tcp`).
/// HA advertises its URLs in the TXT record, so no extra lookup is needed.
@MainActor
@Observable
final class HADiscovery {
    struct Server: Identifiable, Hashable {
        let id: String
        let name: String
        let url: String
        let version: String?
    }

    private(set) var servers: [Server] = []
    private(set) var searching = false
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_home-assistant._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.server)
            Task { @MainActor in
                self?.servers = Array(Set(found)).sorted { $0.name < $1.name }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let active: Bool =
                switch state {
                case .ready, .setup: true
                default: false
                }
            Task { @MainActor in self?.searching = active }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    nonisolated private static func server(_ result: NWBrowser.Result) -> Server? {
        guard case .bonjour(let txt) = result.metadata else { return nil }
        let url = txt["internal_url"].flatMap { $0.isEmpty ? nil : $0 } ?? txt["base_url"]
        guard let url, !url.isEmpty else { return nil }
        var name = txt["location_name"] ?? "Home Assistant"
        if case .service(let service, _, _, _) = result.endpoint, name.isEmpty { name = service }
        return Server(id: txt["uuid"] ?? url, name: name, url: url, version: txt["version"])
    }
}
