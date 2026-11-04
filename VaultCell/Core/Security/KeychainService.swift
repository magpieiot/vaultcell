/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// KeychainService.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation
import CryptoKit
import LocalAuthentication
import Security

enum KeychainError: Error, LocalizedError {
    case storeFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case keyNotFound
    case invalidData
    case serializationFailed
    case deserializationFailed
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Store failed: \(status)"
        case .retrieveFailed(let status):
            return "Retrieve failed: \(status)"
        case .deleteFailed(let status):
            return "Delete failed: \(status)"
        case .keyNotFound:
            return "Key not found"
        case .invalidData:
            return "Invalid data"
        case .serializationFailed:
            return "Serialization failed"
        case .deserializationFailed:
            return "Deserialization failed"
        }
    }
}

protocol KeychainServiceProtocol {
    func storeKey(_ key: Data, for identifier: String) throws
    func storeKey(_ key: Data, for identifier: String, requiresUserPresence: Bool) throws
    func retrieveKey(for identifier: String) throws -> Data
    func deleteKey(for identifier: String) throws
    func store<T: Codable>(_ value: T, for identifier: String) throws
    func retrieve<T: Codable>(_ type: T.Type, for identifier: String) throws -> T
    func exists(for identifier: String) throws -> Bool
}

class KeychainService: KeychainServiceProtocol {
    private let service = "com.magpie.vaultcell"

