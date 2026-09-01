/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// KeychainService.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation
import CryptoKit
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
    private let service = "com.magpieapp.vaultgo"

    private static func resolveAccessGroup() -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VaultGoKeychainAccessGroup") as? String,
           !value.isEmpty {
            return value
        }
        if let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
           !prefix.isEmpty {
            return prefix + "com.magpieapp.vaultgo.shared"
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
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        
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
        
        if let encryptionService = encryptionService as? EncryptionService {
            encryptionService.setEncryptionKey(keys.dataEncryptionKey)
        }
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
    
    func changeMasterPassword(from oldPassword: String, to newPassword: String) throws {
        let salt = try keyDerivationService.generateSalt()
        let oldSalt = try keychainService.retrieveKey(for: saltIdentifier)
        let oldMasterKey = try keyDerivationService.deriveMasterKey(from: oldPassword, salt: oldSalt)
        let oldKeys = try keyDerivationService.deriveSubKeys(from: oldMasterKey)
        
        let encryptedDekData = try keychainService.retrieveKey(for: encryptedMasterKeyIdentifier)
        let encryptedDek = try EncryptedData.fromCombined(encryptedDekData)
        let dekData = try encryptionService.decrypt(encryptedDek, using: oldKeys.keyEncryptionKey)
        
        let newMasterKey = try keyDerivationService.deriveMasterKey(from: newPassword, salt: salt)
        let newKeys = try keyDerivationService.deriveSubKeys(from: newMasterKey)
        
        let newEncryptedDek = try encryptionService.encrypt(dekData, using: newKeys.keyEncryptionKey)
        
        try keychainService.storeKey(salt, for: saltIdentifier)
        try keychainService.storeKey(newEncryptedDek.combined, for: encryptedMasterKeyIdentifier)
        
        let dek = SymmetricKey(data: dekData)
        if let encryptionService = encryptionService as? EncryptionService {
            encryptionService.setEncryptionKey(dek)
        }
    }
}
