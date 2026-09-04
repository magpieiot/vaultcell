/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SafeNoteVaultService.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import Foundation

/// 安全笔记业务服务层
/// 封装 SafeNote 的增删改查，并向 ViewModel 暴露统一的列表状态。
@MainActor
final class SafeNoteVaultService: ObservableObject {
    @Published var notes: [SafeNote] = []
    @Published var trashedNotes: [SafeNote] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let repository: SafeNoteRepositoryProtocol

    init(repository: SafeNoteRepositoryProtocol = SafeNoteRepository()) {
        self.repository = repository
    }

    func loadNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadAll() async {
        await loadNotes()
    }

    /// 加载单条完整笔记（包含正文与图片元数据）
    func loadNote(by id: UUID) async -> SafeNote? {
        do {
            return try await repository.fetch(by: id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func searchNotes(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await loadNotes()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await repository.search(title: trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addNoteOrThrow(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {
        try await repository.save(note, draftAssets: draftAssets)
        await loadNotes()
    }

    func addNote(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async {
        do {
            try await addNoteOrThrow(note, draftAssets: draftAssets)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateNote(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {
        try await repository.update(note, draftAssets: draftAssets)
        await loadNotes()
    }

    func deleteNote(_ id: UUID) async {
        // 软删除：将笔记移入回收站，保留 30 天后由 purgeExpired 物理清理
        do {
            try await repository.softDelete(id)
            notes.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加载回收站中尚未过期的笔记
    func loadTrashedNotes() async {
        do {
            trashedNotes = try await repository.fetchTrashed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 物理清理超过保留期的笔记，返回被删除的 ID 列表
    func purgeExpiredNotes(retentionDays: Int = 30) async -> [UUID] {
        do {
            let purged = try await repository.purgeExpired(retentionDays: retentionDays)
            trashedNotes.removeAll { purged.contains($0.id) }
            return purged
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// 从回收站恢复笔记（清除 deletedAt）
    func restoreNote(_ id: UUID) async {
        do {
            guard var note = trashedNotes.first(where: { $0.id == id }) else { return }
            note.deletedAt = nil
            try await repository.update(note, draftAssets: note.assets.map {
                SafeNoteDraftAsset(id: $0.id, existingAsset: $0, sortOrder: $0.sortOrder)
            })
            trashedNotes.removeAll { $0.id == id }
            notes.append(note)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 彻底物理删除单条笔记（用于回收站中的"立即删除"）
    func permanentlyDeleteNote(_ id: UUID) async {
        do {
            try await repository.delete(id)
            trashedNotes.removeAll { $0.id == id }
            notes.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLastViewed(_ id: UUID) async {
        guard var note = await loadNote(by: id) else { return }
        note.lastViewedAt = Date()
        //note.version += 1
        do {
            try await repository.update(note, draftAssets: note.assets.map {
                SafeNoteDraftAsset(
                    id: $0.id,
                    existingAsset: $0,
                    sortOrder: $0.sortOrder
                )
            })
            await loadNotes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ id: UUID) async {
        // 先在内存中找到对应笔记，避免从数据库重新查询+解密
        guard var note = notes.first(where: { $0.id == id }) else { return }
        note.isFavorite.toggle()
        note.version += 1
        do {
            try await repository.update(note, draftAssets: note.assets.map {
                SafeNoteDraftAsset(
                    id: $0.id,
                    existingAsset: $0,
                    sortOrder: $0.sortOrder
                )
            })
            // 持久化成功后，直接更新内存中的对应条目，无需重新 fetchAll
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index] = note
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
