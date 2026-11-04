import CloudKit
import Foundation

/// 新设备只拉取包裹后的 DEK 和 KDF 材料；真正解锁仍需用户输入原主密码。
struct CloudVaultRestoreService {
    func fetchKeyMaterial() async throws -> CloudVaultKeyMaterial? {
        #if CN
        let containerID = "iCloud.com.magpie.vaultcell.cn"
        #else
        let containerID = "iCloud.com.magpie.vaultcell"
        #endif
        let container = CKContainer(identifier: containerID)
        guard try await container.accountStatus() == .available else {
            throw CloudSyncError.iCloudUnavailable
        }
        let zoneID = CKRecordZone.ID(
            zoneName: "VaultCellZone",
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: "vault-metadata", zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await container.privateCloudDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }

        guard let vaultIDString = record["vaultID"] as? String,
              let vaultID = UUID(uuidString: vaultIDString),
              let salt = record["salt"] as? Data,
              let wrappedDEK = record["wrappedDEK"] as? Data,
              let kdfAlgorithm = record["kdfAlgorithm"] as? String,
              let iterations = (record["kdfIterations"] as? NSNumber)?.intValue,
              let wrapAlgorithm = record["wrapAlgorithm"] as? String,
              let revision = (record["revision"] as? NSNumber)?.int64Value else {
            throw CloudSyncError.invalidRecord(recordID.recordName)
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
}
