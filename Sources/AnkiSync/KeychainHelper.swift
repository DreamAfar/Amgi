public import Foundation
import Security

public enum KeychainHelper: Sendable {
    private static let service = "com.ankiapp.sync"
    private static let hostKeyAccountBase = "sync-host-key"
    private static let usernameAccountBase = "sync-username"
    private static let endpointAccountBase = "sync-endpoint"

    // MARK: - Host Key

    public static func saveHostKey(_ key: String) throws {
        try save(account: scopedAccount(hostKeyAccountBase), value: key)
    }

    public static func loadHostKey() -> String? {
        load(account: scopedAccount(hostKeyAccountBase))
    }

    public static func deleteHostKey() {
        delete(account: scopedAccount(hostKeyAccountBase))
    }

    // MARK: - Username

    public static func saveUsername(_ username: String) throws {
        try save(account: scopedAccount(usernameAccountBase), value: username)
    }

    public static func loadUsername() -> String? {
        load(account: scopedAccount(usernameAccountBase))
    }

    public static func deleteUsername() {
        delete(account: scopedAccount(usernameAccountBase))
    }

    // MARK: - Endpoint

    public static func saveEndpoint(_ url: String) throws {
        try save(account: scopedAccount(endpointAccountBase), value: url)
    }

    public static func loadEndpoint() -> String? {
        load(account: scopedAccount(endpointAccountBase))
    }

    public static func deleteEndpoint() {
        delete(account: scopedAccount(endpointAccountBase))
    }

    private static func scopedAccount(_ base: String) -> String {
        "\(base).\(currentProfileID())"
    }

    private static func currentProfileID() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = selectedUser.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let profile = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return profile.isEmpty ? "default" : profile
    }

    // MARK: - Internal

    private static func save(account: String, value: String) throws {
        let data = Data(value.utf8)
        // Delete existing item first to avoid duplicates
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error, Sendable {
    case saveFailed(OSStatus)
}
