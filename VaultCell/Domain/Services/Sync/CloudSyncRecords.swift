import CloudKit
import Foundation

struct CloudPreparedRecords {
    let records: [CKRecord]
    let temporaryFilesByRecord: [CKRecord.ID: [URL]]

    init(records: [CKRecord], temporaryFiles: [URL]) {
        self.records = records
        self.temporaryFilesByRecord = Dictionary(
            uniqueKeysWithValues: records.map { ($0.recordID, temporaryFiles) }
        )
    }

    init(records: [CKRecord], temporaryFilesByRecord: [CKRecord.ID: [URL]]) {
        self.records = records
        self.temporaryFilesByRecord = temporaryFilesByRecord
    }
}

struct CloudItem {
    let id: UUID
    let kind: SyncItemKind
    let vaultID: String?
    let clock: SyncClock
    let isTombstone: Bool
    let encryptedPayload: Data?
}

final class CloudSyncRecords {
    static let itemType = "VaultItem"
    static let assetType = "VaultAsset"
    static let metadataType = "VaultMetadata"
    static let deviceType = "VaultDevice"

    private let encryptionService: EncryptionServiceProtocol
    private let fileStorage: EncryptedFileStorageProtocol
    private let localStore: SyncLocalStore
    private let fileManager: FileManager

    init(
        encryptionService: EncryptionServiceProtocol = EncryptionService.shared,
        fileStorage: EncryptedFileStorageProtocol = EncryptedFileStorage(),
        localStore: SyncLocalStore = .shared,
        fileManager: FileManager = .default
    ) {
        self.encryptionService = encryptionService
        self.fileStorage = fileStorage
        self.localStore = localStore
        self.fileManager = fileManager
    }

    func passwordRecord(_ entry: PasswordEntry, zoneID: CKRecordZone.ID) throws -> CloudPreparedRecords {
        let data = try encryptedPayload(entry)
        return try itemRecord(
            id: entry.id,
            kind: .password,
            revision: entry.version,
            encryptedPayload: data,
            zoneID: zoneID
        )
    }

    func noteRecord(_ note: SafeNote, zoneID: CKRecordZone.ID) throws -> CloudPreparedRecords {
        let data = try encryptedPayload(note)
        return try itemRecord(
            id: note.id,
            kind: .safeNote,
            revision: note.version,
            encryptedPayload: data,
            zoneID: zoneID
        )
    }

    func tombstoneRecord(_ tombstone: SyncLocalTombstone, zoneID: CKRecordZone.ID) -> CKRecord {
        let previousClock = localStore.clock(for: tombstone.itemID)
        let tombstoneRevision = max(tombstone.revision, previousClock?.revision ?? 0) + 1
        let clock = localStore.nextClock(
            for: tombstone.itemID,
            revision: tombstoneRevision,
            observing: previousClock
        )
        let record = baseRecord(
            type: Self.itemType,
            recordName: Self.itemRecordName(kind: tombstone.itemKind, id: tombstone.itemID),
            zoneID: zoneID
        )
        setCommonFields(record: record, id: tombstone.itemID, kind: tombstone.itemKind, clock: clock)
        record["isTombstone"] = NSNumber(value: true)
        record["payload"] = nil
        record["payloadAsset"] = nil
        localStore.saveClock(clock, for: tombstone.itemID)
        return record
    }

    func assetRecords(for note: SafeNote, zoneID: CKRecordZone.ID) throws -> CloudPreparedRecords {
        var records: [CKRecord] = []
        var filesByRecord: [CKRecord.ID: [URL]] = [:]
        for asset in note.assets {
            let image = try fileStorage.loadDecryptedData(at: asset.encryptedFilePath)
            let thumbnail = try fileStorage.loadDecryptedData(at: asset.encryptedThumbnailPath)
            let encryptedImage = try encryptionService.encrypt(image).combined
            let encryptedThumbnail = try encryptionService.encrypt(thumbnail).combined
            let record = baseRecord(
                type: Self.assetType,
                recordName: Self.assetRecordName(noteID: note.id, assetID: asset.id),
                zoneID: zoneID
            )
            record["noteID"] = note.id.uuidString
            record["assetID"] = asset.id.uuidString
            record["keyVersion"] = NSNumber(value: 1)
            let imageAsset = try makeAsset(encryptedImage, prefix: "image")
            let thumbnailAsset = try makeAsset(encryptedThumbnail, prefix: "thumbnail")
            record["image"] = imageAsset.0
            record["thumbnail"] = thumbnailAsset.0
            records.append(record)
            filesByRecord[record.recordID] = [imageAsset.1, thumbnailAsset.1]
        }
        return CloudPreparedRecords(records: records, temporaryFilesByRecord: filesByRecord)
    }

    func decodeItem(_ record: CKRecord) throws -> CloudItem {
        guard
            let idString = record["itemID"] as? String,
            let id = UUID(uuidString: idString),
            let kindString = record["itemKind"] as? String,
            let kind = SyncItemKind(rawValue: kindString),
            let clock = decodeClock(record)
        else {
            throw CloudSyncError.invalidRecord(record.recordID.recordName)
        }
        let isTombstone = (record["isTombstone"] as? NSNumber)?.boolValue ?? false
        var encryptedPayload: Data?
        if !isTombstone {
            if let inline = record["payload"] as? Data {
                encryptedPayload = inline
            } else if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL {
                encryptedPayload = try Data(contentsOf: url)
            }
            guard encryptedPayload != nil else {
                throw CloudSyncError.invalidRecord(record.recordID.recordName)
            }
        }
        return CloudItem(
            id: id,
            kind: kind,
            vaultID: record["vaultID"] as? String,
            clock: clock,
            isTombstone: isTombstone,
            encryptedPayload: encryptedPayload
        )
    }

