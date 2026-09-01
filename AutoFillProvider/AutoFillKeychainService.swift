/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// AutoFillKeychainService.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation
import KeychainAccess

class AutoFillKeychainService {
    private let keychain: Keychain
    
    init() {
        #if CN
        let service = "com.magpieapp.vaultgo.cn"
        let accessGroup = "group.com.magpieapp.vaultgo.cn.shared"
        #else
        let service = "com.magpieapp.vaultgo"
        let accessGroup = "group.com.magpieapp.vaultgo.shared"
        #endif
        keychain = Keychain(service: service, accessGroup: accessGroup)
            .accessibility(.whenUnlockedThisDeviceOnly)
    }
    
    func saveCredential(_ credential: CredentialItem) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credential)
        try keychain.set(data, key: credential.id.uuidString)
    }
    
    func getCredential(by id: UUID) throws -> CredentialItem? {
        guard let data = try keychain.getData(id.uuidString) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(CredentialItem.self, from: data)
    }
    
    func deleteCredential(by id: UUID) throws {
        try keychain.remove(id.uuidString)
    }
    
    func getAllCredentials() throws -> [CredentialItem] {
        let allKeys = keychain.allKeys()
        var credentials: [CredentialItem] = []
        
        for key in allKeys {
            if let data = try keychain.getData(key),
               let credential = try? JSONDecoder().decode(CredentialItem.self, from: data) {
                credentials.append(credential)
            }
        }
        
        return credentials
    }
    
    func searchCredentials(matching query: String) throws -> [CredentialItem] {
        let allCredentials = try getAllCredentials()
        return allCredentials.filter { credential in
            credential.siteName.localizedCaseInsensitiveContains(query) ||
            credential.username.localizedCaseInsensitiveContains(query) ||
            credential.siteURL.localizedCaseInsensitiveContains(query)
        }
    }
}
