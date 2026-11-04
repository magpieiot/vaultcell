import CoreData
import Foundation

/// 主 App 与 AutoFill 必须使用完全一致的共享库配置。
enum VaultCoreDataStoreConfiguration {
    static let hostAuthor = "VaultCell"
    static let autoFillAuthor = "AutoFillProvider"

    static func configure(_ description: NSPersistentStoreDescription) {
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(
            FileProtectionType.complete as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(["busy_timeout": "5000"] as NSDictionary, forKey: NSSQLitePragmasOption)
    }
}
