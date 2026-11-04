import Foundation

/// 本地写入与云端回写必须使用不同的版本语义，避免云端记录落地后被再次标记为脏数据。
enum VaultWriteOrigin {
    case local
    case remote
}

enum VaultSyncRevision {
    static let initial: Int64 = 1

    /// 上层已经递增版本时沿用该版本；未递增时在持久化边界统一补齐。
    static func next(current: Int64?, proposed: Int64) -> Int64 {
        guard let current else { return max(initial, proposed) }
        return max(proposed, current + 1)
    }
}
