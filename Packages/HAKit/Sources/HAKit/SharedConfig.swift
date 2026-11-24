import Foundation
import Security
import os

/// App settings, kept in the App Group defaults.
public enum SharedConfig {
    /// Shown as a hint in URL fields; never used as an actual address.
    public static let exampleBaseURL = "http://homeassistant.local:8123"

    /// `<TEAMID>.homepanel`, injected into Info.plist by project.yml.
    /// nil when the build has no App Group (the ad-hoc DMG build).
    public static var appGroupID: String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "HomePanelAppGroup") as? String)
    }

    /// `<TEAMID>.<bundle ID>.shared`: the Keychain group that holds the token.
    public static var keychainGroupID: String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "HomePanelKeychainGroup") as? String)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    public static var defaults: UserDefaults {
        appGroupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The saved Home Assistant address, or "" before setup.
    public static var baseURLString: String {
        get { defaults.string(forKey: "haBaseURL") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "haBaseURL") }
    }

    public static var baseURL: URL? { validatedURL(baseURLString) }

    public static var hasSavedURL: Bool { defaults.string(forKey: "haBaseURL")?.isEmpty == false }

    public static func validatedURL(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }
}

/// The HA long-lived access token, kept in the Keychain. Never log it.
///
/// Uses the data-protection keychain in the app's Keychain group. Falls back to the login
/// keychain if the group isn't available (e.g. an unsigned debug build).
public enum TokenStore {
    private static let service = "HomePanel.HomeAssistantToken"
    private static let account = "default"
    private static let log = Logger(subsystem: "HAKit", category: "TokenStore")

    public enum TokenError: LocalizedError {
        case keychain(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .keychain(let s):
                "Keychain error \(s): \(SecCopyErrorMessageString(s, nil) as String? ?? "unknown")"
            }
        }
    }

    private static func baseQuery(shared: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared, let group = SharedConfig.keychainGroupID ?? SharedConfig.appGroupID {
            q[kSecUseDataProtectionKeychain as String] = true
            q[kSecAttrAccessGroup as String] = group
        } else {
            // Always say which keychain: with a keychain group, an unqualified query also
            // matches (and would delete) the shared item.
            q[kSecUseDataProtectionKeychain as String] = false
        }
        return q
    }

    public static var hasToken: Bool { load() != nil }

    /// Where the token lives: `.shared` is the Keychain group, `.appOnly` the login keychain.
    public enum Location: String, Sendable {
        case shared, appOnly, none
    }

    public static var location: Location {
        if read(shared: true) != nil { return .shared }
        if read(shared: false) != nil { return .appOnly }
        return .none
    }

    public static func load() -> String? {
        read(shared: true) ?? read(shared: false)
    }

    private static func read(shared: Bool) -> String? {
        if shared, SharedConfig.keychainGroupID == nil, SharedConfig.appGroupID == nil { return nil }
        var q = baseQuery(shared: shared)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
            let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { return nil }
        return token
    }

    /// Moves a token saved in the login keychain (older builds) into the shared keychain,
    /// Returns the resulting location.
    @discardableResult
    public static func migrateToSharedIfNeeded() -> Location {
        guard SharedConfig.keychainGroupID != nil || SharedConfig.appGroupID != nil, read(shared: true) == nil,
            let token = read(shared: false)
        else {
            return location
        }
        var q = baseQuery(shared: true)
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemDelete(baseQuery(shared: false) as CFDictionary)
            log.notice("Token moved to the shared keychain")
        } else {
            log.notice("Shared keychain unavailable (status \(status)), token stays app-only")
        }
        return location
    }

    public static func save(_ token: String) throws {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        delete()
        var status = errSecMissingEntitlement
        if SharedConfig.keychainGroupID != nil || SharedConfig.appGroupID != nil {
            var q = baseQuery(shared: true)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(q as CFDictionary, nil)
        }
        if status == errSecMissingEntitlement {
            log.notice("Shared keychain unavailable, using login keychain")
            var q = baseQuery(shared: false)
            q[kSecValueData as String] = data
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TokenError.keychain(status) }
    }

    public static func delete() {
        for shared in [true, false] {
            SecItemDelete(baseQuery(shared: shared) as CFDictionary)
        }
    }
}

