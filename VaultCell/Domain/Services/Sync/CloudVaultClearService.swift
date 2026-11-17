import CloudKit
import Foundation

/// 清除私有 iCloud 数据库中的同步数据（整个自定义 zone 及其订阅）。
///
/// 只删云端：本地密码库、钥匙串与登录状态保持不变。
/// 调用方必须先关闭 iCloud 同步，否则 `CKSyncEngine` 会自动把 zone 重新建回来。
struct CloudVaultClearService {
    func clearCloudData() async throws {
        let containerID = "iCloud.com.magpie.vaultcell"
        let container = CKContainer(identifier: containerID)
        guard try await container.accountStatus() == .available else {
            throw CloudSyncError.iCloudUnavailable
        }

        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: "VaultCellZone",
            ownerName: CKCurrentUserDefaultName
        )
        do {
            try await database.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 云端本来就没有 zone：视为已清除，继续复位本机同步游标
        }

        // zone 订阅通常随 zone 一并删除；旧版本残留的独立订阅删不掉也不影响结果
        try? await database.deleteSubscription(withID: "vaultcell-private-sync")
    }
}
