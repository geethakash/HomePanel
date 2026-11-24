import Foundation

public enum HARestError: LocalizedError, Sendable, Equatable {
    case unauthorized
    case http(Int)
    case invalidResponse
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Home Assistant rejected the token (401). Create a new long-lived token."
        case .http(let code): "Home Assistant returned HTTP \(code)."
        case .invalidResponse: "Unexpected reply from Home Assistant."
        case .invalidURL: "That isn't a valid http(s) URL."
        }
    }
}

/// One-shot REST calls (Test connection in Settings).
public struct HARest: Sendable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 10
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    public struct ServerInfo: Sendable {
        public let version: String
        public let locationName: String
    }

    /// `GET /api/` then `GET /api/config`.
    public func serverInfo() async throws -> ServerInfo {
        let status = try await request("api/")
        guard status["message"]?.string != nil else { throw HARestError.invalidResponse }
        let cfg = try await request("api/config")
        return ServerInfo(
            version: cfg["version"]?.string ?? "unknown",
            locationName: cfg["location_name"]?.string ?? "Home")
    }

    public func state(_ entityID: String) async throws -> HAState {
        try HAState(rest: try await request("api/states/\(entityID)"))
    }

    public func callService(_ domain: String, _ service: String, data: [String: JSONValue]) async throws {
        _ = try await request("api/services/\(domain)/\(service)", method: "POST", body: .object(data))
    }

    private func request(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> JSONValue {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try body.serialized() }
        let (data, response) = try await Self.session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw HARestError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return try JSONValue.parse(data)
        case 401, 403: throw HARestError.unauthorized
        default: throw HARestError.http(http.statusCode)
        }
    }
}

public enum HAErrorText {
    /// A short, human message for any error from HARest/HAClient.
    public static func describe(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
                .notConnectedToInternet, .dnsLookupFailed:
                return "Can't reach Home Assistant. Are you on your home network?"
            default:
                return e.localizedDescription
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
