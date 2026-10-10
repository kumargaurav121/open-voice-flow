import Core
import Foundation
import Observation
import Security

/// The user's own API keys, kept in the macOS Keychain (never in preferences or logs). Which keys exist is
/// cached, so dictation and the menu don't touch the Keychain; the key itself is read only when a request
/// is sent.
@MainActor
@Observable
public final class APIKeys {
    /// Every cloud service with a key: the one table of names and environment variables.
    public enum Account: String, CaseIterable, Sendable {
        case deepgram, openAI, groq

        public var displayName: String {
            switch self {
            case .deepgram: "Deepgram"
            case .openAI: "OpenAI"
            case .groq: "Groq"
            }
        }

        /// Where command-line tools (the eval runner) read the key; never a command-line argument.
        public var environmentVariable: String {
            switch self {
            case .deepgram: "DEEPGRAM_API_KEY"
            case .openAI: "OPENAI_API_KEY"
            case .groq: "GROQ_API_KEY"
            }
        }
    }

    public struct Failure: LocalizedError, LogSafeError {
        public let status: OSStatus
        public var errorDescription: String? {
            "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")"
        }
        public var logDescription: String { "Keychain error \(status)" }
    }

    public let service: String
    private(set) var saved: Set<Account> = []

    public init(service: String = "dev.openvoiceflow.api-keys") {
        self.service = service
        saved = Set(Account.allCases.filter { (try? read($0)) != nil })
    }

    /// The saved key, or nil if there's none. Throws if the Keychain refuses (e.g. access denied).
    public func key(for account: Account) throws -> String? {
        try read(account)
    }

    public func hasKey(for account: Account) -> Bool { saved.contains(account) }

    /// Saves (or replaces) a key; a blank one removes the saved key.
    public func save(_ key: String, for account: Account) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return try remove(account) }
        let data = Data(key.utf8)
        let update = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = baseQuery(account)
            item[kSecValueData] = data
            // In the login keychain, not synced to other devices via iCloud.
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrLabel] = "Open Voice Flow: \(account.displayName) API key"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if update != errSecSuccess {
            throw Failure(status: update)
        }
        saved.insert(account)
    }

    public func remove(_ account: Account) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
        saved.remove(account)
    }

    private func read(_ account: Account) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    private func baseQuery(_ account: Account) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account.rawValue]
    }
}
