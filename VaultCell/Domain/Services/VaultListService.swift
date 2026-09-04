/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultListService.swift
/// created on: 2026-06-01 10:00:00
/// ------------------------------------------------------------------

import Foundation

protocol VaultListServiceProtocol {
    func loadAll() async throws -> [VaultItem]
    func searchAll(query: String) async throws -> [VaultItem]
    /// 软删除：将条目移入回收站，保留 30 天后由 purgeExpired 物理清理
    func delete(_ item: VaultItem) async throws
    func toggleFavorite(_ item: VaultItem) async throws
    func updatePassword(_ entry: PasswordEntry) async throws
    func updatePincode(_ entry: PincodeEntry) async throws
    func updateBankcard(_ entry: BankcardEntry) async throws
    /// 加载回收站中尚未过期的条目
    func loadTrashed() async throws -> [VaultItem]
    /// 物理清理超过保留期的条目，返回被删除的 ID 列表
    func purgeExpired(retentionDays: Int) async throws -> [UUID]
    /// 从回收站恢复条目（清除 deletedAt）
    func restore(_ item: VaultItem) async throws
    /// 彻底物理删除单条（用于回收站中的"立即删除"）
    func permanentlyDelete(_ item: VaultItem) async throws
}

final class VaultListService: VaultListServiceProtocol {
    private let passwordRepository: PasswordRepositoryProtocol
    private let pincodeRepository: PincodeRepositoryProtocol
    private let bankcardRepository: BankcardRepositoryProtocol

    init(
        passwordRepository: PasswordRepositoryProtocol = PasswordRepository(),
        pincodeRepository: PincodeRepositoryProtocol = PincodeRepository(),
        bankcardRepository: BankcardRepositoryProtocol = BankcardRepository()
    ) {
        self.passwordRepository = passwordRepository
        self.pincodeRepository = pincodeRepository
        self.bankcardRepository = bankcardRepository
    }

    func loadAll() async throws -> [VaultItem] {
        async let passwords = passwordRepository.fetchAll()
        async let pincodes = pincodeRepository.fetchAll()
        async let bankcards = bankcardRepository.fetchAll()

        return try await mergeAndSort(
            passwords: passwords,
            pincodes: pincodes,
            bankcards: bankcards
        )
    }

    func searchAll(query: String) async throws -> [VaultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await loadAll()
        }

        async let passwords = passwordRepository.search(query: trimmed)
        async let pincodes = pincodeRepository.search(query: trimmed)
        async let bankcards = bankcardRepository.search(query: trimmed)

        return try await mergeAndSort(
            passwords: passwords,
            pincodes: pincodes,
            bankcards: bankcards
        )
    }

    func delete(_ item: VaultItem) async throws {
        // 软删除：仅标记 deletedAt，不物理删除，保留 30 天供恢复
        switch item {
        case let .password(entry):
            try await passwordRepository.softDelete(entry.id)
        case let .pincode(entry):
            try await pincodeRepository.softDelete(entry.id)
        case let .bankcard(entry):
            try await bankcardRepository.softDelete(entry.id)
        }
    }

    func toggleFavorite(_ item: VaultItem) async throws {
        let now = Date()

        switch item {
        case var .password(entry):
            entry.isFavorite.toggle()
            entry.updatedAt = now
            entry.isSynced = false
            try await passwordRepository.update(entry)
        case var .pincode(entry):
            entry.isFavorite.toggle()
            entry.updatedAt = now
            entry.isSynced = false
            try await pincodeRepository.update(entry)
        case var .bankcard(entry):
            entry.isFavorite.toggle()
            entry.updatedAt = now
            entry.isSynced = false
            try await bankcardRepository.update(entry)
        }
    }

    func updatePassword(_ entry: PasswordEntry) async throws {
        var mutableEntry = entry
        mutableEntry.isSynced = false
        try await passwordRepository.update(mutableEntry)
    }

    func updatePincode(_ entry: PincodeEntry) async throws {
        var mutableEntry = entry
        mutableEntry.isSynced = false
        try await pincodeRepository.update(mutableEntry)
    }

    func updateBankcard(_ entry: BankcardEntry) async throws {
        var mutableEntry = entry
        mutableEntry.isSynced = false
        try await bankcardRepository.update(mutableEntry)
    }

    private func mergeAndSort(
        passwords: [PasswordEntry],
        pincodes: [PincodeEntry],
        bankcards: [BankcardEntry]
    ) -> [VaultItem] {
        let items =
            passwords.map(VaultItem.password) +
            pincodes.map(VaultItem.pincode) +
            bankcards.map(VaultItem.bankcard)

        return items.sorted(by: defaultSort)
    }

    private func defaultSort(lhs: VaultItem, rhs: VaultItem) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }

        if lhs.displayDate != rhs.displayDate {
            return lhs.displayDate > rhs.displayDate
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    func loadTrashed() async throws -> [VaultItem] {
        async let passwords = passwordRepository.fetchTrashed()
        async let pincodes = pincodeRepository.fetchTrashed()
        async let bankcards = bankcardRepository.fetchTrashed()

        let trashedPasswords = try await passwords.map(VaultItem.password)
        let trashedPincodes = try await pincodes.map(VaultItem.pincode)
        let trashedBankcards = try await bankcards.map(VaultItem.bankcard)

        // 回收站按删除时间降序排列（最近删除的在前）
        let allItems = trashedPasswords + trashedPincodes + trashedBankcards
        return allItems.sorted { lhs, rhs in
            (lhs.deletedDate ?? .distantPast) > (rhs.deletedDate ?? .distantPast)
        }
    }

    func purgeExpired(retentionDays: Int = 30) async throws -> [UUID] {
        var purged: [UUID] = []
        purged += try await passwordRepository.purgeExpired(retentionDays: retentionDays)
        purged += try await pincodeRepository.purgeExpired(retentionDays: retentionDays)
        purged += try await bankcardRepository.purgeExpired(retentionDays: retentionDays)
        return purged
    }

    func restore(_ item: VaultItem) async throws {
        switch item {
        case var .password(entry):
            entry.deletedAt = nil
            try await passwordRepository.update(entry)
        case var .pincode(entry):
            entry.deletedAt = nil
            try await pincodeRepository.update(entry)
        case var .bankcard(entry):
            entry.deletedAt = nil
            try await bankcardRepository.update(entry)
        }
    }

    func permanentlyDelete(_ item: VaultItem) async throws {
        switch item {
        case let .password(entry):
            try await passwordRepository.delete(entry.id)
        case let .pincode(entry):
            try await pincodeRepository.delete(entry.id)
        case let .bankcard(entry):
            try await bankcardRepository.delete(entry.id)
        }
    }
}
