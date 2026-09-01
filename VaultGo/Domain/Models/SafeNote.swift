/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// SafeNote.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import Foundation

struct SafeNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var assets: [SafeNoteAsset]
    var coverAssetID: UUID?
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastViewedAt: Date?
    var deletedAt: Date?
    var version: Int64
    var isSynced: Bool
    var dataSource: PasswordDataSource

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        assets: [SafeNoteAsset] = [],
        coverAssetID: UUID? = nil,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastViewedAt: Date? = nil,
        deletedAt: Date? = nil,
        version: Int64 = 1,
        isSynced: Bool = false,
        dataSource: PasswordDataSource = .manual
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.assets = assets
        self.coverAssetID = coverAssetID
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastViewedAt = lastViewedAt
        self.deletedAt = deletedAt
        self.version = version
        self.isSynced = isSynced
        self.dataSource = dataSource
    }

    var coverAsset: SafeNoteAsset? {
        if let coverAssetID {
            return assets.first { $0.id == coverAssetID }
        }
        return assets.first
    }

    var imageCount: Int {
        assets.count
    }
}

struct SafeNoteAsset: Identifiable, Codable, Equatable {
    var id: UUID
    var noteID: UUID
    var sortOrder: Int
    var mimeType: String
    var pixelWidth: Int
    var pixelHeight: Int
    var byteSize: Int64
    var encryptedFilePath: String
    var encryptedThumbnailPath: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        noteID: UUID,
        sortOrder: Int,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        byteSize: Int64,
        encryptedFilePath: String,
        encryptedThumbnailPath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.sortOrder = sortOrder
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
        self.encryptedFilePath = encryptedFilePath
        self.encryptedThumbnailPath = encryptedThumbnailPath
        self.createdAt = createdAt
    }
}

struct SafeNoteDraft: Equatable {
    var title: String
    var content: String
    var assets: [SafeNoteDraftAsset]
    var coverAssetID: UUID?
    var isFavorite: Bool

    init(
        title: String = "",
        content: String = "",
        assets: [SafeNoteDraftAsset] = [],
        coverAssetID: UUID? = nil,
        isFavorite: Bool = false
    ) {
        self.title = title
        self.content = content
        self.assets = assets
        self.coverAssetID = coverAssetID
        self.isFavorite = isFavorite
    }
}

struct SafeNoteDraftAsset: Identifiable, Equatable {
    var id: UUID
    var imageData: Data?
    var thumbnailData: Data?
    var existingAsset: SafeNoteAsset?
    var sortOrder: Int
    var mimeType: String?

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        existingAsset: SafeNoteAsset? = nil,
        sortOrder: Int = 0,
        mimeType: String? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.existingAsset = existingAsset
        self.sortOrder = sortOrder
        self.mimeType = mimeType
    }
}
