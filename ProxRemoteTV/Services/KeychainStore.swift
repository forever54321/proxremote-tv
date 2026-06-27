import Foundation
import Security
import CryptoKit

/// Generic Keychain blob store for tvOS. Items are device-only and
/// after-first-unlock — never synced to iCloud, never in backups restored to
/// another device. Used for the paired-server profiles (which include the
/// Proxmox password) and the TOFU TLS pins.
enum KeychainStore {
    static let service = "com.proxremote.tv"

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainStore] save failed for \(account): \(status)")
        }
        return status == errSecSuccess
    }

    static func load(account: String) -> Data? {
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
        return data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Trust-on-first-use TLS pin store, mirroring the iOS app's TofuPinStore.
/// On first connect to a host:port we record the leaf cert's SHA-256
/// fingerprint; subsequent connects must match or the connection is treated
/// as MITM and rejected. Backed by the Keychain (device-only).
final class TofuPinStore {
    static let shared = TofuPinStore()
    private init() { load() }

    private let account = "tofu_pins"
    private var pins: [String: String] = [:]   // "host:port" → sha256 hex
    private let lock = NSLock()

    private func load() {
        guard let data = KeychainStore.load(account: account),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        pins = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pins) {
            KeychainStore.save(data, account: account)
        }
    }

    /// TOFU verdict for a self-signed leaf cert. Records the pin on first
    /// sight, requires a match thereafter.
    func acceptOrPin(certificate: SecCertificate, host: String, port: Int) -> Bool {
        let der = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        let key = "\(host):\(port)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = pins[key] {
            return existing == fingerprint
        }
        pins[key] = fingerprint
        persist()
        return true
    }

    /// Drop the pin for a host:port (e.g. when the user knowingly rotates a cert).
    func forget(host: String, port: Int) {
        lock.lock()
        pins.removeValue(forKey: "\(host):\(port)")
        persist()
        lock.unlock()
    }
}
