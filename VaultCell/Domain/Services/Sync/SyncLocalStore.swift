import CloudKit
import Foundation

struct SyncLocalTombstone: Codable, Equatable, Sendable {
    let itemID: UUID
    let itemKind: SyncItemKind
    let revision: Int64
    var clock: SyncClock?
    var isSynced: Bool
}

/// 保存设备级同步状态；仓储删除回调与主 actor 同步引擎均可安全访问。
final class SyncLocalStore: @unchecked Sendable {
    static let shared = SyncLocalStore()

    private let lock = NSRecursiveLock()
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let deviceKey = "vaultcell.sync.deviceID"
    private let stateKey = "vaultcell.sync.engineState"
    private let clocksKey = "vaultcell.sync.clocks"
    private let lamportKey = "vaultcell.sync.lamport"
    private let tombstonesKey = "vaultcell.sync.tombstones"
    private let initialUploadKey = "vaultcell.sync.initialUploadDone"
    private let assetIDsKey = "vaultcell.sync.assetIDs"
    private let serverRecordsKey = "vaultcell.sync.serverRecords"
    private let pendingRemoteKey = "vaultcell.sync.pendingRemoteRecords"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var deviceID: UUID {
        withLock {
            if let raw = defaults.string(forKey: deviceKey), let id = UUID(uuidString: raw) {
                return id
            }
            let id = UUID()
            defaults.set(id.uuidString, forKey: deviceKey)
            return id
        }
    }

    var stateSerialization: Data? {
        withLock { defaults.data(forKey: stateKey) }
    }

    var initialUploadDone: Bool {
        get { withLock { defaults.bool(forKey: initialUploadKey) } }
        set { withLock { defaults.set(newValue, forKey: initialUploadKey) } }
    }

    func saveStateSerialization(_ data: Data) {
        withLock { defaults.set(data, forKey: stateKey) }
    }

    func clock(for itemID: UUID) -> SyncClock? {
        withLock { allClocks()[itemID.uuidString] }
    }

    func saveClock(_ clock: SyncClock, for itemID: UUID) {
        withLock {
            var clocks = allClocks()
            clocks[itemID.uuidString] = clock
            saveClocks(clocks)
        }
    }

    func nextClock(for itemID: UUID, revision: Int64, observing remote: SyncClock? = nil) -> SyncClock {
        withLock {
            var clocks = allClocks()
            if let existing = clocks[itemID.uuidString], existing.revision == revision {
                return existing
            }
            let current = defaults.integer(forKey: lamportKey)
            let next = max(current, Int(remote?.lamport ?? 0)) + 1
            defaults.set(next, forKey: lamportKey)
            let clock = SyncClock(
                revision: revision,
                lamport: Int64(next),
                deviceID: deviceID,
                mutationID: UUID()
            )
            clocks[itemID.uuidString] = clock
            saveClocks(clocks)
            return clock
        }
    }

    func tombstones() -> [SyncLocalTombstone] {
        withLock {
            (try? decoder.decode([SyncLocalTombstone].self, from: defaults.data(forKey: tombstonesKey) ?? Data())) ?? []
        }
    }

    func recordTombstone(
        itemID: UUID,
        itemKind: SyncItemKind,
        revision: Int64,
        clock: SyncClock? = nil,
        isSynced: Bool = false
    ) {
        withLock {
            var items = tombstones()
            let tombstone = SyncLocalTombstone(
                itemID: itemID,
                itemKind: itemKind,
                revision: revision,
                clock: clock,
                isSynced: isSynced
            )
            if let index = items.firstIndex(where: { $0.itemID == itemID && $0.itemKind == itemKind }) {
                items[index] = tombstone
            } else {
                items.append(tombstone)
            }
            saveTombstones(items)
        }
    }

    func markTombstoneSynced(itemID: UUID, clock: SyncClock) {
        withLock {
            var items = tombstones()
            guard let index = items.firstIndex(where: { $0.itemID == itemID }) else { return }
            items[index].clock = clock
            items[index].isSynced = true
            saveTombstones(items)
        }
    }

