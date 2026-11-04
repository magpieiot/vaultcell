import Foundation
import Testing

@Suite("同步协议")
struct SyncProtocolTests {
    private let deviceA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let deviceB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let mutationA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let mutationB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func clock(
        revision: Int64 = 1,
        lamport: Int64 = 1,
        deviceID: UUID? = nil,
        mutationID: UUID? = nil
    ) -> SyncClock {
        SyncClock(
            revision: revision,
            lamport: lamport,
            deviceID: deviceID ?? deviceA,
            mutationID: mutationID ?? mutationA
        )
    }

    @Test("revision 优先于 Lamport")
    func revisionHasHighestPriority() {
        let local = clock(revision: 3, lamport: 1)
        let remote = clock(revision: 2, lamport: 100, deviceID: deviceB)
        #expect(SyncConflictResolver.resolve(local: local, remote: remote) == .localWins)
        #expect(SyncConflictResolver.resolve(local: remote, remote: local) == .remoteWins)
    }

    @Test("相同 revision 使用 Lamport")
    func lamportBreaksRevisionTie() {
        let local = clock(revision: 2, lamport: 8)
        let remote = clock(revision: 2, lamport: 7, deviceID: deviceB)
        #expect(SyncConflictResolver.resolve(local: local, remote: remote) == .localWins)
    }

    @Test("deviceID 和 mutationID 保证全序且与墙钟无关")
    func deterministicTieBreakers() {
        let local = clock(revision: 2, lamport: 8, deviceID: deviceB)
        let remote = clock(revision: 2, lamport: 8, deviceID: deviceA)
        #expect(SyncConflictResolver.resolve(local: local, remote: remote) == .localWins)

        let sameDeviceNewMutation = clock(mutationID: mutationB)
        #expect(SyncConflictResolver.resolve(local: sameDeviceNewMutation, remote: clock()) == .localWins)
        #expect(SyncConflictResolver.resolve(local: clock(), remote: clock()) == .identical)
    }

    @Test("Lamport 接收远端值后严格递增")
    func lamportObservesRemoteValue() {
        var counter = LamportCounter()
        #expect(counter.next() == 1)
        #expect(counter.next(observing: 41) == 42)
        #expect(counter.next(observing: 7) == 43)
    }

    @Test("本地保存只递增一次并保留上层已递增版本")
    func localRevisionIsMonotonic() {
        #expect(VaultSyncRevision.next(current: 4, proposed: 4) == 5)
        #expect(VaultSyncRevision.next(current: 4, proposed: 5) == 5)
        #expect(VaultSyncRevision.next(current: nil, proposed: 7) == 7)
    }

    @Test("墓碑只等待活跃设备确认")
    func tombstoneAcknowledgementsIgnoreRevokedDevices() throws {
        let tombstoneClock = clock()
        var tombstone = SyncTombstone(
            itemID: UUID(),
            itemKind: .password,
            clock: tombstoneClock
        )
        let active = SyncDevice(id: deviceA, keyVersion: 1, status: .active)
        let revoked = SyncDevice(id: deviceB, keyVersion: 1, status: .revoked)

        #expect(!tombstone.canBeCollected(devices: [active, revoked]))
        tombstone.acknowledge(deviceID: deviceA)
        #expect(tombstone.canBeCollected(devices: [active, revoked]))
        #expect(!tombstone.canBeCollected(devices: []))
        #expect(SyncProtocolLimits.inlinePayloadMaxBytes == 256 * 1024)
    }
}