    func password(from item: CloudItem) throws -> PasswordEntry {
        guard item.kind == .password, let data = item.encryptedPayload else {
            throw CloudSyncError.invalidRecord(item.id.uuidString)
        }
        return try decoder().decode(PasswordEntry.self, from: encryptionService.decryptToData(data))
    }

    func note(from item: CloudItem) throws -> SafeNote {
        guard item.kind == .safeNote, let data = item.encryptedPayload else {
            throw CloudSyncError.invalidRecord(item.id.uuidString)
        }
        return try decoder().decode(SafeNote.self, from: encryptionService.decryptToData(data))
    }

    func assetData(_ record: CKRecord) throws -> (image: Data, thumbnail: Data) {
        guard let imageAsset = record["image"] as? CKAsset,
              let thumbnailAsset = record["thumbnail"] as? CKAsset,
              let imageURL = imageAsset.fileURL,
              let thumbnailURL = thumbnailAsset.fileURL else {
            throw CloudSyncError.invalidRecord(record.recordID.recordName)
        }
        let encryptedImage = try Data(contentsOf: imageURL)
        let encryptedThumbnail = try Data(contentsOf: thumbnailURL)
        return (
            try encryptionService.decryptToData(encryptedImage),
            try encryptionService.decryptToData(encryptedThumbnail)
        )
    }

    func encryptedPayload<T: Codable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encryptionService.encrypt(encoder.encode(value)).combined
    }

    func clock(for record: CKRecord) -> SyncClock? {
        decodeClock(record)
    }

    static func itemRecordName(kind: SyncItemKind, id: UUID) -> String {
        "item-\(kind.rawValue)-\(id.uuidString)"
    }

    static func assetRecordName(noteID: UUID, assetID: UUID) -> String {
        "asset-\(noteID.uuidString)-\(assetID.uuidString)"
    }

    private func itemRecord(
        id: UUID,
        kind: SyncItemKind,
        revision: Int64,
        encryptedPayload: Data,
        zoneID: CKRecordZone.ID
    ) throws -> CloudPreparedRecords {
        let clock = localStore.nextClock(for: id, revision: revision)
        let record = baseRecord(
            type: Self.itemType,
            recordName: Self.itemRecordName(kind: kind, id: id),
            zoneID: zoneID
        )
        setCommonFields(record: record, id: id, kind: kind, clock: clock)
        record["isTombstone"] = NSNumber(value: false)
        var temporaryFiles: [URL] = []
        if encryptedPayload.count <= SyncProtocolLimits.inlinePayloadMaxBytes {
            record["payload"] = encryptedPayload
            record["payloadAsset"] = nil
        } else {
            let asset = try makeAsset(encryptedPayload, prefix: "payload")
            record["payload"] = nil
            record["payloadAsset"] = asset.0
            temporaryFiles.append(asset.1)
        }
        localStore.saveClock(clock, for: id)
        return CloudPreparedRecords(records: [record], temporaryFiles: temporaryFiles)
    }

    private func setCommonFields(
        record: CKRecord,
        id: UUID,
        kind: SyncItemKind,
        clock: SyncClock
    ) {
        record["schemaVersion"] = NSNumber(value: 1)
        record["vaultID"] = UserDefaults.standard.string(forKey: VaultKey.vaultID)
        record["itemID"] = id.uuidString
        record["itemKind"] = kind.rawValue
        record["revision"] = NSNumber(value: clock.revision)
        record["lamport"] = NSNumber(value: clock.lamport)
        record["deviceID"] = clock.deviceID.uuidString
        record["mutationID"] = clock.mutationID.uuidString
        record["keyVersion"] = NSNumber(value: 1)
    }

    private func decodeClock(_ record: CKRecord) -> SyncClock? {
        guard let revision = (record["revision"] as? NSNumber)?.int64Value,
              let lamport = (record["lamport"] as? NSNumber)?.int64Value,
              let deviceString = record["deviceID"] as? String,
              let deviceID = UUID(uuidString: deviceString),
              let mutationString = record["mutationID"] as? String,
              let mutationID = UUID(uuidString: mutationString) else {
            return nil
        }
        return SyncClock(
            revision: revision,
            lamport: lamport,
            deviceID: deviceID,
            mutationID: mutationID
        )
    }

    private func baseRecord(type: String, recordName: String, zoneID: CKRecordZone.ID) -> CKRecord {
        if let cached = localStore.serverRecord(named: recordName), cached.recordType == type {
            return cached
        }
        return CKRecord(
            recordType: type,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )
    }

    private func makeAsset(_ data: Data, prefix: String) throws -> (CKAsset, URL) {
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "VaultCellCloudSync",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(prefix)-\(UUID().uuidString).bin")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return (CKAsset(fileURL: url), url)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
