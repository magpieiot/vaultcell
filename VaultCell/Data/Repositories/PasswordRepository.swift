/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordRepository.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation
import CoreData

protocol PasswordRepositoryProtocol {
    func fetchAll() async throws -> [PasswordEntry]
    func fetch(by id: UUID) async throws -> PasswordEntry?
    func search(query: String) async throws -> [PasswordEntry]
    func save(_ entry: PasswordEntry) async throws
    func update(_ entry: PasswordEntry) async throws
    func delete(_ id: UUID) async throws
    /// 软删除：将条目标记为 deletedAt，保留 30 天后由 purgeExpired 物理删除
    func softDelete(_ id: UUID) async throws
    /// 获取回收站中尚未过期的条目（deletedAt != nil）
    func fetchTrashed() async throws -> [PasswordEntry]
    /// 物理删除已超过保留期（30 天）的条目，返回被删除的 ID 列表
    func purgeExpired(retentionDays: Int) async throws -> [UUID]
}

class PasswordRepository: PasswordRepositoryProtocol {
    private let dataSource: CoreDataDataSource
    
    init(dataSource: CoreDataDataSource = CoreDataDataSource(context: CoreDataStack.shared.newBackgroundContext())) {
        self.dataSource = dataSource
    }
    
    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchAll() async throws -> [PasswordEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllPasswords()
            var entries: [PasswordEntry] = []
            entries.reserveCapacity(cdEntries.count)

            var firstError: Error?
            for cdEntry in cdEntries {
                // 过滤软删除条目：deletedAt 非 nil 的视为回收站中
                guard cdEntry.deletedAt == nil else { continue }
                do {
                    entries.append(try self.dataSource.convertToPasswordEntry(cdEntry))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if entries.isEmpty, let firstError {
                throw firstError
            }
            return entries
        }
    }
    
    func fetch(by id: UUID) async throws -> PasswordEntry? {
        try await perform {
            if let cdEntry = try self.dataSource.fetchPassword(by: id) {
                return try self.dataSource.convertToPasswordEntry(cdEntry)
            }
            return nil
        }
    }
    
    func search(query: String) async throws -> [PasswordEntry] {
        try await perform {
            let cdEntries = try self.dataSource.searchPasswords(query: query)
            var entries: [PasswordEntry] = []
            entries.reserveCapacity(cdEntries.count)

            var firstError: Error?
            for cdEntry in cdEntries {
                do {
                    entries.append(try self.dataSource.convertToPasswordEntry(cdEntry))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if entries.isEmpty, let firstError {
                throw firstError
            }
            return entries
        }
    }
    
    func save(_ entry: PasswordEntry) async throws {
        try await perform {
            try self.dataSource.savePasswordEntry(entry)
        }
    }
    
    func update(_ entry: PasswordEntry) async throws {
        try await perform {
            try self.dataSource.savePasswordEntry(entry)
        }
    }
    
    func delete(_ id: UUID) async throws {
        try await perform {
            try self.dataSource.deletePasswordEntry(id)
        }
    }

    func softDelete(_ id: UUID) async throws {
        try await perform {
            guard let cdEntry = try self.dataSource.fetchPassword(by: id) else { return }
            cdEntry.deletedAt = Date()
            try self.dataSource.context.save()
        }
    }

    func fetchTrashed() async throws -> [PasswordEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllPasswords()
            var entries: [PasswordEntry] = []
            var firstError: Error?
            for cdEntry in cdEntries {
                guard cdEntry.deletedAt != nil else { continue }
                do {
                    entries.append(try self.dataSource.convertToPasswordEntry(cdEntry))
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if entries.isEmpty, let firstError { throw firstError }
            return entries
        }
    }

    func purgeExpired(retentionDays: Int) async throws -> [UUID] {
        try await perform {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
            let cdEntries = try self.dataSource.fetchAllPasswords()
            var purgedIDs: [UUID] = []
            for cdEntry in cdEntries {
                if let deletedAt = cdEntry.deletedAt, deletedAt < cutoff {
                    let id = cdEntry.id
                    self.dataSource.context.delete(cdEntry)
                    purgedIDs.append(id)
                }
            }
            if !purgedIDs.isEmpty {
                try self.dataSource.context.save()
            }
            return purgedIDs
        }
    }
}

protocol TwoFactorRepositoryProtocol {
    func fetchAll() async throws -> [TwoFactorConfig]
    func fetch(for passwordEntryId: UUID) async throws -> [TwoFactorConfig]
    func save(_ config: TwoFactorConfig, for passwordEntryId: UUID) async throws
    func delete(_ id: UUID) async throws
}

class TwoFactorRepository: TwoFactorRepositoryProtocol {
    private let dataSource: CoreDataDataSource
    
    init(dataSource: CoreDataDataSource = CoreDataDataSource(context: CoreDataStack.shared.newBackgroundContext())) {
        self.dataSource = dataSource
    }
    
    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchAll() async throws -> [TwoFactorConfig] {
        let entries = try await fetchAllPasswordEntries()
        let configs = entries.flatMap { $0.twoFactorConfigs ?? [] }
        return configs
    }
    
    private func fetchAllPasswordEntries() async throws -> [PasswordEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllPasswords()
            var entries: [PasswordEntry] = []
            entries.reserveCapacity(cdEntries.count)

            var firstError: Error?
            for cdEntry in cdEntries {
                do {
                    entries.append(try self.dataSource.convertToPasswordEntry(cdEntry))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if entries.isEmpty, let firstError {
                throw firstError
            }
            return entries
        }
    }
    
    func fetch(for passwordEntryId: UUID) async throws -> [TwoFactorConfig] {
        if let entry = try await fetchPasswordEntry(by: passwordEntryId) {
            return entry.twoFactorConfigs ?? []
        }
        return []
    }
    
    private func fetchPasswordEntry(by id: UUID) async throws -> PasswordEntry? {
        try await perform {
            if let cdEntry = try self.dataSource.fetchPassword(by: id) {
                return try self.dataSource.convertToPasswordEntry(cdEntry)
            }
            return nil
        }
    }
    
    func save(_ config: TwoFactorConfig, for passwordEntryId: UUID) async throws {
        if var entry = try await fetchPasswordEntry(by: passwordEntryId) {
            var configs = entry.twoFactorConfigs ?? []
            if let index = configs.firstIndex(where: { $0.id == config.id }) {
                configs[index] = config
            } else {
                configs.append(config)
            }
            entry.twoFactorConfigs = configs
            entry.has2FA = true
            entry.updatedAt = Date()
            try await perform {
                try self.dataSource.savePasswordEntry(entry)
            }
        }
    }
    
    func delete(_ id: UUID) async throws {
    }
}
