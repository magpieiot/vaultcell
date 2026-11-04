import Foundation

enum CloudSyncError: LocalizedError {
    case iCloudUnavailable
    case vaultLocked
    case invalidRecord(String)
    case partialFailure(String)
    case vaultMismatch
    case remoteKeyMaterialChanged

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return AppLocale.string("iCloud is unavailable. Check your account and try again.")
        case .vaultLocked:
            return AppLocale.string("Unlock the vault before syncing.")
        case .invalidRecord(let name):
            return AppLocale.string("Invalid iCloud record: \(name)")
        case .partialFailure(let detail):
            return AppLocale.string("Some items could not be synced: \(detail)")
        case .vaultMismatch:
            return AppLocale.string(
                "This device has a different vault from the one in iCloud. Back up the local vault, reset it, then restore the original vault from iCloud."
            )
        case .remoteKeyMaterialChanged:
            return AppLocale.string(
                "The master password was changed on another device. Use the latest password next time you unlock."
            )
        }
    }
}
