/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// PasswordVaultService.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation
import SwiftUI
import Combine

@MainActor
class PasswordVaultService: ObservableObject {
    @Published var passwords: [PasswordEntry] = []
    @Published var trashedPasswords: [PasswordEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let repository: PasswordRepositoryProtocol
    private let encryptionService: EncryptionServiceProtocol
    private let keychainService: KeychainServiceProtocol

    init(
        repository: PasswordRepositoryProtocol = PasswordRepository(),
        encryptionService: EncryptionServiceProtocol = EncryptionService.shared,
        keychainService: KeychainServiceProtocol = KeychainService()
    ) {
        self.repository = repository
        self.encryptionService = encryptionService
        self.keychainService = keychainService
    }

    func loadPasswords() async {
        isLoading = true
        errorMessage = nil

        do {
            let entries = try await repository.fetchAll()
            self.passwords = entries.sorted { $0.siteName < $1.siteName }
        } catch {
            if case CryptoError.keyNotFound = error {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let entries = try await repository.fetchAll()
                    self.passwords = entries.sorted { $0.siteName < $1.siteName }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            } else {
                self.errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    func reloadAll() async {
        await loadPasswords()
    }

    func searchPasswords(_ query: String) async {
        guard !query.isEmpty else {
            await loadPasswords()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let entries = try await repository.search(query: query)
            self.passwords = entries.sorted { $0.siteName < $1.siteName }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func addPasswordOrThrow(_ entry: PasswordEntry) async throws {
        errorMessage = nil
        try await repository.save(entry)
        self.passwords.append(entry)
        self.passwords.sort { $0.siteName < $1.siteName }
    }

    func addPassword(_ entry: PasswordEntry) async {
        do {
            try await addPasswordOrThrow(entry)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func updatePassword(_ entry: PasswordEntry) async {
        do {
            try await repository.update(entry)
            if let index = self.passwords.firstIndex(where: { $0.id == entry.id }) {
                self.passwords[index] = entry
                self.passwords.sort { $0.siteName < $1.siteName }
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func deletePassword(_ id: UUID) async {
        // 软删除：将密码移入回收站，保留 30 天后由 purgeExpired 物理清理
        do {
            try await repository.softDelete(id)
            self.passwords.removeAll { $0.id == id }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 加载回收站中尚未过期的密码
    func loadTrashedPasswords() async {
        do {
            trashedPasswords = try await repository.fetchTrashed()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 物理清理超过保留期的密码，返回被删除的 ID 列表
    func purgeExpiredPasswords(retentionDays: Int = 30) async -> [UUID] {
        do {
            let purged = try await repository.purgeExpired(retentionDays: retentionDays)
            trashedPasswords.removeAll { purged.contains($0.id) }
            return purged
        } catch {
            self.errorMessage = error.localizedDescription
            return []
        }
    }

    /// 从回收站恢复密码（清除 deletedAt）
    func restorePassword(_ id: UUID) async {
        do {
            guard var entry = trashedPasswords.first(where: { $0.id == id }) else { return }
            entry.deletedAt = nil
            try await repository.update(entry)
            trashedPasswords.removeAll { $0.id == id }
            passwords.append(entry)
            passwords.sort { $0.siteName < $1.siteName }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 彻底物理删除单条密码（用于回收站中的"立即删除"）
    func permanentlyDeletePassword(_ id: UUID) async {
        do {
            try await repository.delete(id)
            trashedPasswords.removeAll { $0.id == id }
            passwords.removeAll { $0.id == id }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ id: UUID) async {
        if var entry = self.passwords.first(where: { $0.id == id }) {
            entry.isFavorite.toggle()
            entry.updatedAt = Date()
            await updatePassword(entry)
        }
    }

    func updateLastUsed(_ id: UUID) async {
        if var entry = self.passwords.first(where: { $0.id == id }) {
            entry.lastUsedAt = Date()
            await updatePassword(entry)
        }
    }
}

class PasswordGeneratorService: ObservableObject {
    @Published var generatedPassword: String = ""
    @Published var length: Double = 16
    @Published var includeUppercase: Bool = true
    @Published var includeLowercase: Bool = true
    @Published var includeNumbers: Bool = true
    @Published var includeSymbols: Bool = true

    private let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private let lowercase = "abcdefghijklmnopqrstuvwxyz"
    private let numbers = "0123456789"
    private let symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    init() {
        generatePassword()
    }

    func generatePassword() {
        var charset = ""

        if includeUppercase { charset += uppercase }
        if includeLowercase { charset += lowercase }
        if includeNumbers { charset += numbers }
        if includeSymbols { charset += symbols }

        if charset.isEmpty {
            charset = lowercase
            includeLowercase = true
        }

        var password = ""
        for _ in 0..<Int(length) {
            if let char = charset.randomElement() {
                password.append(char)
            }
        }

        self.generatedPassword = password
    }
}
