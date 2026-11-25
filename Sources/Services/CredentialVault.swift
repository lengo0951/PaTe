import Foundation
import CryptoKit
import Security

/// Ultra-fast, zero-prompt native credential vault using macOS Keychain + Hardware AES-256-GCM.
/// Secrets are encrypted individually with a 256-bit SymmetricKey and never stored in plaintext JSON.
@MainActor
public final class CredentialVault {
    public static let shared = CredentialVault()
    
    private let keychainService = "com.coolstar.PasteFlow.VaultMaster"
    private let keychainAccount = "master-key-v1"
    
    private let vaultFileURL: URL
    private let fallbackKeyURL: URL
    private let masterKey: SymmetricKey
    private var encryptedBlobs: [String: String] = [:] // itemID -> base64(AES.GCM combined)
    
    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PasteFlow", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.vaultFileURL = dir.appendingPathComponent("vault.enc.json")
        self.fallbackKeyURL = dir.appendingPathComponent(".vault_master.key")
        self.masterKey = Self.loadOrCreateMasterKey(
            service: keychainService,
            account: keychainAccount,
            fallbackURL: fallbackKeyURL
        )
        loadVaultFile()
    }
    
    private static func loadOrCreateMasterKey(service: String, account: String, fallbackURL: URL) -> SymmetricKey {
        // 1. Prefer user-only (0600) local keyfile synchronized with Keychain to avoid ad-hoc rebuild prompts
        if let keyData = try? Data(contentsOf: fallbackURL), keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }
        
        // 2. Check macOS Keychain if migrating
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            persistRestrictedKeyFile(data: data, to: fallbackURL)
            return SymmetricKey(data: data)
        }
        
        // 3. Generate fresh 256-bit cryptographically secure SymmetricKey
        let newKey = SymmetricKey(size: .bits256)
        let rawData = newKey.withUnsafeBytes { Data($0) }
        
        // Store in Keychain (best-effort) + 0600 restricted user file
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: rawData
        ]
        SecItemDelete(addQuery as CFDictionary)
        _ = SecItemAdd(addQuery as CFDictionary, nil)
        persistRestrictedKeyFile(data: rawData, to: fallbackURL)
        
        return newKey
    }
    
    private static func persistRestrictedKeyFile(data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    
    public func setSecret(_ secret: String, for itemID: String) {
        guard let plainData = secret.data(using: .utf8),
              let sealedBox = try? AES.GCM.seal(plainData, using: masterKey),
              let combined = sealedBox.combined else {
            return
        }
        encryptedBlobs[itemID] = combined.base64EncodedString()
        saveVaultFile()
    }
    
    public func getSecret(for itemID: String) -> String? {
        guard let b64 = encryptedBlobs[itemID],
              let combined = Data(base64Encoded: b64),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let decrypted = try? AES.GCM.open(sealedBox, using: masterKey) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }
    
    public func removeSecret(for itemID: String) {
        if encryptedBlobs.removeValue(forKey: itemID) != nil {
            saveVaultFile()
        }
    }
    
    private func loadVaultFile() {
        guard FileManager.default.fileExists(atPath: vaultFileURL.path),
              let data = try? Data(contentsOf: vaultFileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        self.encryptedBlobs = decoded
    }
    
    private func saveVaultFile() {
        let snapshot = self.encryptedBlobs
        let url = self.vaultFileURL
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
    }
}
