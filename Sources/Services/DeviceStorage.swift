import Foundation
import Security

struct SavedTV: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: UInt16
}

struct Shortcut: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var link: String
}

/// Piccolo wrapper del Keychain (password generiche, accessibili solo da questo dispositivo).
enum Keychain {
    private static let service = "it.example.xiaomiremote"

    static func set(_ data: Data, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Dati locali: elenco TV e preferenze in UserDefaults; impronta del certificato
/// della TV (pinning) nel Keychain. Nessun dato lascia il dispositivo.
final class DeviceStorage: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadTVs() -> [SavedTV] { decode("tvs") ?? [] }
    func saveTVs(_ tvs: [SavedTV]) { encode(tvs, key: "tvs") }

    var selectedID: UUID? {
        get { defaults.string(forKey: "selectedTV").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "selectedTV") }
    }

    var hapticsEnabled: Bool {
        get { defaults.object(forKey: "haptics") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "haptics") }
    }

    var testMode: Bool {
        get { defaults.bool(forKey: "testMode") }
        set { defaults.set(newValue, forKey: "testMode") }
    }

    func loadShortcuts() -> [Shortcut] { decode("shortcuts") ?? [] }
    func saveShortcuts(_ list: [Shortcut]) { encode(list, key: "shortcuts") }

    func pin(for id: UUID) -> Data? { Keychain.get(account: "pin.\(id.uuidString)") }
    func savePin(_ data: Data, for id: UUID) { Keychain.set(data, account: "pin.\(id.uuidString)") }
    func deletePin(for id: UUID) { Keychain.delete(account: "pin.\(id.uuidString)") }

    private func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
