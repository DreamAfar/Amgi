public import Foundation
import Security

public enum KeychainHelper: Sendable {
    private static let service = "com.ankiapp.sync"
    private static let hostKeyAccountBase = "sync-host-key"
    private static let usernameAccountBase = "sync-username"
    private static let endpointAccountBase = "sync-endpoint"
    private static let currentEndpointAccountBase = "sync-current-endpoint"
    private static let reviewSelectionAIAPIKeyAccountBase = "review-selection-ai-api-key"

    // MARK: - Host Key

    public static func saveHostKey(_ key: String) throws {
        try save(account: scopedAccount(hostKeyAccountBase), value: key)
    }

    public static func saveHostKey(_ key: String, for user: String) throws {
        try save(account: scopedAccount(hostKeyAccountBase, user: user), value: key)
    }

    public static func loadHostKey() -> String? {
        load(account: scopedAccount(hostKeyAccountBase))
    }

    public static func loadHostKey(for user: String) -> String? {
        load(account: scopedAccount(hostKeyAccountBase, user: user))
    }

    public static func deleteHostKey() {
        delete(account: scopedAccount(hostKeyAccountBase))
    }

    public static func deleteHostKey(for user: String) {
        delete(account: scopedAccount(hostKeyAccountBase, user: user))
    }

    // MARK: - Username

    public static func saveUsername(_ username: String) throws {
        try save(account: scopedAccount(usernameAccountBase), value: username)
    }

    public static func saveUsername(_ username: String, for user: String) throws {
        try save(account: scopedAccount(usernameAccountBase, user: user), value: username)
    }

    public static func loadUsername() -> String? {
        load(account: scopedAccount(usernameAccountBase))
    }

    public static func loadUsername(for user: String) -> String? {
        load(account: scopedAccount(usernameAccountBase, user: user))
    }

    public static func deleteUsername() {
        delete(account: scopedAccount(usernameAccountBase))
    }

    public static func deleteUsername(for user: String) {
        delete(account: scopedAccount(usernameAccountBase, user: user))
    }

    // MARK: - Endpoint

    public static func saveEndpoint(_ url: String) throws {
        try save(account: scopedAccount(endpointAccountBase), value: url)
    }

    public static func saveEndpoint(_ url: String, for user: String) throws {
        try save(account: scopedAccount(endpointAccountBase, user: user), value: url)
    }

    public static func loadEndpoint() -> String? {
        load(account: scopedAccount(endpointAccountBase))
    }

    public static func loadEndpoint(for user: String) -> String? {
        load(account: scopedAccount(endpointAccountBase, user: user))
    }

    public static func deleteEndpoint() {
        delete(account: scopedAccount(endpointAccountBase))
    }

    public static func deleteEndpoint(for user: String) {
        delete(account: scopedAccount(endpointAccountBase, user: user))
    }

    // MARK: - Current Endpoint

    public static func saveCurrentEndpoint(_ url: String) throws {
        try save(account: scopedAccount(currentEndpointAccountBase), value: url)
    }

    public static func saveCurrentEndpoint(_ url: String, for user: String) throws {
        try save(account: scopedAccount(currentEndpointAccountBase, user: user), value: url)
    }

    public static func loadCurrentEndpoint() -> String? {
        load(account: scopedAccount(currentEndpointAccountBase))
    }

    public static func loadCurrentEndpoint(for user: String) -> String? {
        load(account: scopedAccount(currentEndpointAccountBase, user: user))
    }

    public static func deleteCurrentEndpoint() {
        delete(account: scopedAccount(currentEndpointAccountBase))
    }

    public static func deleteCurrentEndpoint(for user: String) {
        delete(account: scopedAccount(currentEndpointAccountBase, user: user))
    }

    // MARK: - Review Selection AI API Key

    public static func saveReviewSelectionAIAPIKey(_ key: String) throws {
        try save(account: scopedAccount(reviewSelectionAIAPIKeyAccountBase), value: key)
    }

    public static func loadReviewSelectionAIAPIKey() -> String? {
        load(account: scopedAccount(reviewSelectionAIAPIKeyAccountBase))
    }

    public static func deleteReviewSelectionAIAPIKey() {
        delete(account: scopedAccount(reviewSelectionAIAPIKeyAccountBase))
    }

    public static func deleteAllSyncCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func scopedAccount(_ base: String) -> String {
        "\(base).\(currentProfileID())"
    }

    private static func scopedAccount(_ base: String, user: String) -> String {
        "\(base).\(profileID(for: user))"
    }

    private static func currentProfileID() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        return profileID(for: selectedUser)
    }

    private static func profileID(for user: String) -> String {
        let selectedUser = user
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
