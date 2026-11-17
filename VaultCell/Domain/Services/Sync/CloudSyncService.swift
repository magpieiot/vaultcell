import CloudKit
import CryptoKit
import Foundation

@MainActor
protocol CloudSyncStatusReporting: AnyObject {
    func syncDidStart()
    func syncDidComplete()
    func syncDidFail(_ error: Error)
    func syncAccountDidChange()
}

/// 只同步本机加密后的业务载荷；CloudKit 引擎负责 token、分批、调度和基础重试。
actor CloudSyncService: CKSyncEngineDelegate {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let records: CloudSyncRecords
    private let localStore: SyncLocalStore
    private let snapshotStore = SyncConflictSnapshotStore()
    private weak var statusDelegate: (any CloudSyncStatusReporting)?

    private var engine: CKSyncEngine?
    private var pendingRecords: [CKRecord.ID: CKRecord] = [:]
    private var temporaryFiles: [CKRecord.ID: [URL]] = [:]
    private var pendingNoteAssets: [UUID: Set<UUID>] = [:]
    private var failureMessages: [String] = []
    private var isSynchronizing = false
    private var metadataConflictDetected = false

    init(
        statusDelegate: (any CloudSyncStatusReporting)?,
        records: CloudSyncRecords = CloudSyncRecords(),
        localStore: SyncLocalStore = .shared
    ) {
        let containerID = "iCloud.com.magpie.vaultcell"
        self.container = CKContainer(identifier: containerID)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: "VaultCellZone", ownerName: CKCurrentUserDefaultName)
        self.statusDelegate = statusDelegate
        self.records = records
        self.localStore = localStore
    }

    func start() async throws {
        guard engine == nil else { return }
        guard try await container.accountStatus() == .available else {
            throw CloudSyncError.iCloudUnavailable
        }

        var serialization: CKSyncEngine.State.Serialization?
        if let data = localStore.stateSerialization {
            serialization = try? JSONDecoder().decode(
                CKSyncEngine.State.Serialization.self,
                from: data
            )
        }
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = "vaultcell-private-sync"
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        engine.state.add(
            pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]
        )
    }

    func stop() {
        engine = nil
        pendingRecords.removeAll()
        cleanupTemporaryFiles()
    }

    func synchronize() async throws {
        guard let engine else { throw CloudSyncError.iCloudUnavailable }
        guard !isSynchronizing else { return }
        isSynchronizing = true
        failureMessages = []
        metadataConflictDetected = false
        await statusDelegate?.syncDidStart()

        do {
            // 确保旧版本升级时先得到稳定 vaultID，再校验远端元数据。
            _ = try AppLockService().exportCloudKeyMaterial()
            try await validateRemoteMetadataBeforeDecryptingItems()
            try await engine.sendChanges()
            try await engine.fetchChanges()
            if metadataConflictDetected {
                throw CloudSyncError.remoteKeyMaterialChanged
            }
            try await retryPendingRemoteRecords()
            try await prepareLocalChanges()
            try await engine.sendChanges()
            if !failureMessages.isEmpty {
                throw CloudSyncError.partialFailure(failureMessages.prefix(2).joined(separator: "; "))
            }
            localStore.initialUploadDone = true
            await statusDelegate?.syncDidComplete()
        } catch {
            await statusDelegate?.syncDidFail(error)
            isSynchronizing = false
            throw error
        }
        isSynchronizing = false
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            await self?.record(for: recordID)
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                localStore.saveStateSerialization(data)
            }

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            // 先应用密钥元数据，再尝试解密业务记录。
            for modification in changes.modifications
            where modification.record.recordType == CloudSyncRecords.metadataType {
                do {
                    try await applyRemoteRecord(modification.record)
                } catch {
                    metadataConflictDetected = true
                    failureMessages.append(error.localizedDescription)
                }
            }
            for modification in changes.modifications
            where modification.record.recordType != CloudSyncRecords.metadataType {
                do {
                    try await applyRemoteRecord(modification.record)
                } catch {
                    localStore.addPendingRemoteRecordName(modification.record.recordID.recordName)
                    if Self.isAuthenticationFailure(error) {
                        failureMessages.append(CloudSyncError.vaultMismatch.localizedDescription)
                    } else {
                        failureMessages.append(error.localizedDescription)
                    }
                }
            }

        case .sentRecordZoneChanges(let changes):
            await handleSentRecordChanges(changes)

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                localStore.resetForAccountChange()
                await statusDelegate?.syncDidFail(CloudSyncError.iCloudUnavailable)
            }

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges, .sentDatabaseChanges:
            break
        @unknown default:
            break
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signIn:
            localStore.initialUploadDone = false
        case .switchAccounts, .signOut:
            localStore.resetForAccountChange()
            engine = nil
            await statusDelegate?.syncAccountDidChange()
        @unknown default:
            break
        }
    }

    private func prepareLocalChanges() async throws {
        let initialUpload = !localStore.initialUploadDone
        let passwordRepository = PasswordRepository()
        let noteRepository = SafeNoteRepository()

        for entry in try await passwordRepository.fetchAllForSync()
        where initialUpload || !entry.isSynced {
            let prepared = try records.passwordRecord(entry, zoneID: zoneID)
            enqueue(prepared)
        }

        for note in try await noteRepository.fetchAllForSync()
        where initialUpload || !note.isSynced {
            let noteRecord = try records.noteRecord(note, zoneID: zoneID)
            let assetRecords = try records.assetRecords(for: note, zoneID: zoneID)
            enqueue(noteRecord)
            enqueue(assetRecords)
            pendingNoteAssets[note.id] = Set(note.assets.map(\.id))

            let currentIDs = pendingNoteAssets[note.id] ?? []
            let staleIDs = localStore.uploadedAssetIDs(noteID: note.id).subtracting(currentIDs)
            for assetID in staleIDs {
                let recordID = CKRecord.ID(
                    recordName: CloudSyncRecords.assetRecordName(noteID: note.id, assetID: assetID),
                    zoneID: zoneID
                )
                engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
        }

        for tombstone in localStore.tombstones() where !tombstone.isSynced {
            enqueue(
                CloudPreparedRecords(
                    records: [records.tombstoneRecord(tombstone, zoneID: zoneID)],
                    temporaryFiles: []
                )
            )
        }

        enqueue(try prepareMetadataRecord())
        enqueue(prepareDeviceRecord())
    }

    private func validateRemoteMetadataBeforeDecryptingItems() async throws {
        let recordID = CKRecord.ID(recordName: "vault-metadata", zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            try validateRemoteMetadata(record)
        } catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound {
            return
        }
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        if let cryptoError = error as? CryptoKitError,
           case .authenticationFailure = cryptoError {
            return true
        }
        return false
    }

    private func retryPendingRemoteRecords() async throws {
        for name in localStore.pendingRemoteRecordNames() {
            do {
                let record = try await database.record(
                    for: CKRecord.ID(recordName: name, zoneID: zoneID)
                )
                try await applyRemoteRecord(record)
                localStore.removePendingRemoteRecordName(name)
            } catch let error as CKError where error.code == .unknownItem {
                localStore.removePendingRemoteRecordName(name)
            }
        }
    }

    private func applyRemoteRecord(_ record: CKRecord) async throws {
        localStore.saveServerRecord(record)
        switch record.recordType {
        case CloudSyncRecords.itemType:
            try await applyRemoteItem(record)
        case CloudSyncRecords.metadataType:
            try validateRemoteMetadata(record)
        default:
            break
        }
    }

    private func applyRemoteItem(_ record: CKRecord) async throws {
        let item = try records.decodeItem(record)
        let recordName = record.recordID.recordName
        if let remoteVaultID = item.vaultID,
           let localVaultID = UserDefaults.standard.string(forKey: VaultKey.vaultID),
           remoteVaultID != localVaultID {
            // 同一私有 Zone 可能残留旧密码库记录；不能拿当前 DEK 尝试解密。
            localStore.removePendingRemoteRecordName(recordName)
            return
        }
        if item.isTombstone {
            try await applyRemoteTombstone(item, recordName: recordName)
            return
        }

        switch item.kind {
        case .password:
            let repository = PasswordRepository()
            if let local = try await repository.fetch(by: item.id) {
                if !local.isSynced {
                    let localClock = localStore.nextClock(
                        for: item.id,
                        revision: local.version,
                        observing: item.clock
                    )
                    if SyncConflictResolver.resolve(local: localClock, remote: item.clock) == .remoteWins {
                        try snapshotStore.save(
                            itemID: item.id,
                            itemKind: .password,
                            localClock: localClock,
                            remoteClock: item.clock,
                            encryptedPayload: try records.encryptedPayload(local)
                        )
                    } else {
                        enqueue(try records.passwordRecord(local, zoneID: zoneID))
                        return
                    }
                } else if let localClock = localStore.clock(for: item.id) {
                    let decision = SyncConflictResolver.resolve(local: localClock, remote: item.clock)
                    if decision == .identical || decision == .localWins {
                        localStore.saveServerRecord(record)
                        return
                    }
                }
            }
            let remote = try records.password(from: item)
            try await repository.applyRemote(remote)
            localStore.saveClock(item.clock, for: item.id)
            localStore.removePendingRemoteRecordName(recordName)

        case .safeNote:
            let repository = SafeNoteRepository()
            if let local = try await repository.fetch(by: item.id) {
                if !local.isSynced {
                    let localClock = localStore.nextClock(
                        for: item.id,
                        revision: local.version,
                        observing: item.clock
                    )
                    if SyncConflictResolver.resolve(local: localClock, remote: item.clock) == .remoteWins {
                        try snapshotStore.save(
                            itemID: item.id,
                            itemKind: .safeNote,
                            localClock: localClock,
                            remoteClock: item.clock,
                            encryptedPayload: try records.encryptedPayload(local)
                        )
                    } else {
                        enqueue(try records.noteRecord(local, zoneID: zoneID))
                        return
                    }
                } else if let localClock = localStore.clock(for: item.id) {
                    let decision = SyncConflictResolver.resolve(local: localClock, remote: item.clock)
                    if decision == .identical || decision == .localWins {
                        localStore.saveServerRecord(record)
                        return
                    }
                }
            }
            let remote = try records.note(from: item)
            let drafts = try await downloadAssets(for: remote)
            try await repository.applyRemote(remote, draftAssets: drafts)
            localStore.saveClock(item.clock, for: item.id)
            localStore.removePendingRemoteRecordName(recordName)
        }
    }

    private func applyRemoteTombstone(_ item: CloudItem, recordName: String) async throws {
        if let localTombstone = localStore.tombstones().first(where: {
            $0.itemID == item.id && $0.itemKind == item.kind
        }) {
            if !localTombstone.isSynced,
               let localClock = localTombstone.clock,
               SyncConflictResolver.resolve(local: localClock, remote: item.clock) == .localWins {
                return
            }
        }

        switch item.kind {
        case .password:
            let repository = PasswordRepository()
            if let local = try await repository.fetch(by: item.id) {
                let localClock = localStore.nextClock(
                    for: item.id,
                    revision: local.version,
                    observing: item.clock
                )
                if !local.isSynced,
                   SyncConflictResolver.resolve(local: localClock, remote: item.clock) == .localWins {
                    enqueue(try records.passwordRecord(local, zoneID: zoneID))
                    return
                }
            }
            try await repository.deleteRemote(item.id)
        case .safeNote:
            let repository = SafeNoteRepository()
            if let local = try await repository.fetch(by: item.id) {
                let localClock = localStore.nextClock(
                    for: item.id,
                    revision: local.version,
                    observing: item.clock
                )
                if !local.isSynced,
                   SyncConflictResolver.resolve(local: localClock, remote: item.clock) == .localWins {
                    enqueue(try records.noteRecord(local, zoneID: zoneID))
                    return
                }
            }
            try await repository.deleteRemote(item.id)
        }
        localStore.saveClock(item.clock, for: item.id)
        localStore.recordTombstone(
            itemID: item.id,
            itemKind: item.kind,
            revision: item.clock.revision,
            clock: item.clock,
            isSynced: true
        )
        localStore.removePendingRemoteRecordName(recordName)
    }

    private func downloadAssets(for note: SafeNote) async throws -> [SafeNoteDraftAsset] {
        var drafts: [SafeNoteDraftAsset] = []
        for asset in note.assets.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let recordID = CKRecord.ID(
                recordName: CloudSyncRecords.assetRecordName(noteID: note.id, assetID: asset.id),
                zoneID: zoneID
            )
            let record = try await database.record(for: recordID)
            let data = try records.assetData(record)
            drafts.append(
                SafeNoteDraftAsset(
                    id: asset.id,
                    imageData: data.image,
                    thumbnailData: data.thumbnail,
                    sortOrder: asset.sortOrder,
                    mimeType: asset.mimeType
                )
            )
        }
        return drafts
    }

    private func handleSentRecordChanges(_ changes: CKSyncEngine.Event.SentRecordZoneChanges) async {
        // 附件先落账，再确认笔记；否则同一批次内笔记可能先被标记完成。
        for saved in changes.savedRecords where saved.recordType == CloudSyncRecords.assetType {
            localStore.saveServerRecord(saved)
            if let noteID = (saved["noteID"] as? String).flatMap(UUID.init(uuidString:)),
               let assetID = (saved["assetID"] as? String).flatMap(UUID.init(uuidString:)) {
                localStore.addUploadedAssetID(assetID, noteID: noteID)
            }
            cleanupTemporaryFiles(for: saved.recordID)
        }
        for saved in changes.savedRecords where saved.recordType != CloudSyncRecords.assetType {
            localStore.saveServerRecord(saved)
            await markSavedRecord(saved)
            cleanupTemporaryFiles(for: saved.recordID)
        }

        for failure in changes.failedRecordSaves {
            let record = failure.record
            let error = failure.error
            failureMessages.append("\(record.recordID.recordName): \(error.localizedDescription)")

            switch error.code {
            case .serverRecordChanged:
                if let server = error.serverRecord {
                    do {
                        try await applyRemoteRecord(server)
                    } catch {
                        localStore.addPendingRemoteRecordName(server.recordID.recordName)
                    }
                }
            case .zoneNotFound:
                engine?.state.add(
                    pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: record.recordID.zoneID))]
                )
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            case .unknownItem:
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            default:
                break
            }
        }

        for deleted in changes.deletedRecordIDs {
            localStore.removeServerRecord(named: deleted.recordName)
        }
        for (recordID, error) in changes.failedRecordDeletes {
            failureMessages.append("\(recordID.recordName): \(error.localizedDescription)")
        }
    }

    private func markSavedRecord(_ record: CKRecord) async {
        guard record.recordType == CloudSyncRecords.itemType,
              let idString = record["itemID"] as? String,
              let id = UUID(uuidString: idString),
              let kindString = record["itemKind"] as? String,
              let kind = SyncItemKind(rawValue: kindString),
              let clock = records.clock(for: record) else {
            return
        }
        let isTombstone = (record["isTombstone"] as? NSNumber)?.boolValue ?? false
        if isTombstone {
            localStore.markTombstoneSynced(itemID: id, clock: clock)
            return
        }
        switch kind {
        case .password:
            try? await PasswordRepository().markSynced(id)
        case .safeNote:
            let expectedAssets = pendingNoteAssets[id] ?? []
            let uploadedAssets = localStore.uploadedAssetIDs(noteID: id)
            guard expectedAssets.isSubset(of: uploadedAssets) else {
                failureMessages.append("safe note \(id.uuidString): attachments pending")
                return
            }
            try? await SafeNoteRepository().markSynced(id)
            pendingNoteAssets.removeValue(forKey: id)
            localStore.saveUploadedAssetIDs(expectedAssets, noteID: id)
        }
        localStore.saveClock(clock, for: id)
    }

    private func validateRemoteMetadata(_ record: CKRecord) throws {
        guard let remoteVaultID = record["vaultID"] as? String,
              let localVaultID = UserDefaults.standard.string(forKey: VaultKey.vaultID),
              remoteVaultID == localVaultID else {
            throw CloudSyncError.vaultMismatch
        }
        let localRevision = Int64(max(1, UserDefaults.standard.integer(forKey: VaultKey.cloudKeyRevision)))
        let remoteRevision = (record["revision"] as? NSNumber)?.int64Value ?? 0
        let localWrapped = try AppLockService().exportCloudKeyMaterial().wrappedDEK
        let remoteWrapped = record["wrappedDEK"] as? Data
        if remoteRevision > localRevision {
            // 改密复用同一个 DEK；本设备仍持有该 DEK，可安全吸收新的包裹材料。
            let material = try decodeKeyMaterial(record)
            try AppLockService().importCloudKeyMaterial(material)
            metadataConflictDetected = true
            throw CloudSyncError.remoteKeyMaterialChanged
        }
        if remoteRevision == localRevision && remoteWrapped != localWrapped {
            // 同一修订号出现两个包裹材料，说明并发改密；以云端已接受的版本为准。
            let material = try decodeKeyMaterial(record)
            try AppLockService().importCloudKeyMaterial(material)
            metadataConflictDetected = true
            throw CloudSyncError.remoteKeyMaterialChanged
        }
    }

    private func decodeKeyMaterial(_ record: CKRecord) throws -> CloudVaultKeyMaterial {
        guard let vaultIDString = record["vaultID"] as? String,
              let vaultID = UUID(uuidString: vaultIDString),
              let salt = record["salt"] as? Data,
              let wrappedDEK = record["wrappedDEK"] as? Data,
              let kdfAlgorithm = record["kdfAlgorithm"] as? String,
              let iterations = (record["kdfIterations"] as? NSNumber)?.intValue,
              let wrapAlgorithm = record["wrapAlgorithm"] as? String,
              let revision = (record["revision"] as? NSNumber)?.int64Value else {
            throw CloudSyncError.vaultMismatch
        }
        return CloudVaultKeyMaterial(
            vaultID: vaultID,
            salt: salt,
            wrappedDEK: wrappedDEK,
            kdfAlgorithm: kdfAlgorithm,
            kdfIterations: iterations,
            wrapAlgorithm: wrapAlgorithm,
            revision: revision
        )
    }

    private func prepareMetadataRecord() throws -> CloudPreparedRecords {
        let material = try AppLockService().exportCloudKeyMaterial()
        let name = "vault-metadata"
        let record = localStore.serverRecord(named: name)
            ?? CKRecord(
                recordType: CloudSyncRecords.metadataType,
                recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
            )
        record["schemaVersion"] = NSNumber(value: 1)
        record["vaultID"] = material.vaultID.uuidString
        record["salt"] = material.salt
        record["wrappedDEK"] = material.wrappedDEK
        record["kdfAlgorithm"] = material.kdfAlgorithm
        record["kdfIterations"] = NSNumber(value: material.kdfIterations)
        record["wrapAlgorithm"] = material.wrapAlgorithm
        record["revision"] = NSNumber(value: material.revision)
        return CloudPreparedRecords(records: [record], temporaryFiles: [])
    }

    private func prepareDeviceRecord() -> CloudPreparedRecords {
        let name = "device-\(localStore.deviceID.uuidString)"
        let record = localStore.serverRecord(named: name)
            ?? CKRecord(
                recordType: CloudSyncRecords.deviceType,
                recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
            )
        record["deviceID"] = localStore.deviceID.uuidString
        record["keyVersion"] = NSNumber(value: 1)
        record["status"] = "active"
        record["updatedAt"] = Date()
        return CloudPreparedRecords(records: [record], temporaryFiles: [])
    }

    private func enqueue(_ prepared: CloudPreparedRecords) {
        for record in prepared.records {
            pendingRecords[record.recordID] = record
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            temporaryFiles[record.recordID, default: []].append(
                contentsOf: prepared.temporaryFilesByRecord[record.recordID] ?? []
            )
        }
    }

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        pendingRecords[recordID]
    }

    private func cleanupTemporaryFiles(for recordID: CKRecord.ID) {
        for url in temporaryFiles.removeValue(forKey: recordID) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func cleanupTemporaryFiles() {
        for urls in temporaryFiles.values {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
        temporaryFiles.removeAll()
    }
}

private final class SyncConflictSnapshotStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()

    func save(
        itemID: UUID,
        itemKind: SyncItemKind,
        localClock: SyncClock,
        remoteClock: SyncClock,
        encryptedPayload: Data
    ) throws {
        let snapshot = SyncConflictSnapshot(
            itemID: itemID,
            itemKind: itemKind,
            losingClock: localClock,
            winningClock: remoteClock,
            encryptedPayload: encryptedPayload
        )
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VaultCellSyncConflicts", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(itemID.uuidString).json")
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