    private static func resolveAccessGroup() -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VaultCellKeychainAccessGroup") as? String,
           !value.isEmpty {
            return value
        }
        if let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
           !prefix.isEmpty {
            return prefix + "com.magpie.vaultcell.shared"
        }
        return nil
    }

    private let accessGroup: String? = resolveAccessGroup()
    
    private func baseQuery(for identifier: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
    
    func storeKey(_ key: Data, for identifier: String) throws {
        try storeKey(key, for: identifier, requiresUserPresence: false)
    }

    func storeKey(_ key: Data, for identifier: String, requiresUserPresence: Bool) throws {
        var query = baseQuery(for: identifier)

        var addAttributes: [String: Any] = [
            kSecValueData as String: key
        ]

        if requiresUserPresence, #available(iOS 13.0, *) {
            if let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                nil
            ) {
                addAttributes[kSecAttrAccessControl as String] = accessControl
            }
        }

        if addAttributes[kSecAttrAccessControl as String] == nil {
            addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        SecItemDelete(query as CFDictionary)

        query.merge(addAttributes) { (_, new) in new }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status: status)
        }
    }
    
    func retrieveKey(for identifier: String) throws -> Data {
        var query = baseQuery(for: identifier)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.keyNotFound
            }
            throw KeychainError.retrieveFailed(status: status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    func deleteKey(for identifier: String) throws {
        let query = baseQuery(for: identifier)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
    
    func store<T: Codable>(_ value: T, for identifier: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        try storeKey(data, for: identifier, requiresUserPresence: false)
    }
    
    func retrieve<T: Codable>(_ type: T.Type, for identifier: String) throws -> T {
        let data = try retrieveKey(for: identifier)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    func exists(for identifier: String) throws -> Bool {
        var query = baseQuery(for: identifier)
        query[kSecReturnData as String] = kCFBooleanFalse
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // kSecUseAuthenticationUI/kSecUseAuthenticationUIFail 自 iOS 14 废弃：
        // 改传 interactionNotAllowed 的 LAContext，语义不变——存在性检查绝不弹认证 UI，
        // 条目存在但需要认证时返回 errSecInteractionNotAllowed（下方按"存在"处理）
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            return false
        }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return true
        }
        throw KeychainError.retrieveFailed(status: status)
    }
    
    func clearAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

class AppLockService {
    private let keychainService: KeychainServiceProtocol
    private let encryptionService: EncryptionServiceProtocol
    private let keyDerivationService: KeyDerivationServiceProtocol
    
    private let saltIdentifier = VaultKey.salt
    private let encryptedMasterKeyIdentifier = VaultKey.encryptedMasterKey
    private let biometricDekIdentifier = VaultKey.biometricDek
    private let hasVaultIdentifier = VaultKey.hasVault
    
    init(
        keychainService: KeychainServiceProtocol = KeychainService(),
        encryptionService: EncryptionServiceProtocol = EncryptionService.shared,
        keyDerivationService: KeyDerivationServiceProtocol = KeyDerivationService()
    ) {
        self.keychainService = keychainService
        self.encryptionService = encryptionService
        self.keyDerivationService = keyDerivationService
    }
    
    func hasExistingVault() -> Bool {
        print("@@@DEBUG: AppLockService.hasExistingVault")

        let userDefaultsMarkerExists: Bool
        if let value = UserDefaults.standard.object(forKey: VaultKey.vaultInstalledMarker) as? Bool {
            userDefaultsMarkerExists = value
        } else {
            userDefaultsMarkerExists = false
        }

        let keychainHasVault: Bool
        do {
            keychainHasVault = try keychainService.exists(for: hasVaultIdentifier)
        } catch {
            print("@@@DEBUG: AppLockService.hasExistingVault error: \(error)")
            return false
        }

        if keychainHasVault && !userDefaultsMarkerExists {
            print("@@@DEBUG: AppLockService.hasExistingVault - reinstall detected, clearing orphaned keychain data")
            try? clearVaultKeychainData()
            return false
        }

        return keychainHasVault && userDefaultsMarkerExists
    }

    private func clearVaultKeychainData() throws {
        try? keychainService.deleteKey(for: saltIdentifier)
        try? keychainService.deleteKey(for: encryptedMasterKeyIdentifier)
        try? keychainService.deleteKey(for: biometricDekIdentifier)
        try? keychainService.deleteKey(for: hasVaultIdentifier)
        UserDefaults.standard.removeObject(forKey: VaultKey.pendingCloudRestoreDownload)
        UserDefaults.standard.removeObject(forKey: VaultKey.iCloudSyncEnabled)
    }
    
    func createVault(with masterPassword: String) throws {
        print("@@@DEBUG: AppLockService.createVault")
        
        let salt = try keyDerivationService.generateSalt()
        let masterKey = try keyDerivationService.deriveMasterKey(from: masterPassword, salt: salt)
        let keys = try keyDerivationService.deriveSubKeys(from: masterKey)
        
        let wrappedDek = try encryptionService.encrypt(
            keys.dataEncryptionKey.withUnsafeBytes { Data($0) },
            using: keys.keyEncryptionKey
        )
        
        try keychainService.storeKey(salt, for: saltIdentifier, requiresUserPresence: false)
        try keychainService.storeKey(wrappedDek.combined, for: encryptedMasterKeyIdentifier, requiresUserPresence: false)
        try keychainService.storeKey(keys.dataEncryptionKey.withUnsafeBytes { Data($0) }, for: biometricDekIdentifier, requiresUserPresence: true)
        try keychainService.store(true, for: hasVaultIdentifier)

        UserDefaults.standard.set(true, forKey: VaultKey.vaultInstalledMarker)
        UserDefaults.standard.set(UUID().uuidString, forKey: VaultKey.vaultID)
        UserDefaults.standard.set(1, forKey: VaultKey.cloudKeyRevision)
        UserDefaults.standard.removeObject(forKey: VaultKey.pendingCloudRestoreDownload)
        
        if let encryptionService = encryptionService as? EncryptionService {
            encryptionService.setEncryptionKey(keys.dataEncryptionKey)
        }
    }

    var vaultID: UUID {
        if let raw = UserDefaults.standard.string(forKey: VaultKey.vaultID),
           let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: VaultKey.vaultID)
        return id
    }

    func exportCloudKeyMaterial() throws -> CloudVaultKeyMaterial {
        let salt = try keychainService.retrieveKey(for: saltIdentifier)
        let id = vaultID
        let revision = max(1, UserDefaults.standard.integer(forKey: VaultKey.cloudKeyRevision))
        return CloudVaultKeyMaterial(
            vaultID: id,
            salt: salt,
            wrappedDEK: try keychainService.retrieveKey(for: encryptedMasterKeyIdentifier),
            kdfAlgorithm: CloudVaultKeyMaterial.currentKDF,
            kdfIterations: KeyDerivationService.pbkdf2Iterations,
            wrapAlgorithm: CloudVaultKeyMaterial.currentWrap,
            revision: Int64(revision)
        )
    }

    /// 新设备只安装包裹材料，随后仍必须由用户输入原主密码完成真正解锁。
    func importCloudKeyMaterial(_ material: CloudVaultKeyMaterial) throws {
        guard material.kdfAlgorithm == CloudVaultKeyMaterial.currentKDF,
              material.kdfIterations == KeyDerivationService.pbkdf2Iterations,
              material.wrapAlgorithm == CloudVaultKeyMaterial.currentWrap,
              material.salt.count == KeyDerivationService.saltSize else {
            throw CloudSyncError.vaultMismatch
        }
        try keychainService.storeKey(material.salt, for: saltIdentifier, requiresUserPresence: false)
        try keychainService.storeKey(
            material.wrappedDEK,
            for: encryptedMasterKeyIdentifier,
            requiresUserPresence: false
        )
        try keychainService.store(true, for: hasVaultIdentifier)
        UserDefaults.standard.set(material.vaultID.uuidString, forKey: VaultKey.vaultID)
        UserDefaults.standard.set(Int(material.revision), forKey: VaultKey.cloudKeyRevision)
        UserDefaults.standard.set(true, forKey: VaultKey.vaultInstalledMarker)
        UserDefaults.standard.set(true, forKey: VaultKey.pendingCloudRestoreDownload)
    }
    
    func unlockVault(with masterPassword: String) throws {
        let salt = try keychainService.retrieveKey(for: saltIdentifier)
        let masterKey = try keyDerivationService.deriveMasterKey(from: masterPassword, salt: salt)
        let keys = try keyDerivationService.deriveSubKeys(from: masterKey)
        
        let encryptedDekData = try keychainService.retrieveKey(for: encryptedMasterKeyIdentifier)
        let encryptedDek = try EncryptedData.fromCombined(encryptedDekData)
        let dekData = try encryptionService.decrypt(encryptedDek, using: keys.keyEncryptionKey)
        let dek = SymmetricKey(data: dekData)
        
        if let encryptionService = encryptionService as? EncryptionService {
            encryptionService.setEncryptionKey(dek)
        }
        try? keychainService.storeKey(dekData, for: biometricDekIdentifier, requiresUserPresence: true)
    }

    func unlockWithBiometrics() throws {
        let dekData = try keychainService.retrieveKey(for: biometricDekIdentifier)
        let dek = SymmetricKey(data: dekData)
        if let encryptionService = encryptionService as? EncryptionService {
            encryptionService.setEncryptionKey(dek)
        }
    }
    
    /// 修改主密码：用新密码派生的 KEK 重新包裹 DEK
    ///
    /// 顺序要点：先解出 DEK 并校验旧密码，再生成新盐与新密文，最后成对写入。
    /// 两个 Keychain 条目（盐 / 包裹后的 DEK）必须同时更新，任一写入失败都会
    /// 让旧密码再也解不开 DEK，因此写入失败时回滚到改动前的两份数据。
    func changeMasterPassword(from oldPassword: String, to newPassword: String) throws {
        let oldSalt = try keychainService.retrieveKey(for: saltIdentifier)
        let oldEncryptedDekData = try keychainService.retrieveKey(for: encryptedMasterKeyIdentifier)

        let oldMasterKey = try keyDerivationService.deriveMasterKey(from: oldPassword, salt: oldSalt)
        let oldKeys = try keyDerivationService.deriveSubKeys(from: oldMasterKey)

        let encryptedDek = try EncryptedData.fromCombined(oldEncryptedDekData)
        // 旧密码不对时 AES-GCM 认证失败在此抛出，此时尚未写入任何数据
        let dekData = try encryptionService.decrypt(encryptedDek, using: oldKeys.keyEncryptionKey)

        let newSalt = try keyDerivationService.generateSalt()
        let newMasterKey = try keyDerivationService.deriveMasterKey(from: newPassword, salt: newSalt)
        let newKeys = try keyDerivationService.deriveSubKeys(from: newMasterKey)
        let newEncryptedDek = try encryptionService.encrypt(dekData, using: newKeys.keyEncryptionKey)

        do {
            try keychainService.storeKey(newSalt, for: saltIdentifier, requiresUserPresence: false)
            try keychainService.storeKey(
                newEncryptedDek.combined,
                for: encryptedMasterKeyIdentifier,
                requiresUserPresence: false
            )
        } catch {
            try? keychainService.storeKey(oldSalt, for: saltIdentifier, requiresUserPresence: false)
            try? keychainService.storeKey(
                oldEncryptedDekData,
                for: encryptedMasterKeyIdentifier,
                requiresUserPresence: false
            )
            throw error
        }

        let previousRevision = UserDefaults.standard.integer(forKey: VaultKey.cloudKeyRevision)
        UserDefaults.standard.set(max(1, previousRevision) + 1, forKey: VaultKey.cloudKeyRevision)

        let dek = SymmetricKey(data: dekData)
        if let encryptionService = encryptionService as? EncryptionService {
            encryptionService.setEncryptionKey(dek)
        }
    }
}
