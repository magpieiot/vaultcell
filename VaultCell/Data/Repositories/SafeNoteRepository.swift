/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SafeNoteRepository.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import CoreGraphics
import Foundation

protocol SafeNoteRepositoryProtocol {
    func fetchAll() async throws -> [SafeNote]
    /// 获取全部未删除笔记的完整内容（含正文与附件元数据），用于备份导出
    func fetchAllFull() async throws -> [SafeNote]
    func fetch(by id: UUID) async throws -> SafeNote?
    func search(title query: String) async throws -> [SafeNote]
    func save(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws
    func update(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws
    func delete(_ id: UUID) async throws
    func softDelete(_ id: UUID) async throws
    func fetchTrashed() async throws -> [SafeNote]
    func purgeExpired(retentionDays: Int) async throws -> [UUID]
}

final class SafeNoteRepository: SafeNoteRepositoryProtocol {
    private let dataSource: CoreDataDataSource
    private let fileStorage: EncryptedFileStorageProtocol

    init(
        dataSource: CoreDataDataSource = CoreDataDataSource(context: CoreDataStack.shared.newBackgroundContext()),
        fileStorage: EncryptedFileStorageProtocol = EncryptedFileStorage()
    ) {
        self.dataSource = dataSource
        self.fileStorage = fileStorage
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

    func fetchAll() async throws -> [SafeNote] {
        try await perform {
            let cdNotes = try self.dataSource.fetchAllSafeNotes()
            var notes: [SafeNote] = []
            notes.reserveCapacity(cdNotes.count)

            var firstError: Error?
            for cdNote in cdNotes {
                guard cdNote.deletedAt == nil else { continue }
                do {
                    notes.append(try self.dataSource.convertToSafeNoteSummary(cdNote))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if notes.isEmpty, let firstError {
                throw firstError
            }
            return notes
        }
    }

    func fetchAllFull() async throws -> [SafeNote] {
        try await perform {
            let cdNotes = try self.dataSource.fetchAllSafeNotes()
            var notes: [SafeNote] = []
            notes.reserveCapacity(cdNotes.count)

            var firstError: Error?
            for cdNote in cdNotes {
                guard cdNote.deletedAt == nil else { continue }
                do {
                    notes.append(try self.dataSource.convertToSafeNote(cdNote))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if notes.isEmpty, let firstError {
                throw firstError
            }
            return notes
        }
    }

    func fetch(by id: UUID) async throws -> SafeNote? {
        try await perform {
            guard let cdNote = try self.dataSource.fetchSafeNote(by: id) else { return nil }
            return try self.dataSource.convertToSafeNote(cdNote)
        }
    }

    func search(title query: String) async throws -> [SafeNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchAll()
        }

        let notes = try await fetchAll()
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func save(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {
        try await persist(note, draftAssets: draftAssets, isUpdate: false)
    }

    func update(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {
        try await persist(note, draftAssets: draftAssets, isUpdate: true)
    }

    func delete(_ id: UUID) async throws {
        try await perform {
            let existingNote = try self.dataSource.fetchSafeNote(by: id).map { try self.dataSource.convertToSafeNote($0) }
            try self.dataSource.deleteSafeNote(id)

            for asset in existingNote?.assets ?? [] {
                try? self.fileStorage.deleteFile(at: asset.encryptedFilePath)
                try? self.fileStorage.deleteFile(at: asset.encryptedThumbnailPath)
            }
            try? self.fileStorage.deleteFiles(for: id)
        }
    }

    func softDelete(_ id: UUID) async throws {
        try await perform {
            guard let cdNote = try self.dataSource.fetchSafeNote(by: id) else { return }
            cdNote.deletedAt = Date()
            try self.dataSource.saveIfPossible()
        }
    }

    func fetchTrashed() async throws -> [SafeNote] {
        try await perform {
            let cdNotes = try self.dataSource.fetchAllSafeNotes()
            var notes: [SafeNote] = []
            var firstError: Error?
            for cdNote in cdNotes {
                guard cdNote.deletedAt != nil else { continue }
                do {
                    notes.append(try self.dataSource.convertToSafeNoteSummary(cdNote))
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if notes.isEmpty, let firstError { throw firstError }
            return notes
        }
    }

    func purgeExpired(retentionDays: Int) async throws -> [UUID] {
        try await perform {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
            let cdNotes = try self.dataSource.fetchAllSafeNotes()
            var purgedIDs: [UUID] = []
            for cdNote in cdNotes {
                if let deletedAt = cdNote.deletedAt, deletedAt < cutoff {
                    let id = cdNote.id
                    // 物理删除前清理关联加密文件
                    let existingNote = try? self.dataSource.convertToSafeNote(cdNote)
                    self.dataSource.context.delete(cdNote)
                    for asset in existingNote?.assets ?? [] {
                        try? self.fileStorage.deleteFile(at: asset.encryptedFilePath)
                        try? self.fileStorage.deleteFile(at: asset.encryptedThumbnailPath)
                    }
                    try? self.fileStorage.deleteFiles(for: id)
                    purgedIDs.append(id)
                }
            }
            if !purgedIDs.isEmpty {
                try self.dataSource.saveIfPossible()
            }
            return purgedIDs
        }
    }

    private func persist(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset], isUpdate: Bool) async throws {
        try await perform {
            let existingNote = try self.dataSource.fetchSafeNote(by: note.id).map { try self.dataSource.convertToSafeNote($0) }
            var newlyWrittenPaths: [String] = []

            do {
                let assets = try self.makePersistedAssets(
                    noteID: note.id,
                    draftAssets: draftAssets,
                    newlyWrittenPaths: &newlyWrittenPaths
                )

                var persistedNote = note
                persistedNote.assets = assets
                if persistedNote.coverAssetID == nil || assets.contains(where: { $0.id == persistedNote.coverAssetID }) == false {
                    persistedNote.coverAssetID = assets.first?.id
                }
                // updatedAt 由上层（service/ViewModel）决定是否更新，repository 不再强制覆盖，
                // 避免 updateLastViewed/toggleFavorite 等操作意外改变 updatedAt
                if isUpdate == false {
                    persistedNote.createdAt = note.createdAt
                }

                try self.dataSource.saveSafeNote(persistedNote)

                if let existingNote {
                    let removedAssets = existingNote.assets.filter { oldAsset in
                        assets.contains(where: { $0.id == oldAsset.id }) == false
                    }
                    for asset in removedAssets {
                        try? self.fileStorage.deleteFile(at: asset.encryptedFilePath)
                        try? self.fileStorage.deleteFile(at: asset.encryptedThumbnailPath)
                    }
                }
            } catch {
                for path in newlyWrittenPaths {
                    try? self.fileStorage.deleteFile(at: path)
                }
                throw error
            }
        }
    }

    private func makePersistedAssets(
        noteID: UUID,
        draftAssets: [SafeNoteDraftAsset],
        newlyWrittenPaths: inout [String]
    ) throws -> [SafeNoteAsset] {
        try draftAssets
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .enumerated()
            .compactMap { index, draftAsset in
                if let existingAsset = draftAsset.existingAsset, draftAsset.imageData == nil {
                    var asset = existingAsset
                    asset.noteID = noteID
                    asset.sortOrder = index
                    return asset
                }

                guard let imageData = draftAsset.imageData else {
                    return nil
                }

                let optimizedData = fileStorage.optimizedImageData(from: imageData, maxDimension: 2000) ?? imageData
                let thumbnailData = draftAsset.thumbnailData
                    ?? fileStorage.thumbnailData(from: optimizedData, maxDimension: 320)
                    ?? optimizedData

                let encryptedFilePath = try fileStorage.saveImage(
                    data: optimizedData,
                    noteID: noteID,
                    assetID: draftAsset.id
                )
                newlyWrittenPaths.append(encryptedFilePath)

                let encryptedThumbnailPath = try fileStorage.saveThumbnail(
                    data: thumbnailData,
                    noteID: noteID,
                    assetID: draftAsset.id
                )
                newlyWrittenPaths.append(encryptedThumbnailPath)

                let imageSize = fileStorage.imageSize(from: optimizedData) ?? .zero

                return SafeNoteAsset(
                    id: draftAsset.id,
                    noteID: noteID,
                    sortOrder: index,
                    mimeType: draftAsset.mimeType ?? mimeType(for: optimizedData),
                    pixelWidth: Int(imageSize.width.rounded()),
                    pixelHeight: Int(imageSize.height.rounded()),
                    byteSize: Int64(optimizedData.count),
                    encryptedFilePath: encryptedFilePath,
                    encryptedThumbnailPath: encryptedThumbnailPath
                )
            }
    }

    private func mimeType(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        return "image/jpeg"
    }
}
