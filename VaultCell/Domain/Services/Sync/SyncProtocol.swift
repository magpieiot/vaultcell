import Foundation

/// 云端冲突排序不依赖墙钟；mutationID 仅用于同一设备并发写入的最终决胜。
struct SyncClock: Codable, Equatable, Comparable, Sendable {
    let revision: Int64
    let lamport: Int64
    let deviceID: UUID
    let mutationID: UUID

    static func < (lhs: SyncClock, rhs: SyncClock) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.lamport != rhs.lamport { return lhs.lamport < rhs.lamport }
        let lhsDevice = lhs.deviceID.uuidString
        let rhsDevice = rhs.deviceID.uuidString
        if lhsDevice != rhsDevice { return lhsDevice < rhsDevice }
        return lhs.mutationID.uuidString < rhs.mutationID.uuidString
    }
}

struct LamportCounter: Codable, Equatable, Sendable {
    private(set) var value: Int64 = 0

    mutating func next(observing remoteValue: Int64? = nil) -> Int64 {
        value = max(value, remoteValue ?? 0) + 1
        return value
    }
}

enum SyncConflictDecision: Equatable, Sendable {
    case identical
    case localWins
    case remoteWins
}

enum SyncConflictResolver {
    static func resolve(local: SyncClock, remote: SyncClock) -> SyncConflictDecision {
        if local == remote { return .identical }
        return local > remote ? .localWins : .remoteWins
    }
}

enum SyncItemKind: String, Codable, Sendable {
    case password
    case safeNote
}

enum SyncProtocolLimits {
    static let inlinePayloadMaxBytes = 256 * 1024
}

/// 冲突输家保存完整密文，不能只保留密码值，否则其他字段和安全笔记无法恢复。
struct SyncConflictSnapshot: Codable, Equatable, Sendable {
    let itemID: UUID
    let itemKind: SyncItemKind
    let losingClock: SyncClock
    let winningClock: SyncClock
    let encryptedPayload: Data
}

enum SyncDeviceStatus: String, Codable, Sendable {
    case active
    case revoked
}

struct SyncDevice: Codable, Equatable, Sendable {
    let id: UUID
    var keyVersion: Int64
    var status: SyncDeviceStatus
}

/// 物理删除后仍保留在云端；只有所有活跃设备确认同一 mutation 后才允许回收。
struct SyncTombstone: Codable, Equatable, Sendable {
    let itemID: UUID
    let itemKind: SyncItemKind
    let clock: SyncClock
    private(set) var acknowledgedDeviceIDs: Set<UUID>

    init(
        itemID: UUID,
        itemKind: SyncItemKind,
        clock: SyncClock,
        acknowledgedDeviceIDs: Set<UUID> = []
    ) {
        self.itemID = itemID
        self.itemKind = itemKind
        self.clock = clock
        self.acknowledgedDeviceIDs = acknowledgedDeviceIDs
    }

    mutating func acknowledge(deviceID: UUID) {
        acknowledgedDeviceIDs.insert(deviceID)
    }

    func canBeCollected(devices: [SyncDevice]) -> Bool {
        let activeDeviceIDs = Set(devices.filter { $0.status == .active }.map(\.id))
        return !activeDeviceIDs.isEmpty && activeDeviceIDs.isSubset(of: acknowledgedDeviceIDs)
    }
}