    func uploadedAssetIDs(noteID: UUID) -> Set<UUID> {
        withLock {
            let values = defaults.stringArray(forKey: assetIDsKey + noteID.uuidString) ?? []
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
    }

    func saveUploadedAssetIDs(_ ids: Set<UUID>, noteID: UUID) {
        withLock {
            defaults.set(ids.map(\.uuidString).sorted(), forKey: assetIDsKey + noteID.uuidString)
        }
    }

    func addUploadedAssetID(_ assetID: UUID, noteID: UUID) {
        withLock {
            var ids = uploadedAssetIDs(noteID: noteID)
            ids.insert(assetID)
            saveUploadedAssetIDs(ids, noteID: noteID)
        }
    }

    func serverRecord(named recordName: String) -> CKRecord? {
        withLock {
            guard let data = allServerRecords()[recordName] else { return nil }
            return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? CKRecord
        }
    }

    func saveServerRecord(_ record: CKRecord) {
        withLock {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: record,
                requiringSecureCoding: true
            ) else { return }
            var records = allServerRecords()
            records[record.recordID.recordName] = data
            defaults.set(try? encoder.encode(records), forKey: serverRecordsKey)
        }
    }

    func removeServerRecord(named recordName: String) {
        withLock {
            var records = allServerRecords()
            records.removeValue(forKey: recordName)
            defaults.set(try? encoder.encode(records), forKey: serverRecordsKey)
        }
    }

    func pendingRemoteRecordNames() -> [String] {
        withLock { defaults.stringArray(forKey: pendingRemoteKey) ?? [] }
    }

    func addPendingRemoteRecordName(_ name: String) {
        withLock {
            var names = Set(defaults.stringArray(forKey: pendingRemoteKey) ?? [])
            names.insert(name)
            defaults.set(names.sorted(), forKey: pendingRemoteKey)
        }
    }

    func removePendingRemoteRecordName(_ name: String) {
        withLock {
            var names = Set(defaults.stringArray(forKey: pendingRemoteKey) ?? [])
            names.remove(name)
            defaults.set(names.sorted(), forKey: pendingRemoteKey)
        }
    }

    func resetForAccountChange() {
        withLock {
            defaults.removeObject(forKey: stateKey)
            defaults.removeObject(forKey: clocksKey)
            defaults.removeObject(forKey: initialUploadKey)
            defaults.removeObject(forKey: serverRecordsKey)
            defaults.removeObject(forKey: pendingRemoteKey)
        }
    }

    /// 重置密码库：连同删除记录与设备标识一起清空
    ///
    /// 新建的库会拿到新的 vaultID（新的 CloudKit zone），旧库的墓碑与本地时钟
    /// 若留下来，重新开启同步时会被当成新库的待上传删除，误删同名记录。
    func resetForVaultReset() {
        resetForAccountChange()
        withLock {
            defaults.removeObject(forKey: tombstonesKey)
            defaults.removeObject(forKey: lamportKey)
            defaults.removeObject(forKey: deviceKey)
        }
    }

    private func allServerRecords() -> [String: Data] {
        guard let data = defaults.data(forKey: serverRecordsKey) else { return [:] }
        return (try? decoder.decode([String: Data].self, from: data)) ?? [:]
    }

    private func allClocks() -> [String: SyncClock] {
        guard let data = defaults.data(forKey: clocksKey) else { return [:] }
        return (try? decoder.decode([String: SyncClock].self, from: data)) ?? [:]
    }

    private func saveClocks(_ clocks: [String: SyncClock]) {
        defaults.set(try? encoder.encode(clocks), forKey: clocksKey)
    }

    private func saveTombstones(_ items: [SyncLocalTombstone]) {
        defaults.set(try? encoder.encode(items), forKey: tombstonesKey)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
