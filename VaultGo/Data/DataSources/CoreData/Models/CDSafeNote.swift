/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// CDSafeNote.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import CoreData
import Foundation

@objc(CDSafeNote)
public class CDSafeNote: NSManagedObject {

}

extension CDSafeNote {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSafeNote> {
        NSFetchRequest<CDSafeNote>(entityName: "CDSafeNote")
    }

    @NSManaged public var id: UUID
    @NSManaged public var encryptedTitle: Data
    @NSManaged public var encryptedContent: Data
    @NSManaged public var coverAssetID: UUID?
    @NSManaged public var imageCount: Int32
    @NSManaged public var isFavorite: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var lastViewedAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var version: Int64
    @NSManaged public var isSynced: Bool
    @NSManaged public var dataSourceRaw: Int16
    @NSManaged public var assets: NSSet?
}

extension CDSafeNote: Identifiable {

}

@objc(CDSafeNoteAsset)
public class CDSafeNoteAsset: NSManagedObject {

}

extension CDSafeNoteAsset {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSafeNoteAsset> {
        NSFetchRequest<CDSafeNoteAsset>(entityName: "CDSafeNoteAsset")
    }

    @NSManaged public var id: UUID
    @NSManaged public var sortOrder: Int32
    @NSManaged public var mimeType: String
    @NSManaged public var pixelWidth: Int32
    @NSManaged public var pixelHeight: Int32
    @NSManaged public var byteSize: Int64
    @NSManaged public var encryptedFilePath: String
    @NSManaged public var encryptedThumbnailPath: String
    @NSManaged public var createdAt: Date
    @NSManaged public var note: CDSafeNote?
}

extension CDSafeNoteAsset: Identifiable {

}
