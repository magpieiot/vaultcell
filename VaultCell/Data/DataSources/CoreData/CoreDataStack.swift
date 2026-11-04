/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CoreDataStack.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import CoreData
import Foundation

class CoreDataStack {
    static let shared = CoreDataStack()
    
    /// 当前构建变体对应的 App Group（CN 变体有独立的 bundle 与共享容器）。
    /// 必须与 AutoFillProvider 扩展一致，否则两边打开的是不同的数据库文件
    /// （表现为扩展保存成功、主 App 永远查不到）。
    private let appGroupIdentifier: String = {
        #if CN
        return "group.com.magpie.vaultcell.cn.shared"
        #else
        return "group.com.magpie.vaultcell.shared"
        #endif
    }()

    /// 线程安全的容器访问
    private let lock = NSLock()
    private var _container: NSPersistentContainer?

    /// 最近一次加载持久化存储时的错误（nil 表示加载成功）
    private(set) var loadError: Error?

    /// 跨进程（AutoFill 扩展）写入通知观察者；生命周期与单例一致，无需移除
    private var remoteChangeObserver: NSObjectProtocol?

    /// 持久化容器（线程安全懒加载，避免多线程并发初始化导致 "invalid reuse after initialization failure"）
    var container: NSPersistentContainer {
        lock.lock()
        defer { lock.unlock() }
        if let container = _container {
            return container
        }
        let result = createAndLoadContainer()
        _container = result.container
        loadError = result.error
        return result.container
    }

    /// 持久化存储是否已成功加载。
    ///
    /// 当协调器没有任何持久化存储时，Core Data 的 `save()` 会抛出无法被 Swift
    /// `catch` 捕获的 ObjC 异常（NSInternalInconsistencyException）并直接闪退，
    /// 因此所有保存前都必须先校验该状态。
    var isStoreLoaded: Bool {
        return !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.transactionAuthor = VaultCoreDataStoreConfiguration.hostAuthor
        return context
    }

    func saveContext() {
        guard isStoreLoaded else {
            print("⚠️ 持久化存储不可用，跳过保存以避免闪退：\(loadError?.localizedDescription ?? "unknown")")
            return
        }
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save Core Data: \(error.localizedDescription)")
            }
        }
    }

    /// 创建并加载持久化容器
    /// - Returns: 容器本身，以及加载持久化存储时的错误（成功时为 nil）
    private func createAndLoadContainer() -> (container: NSPersistentContainer, error: Error?) {
        let container = NSPersistentContainer(name: "VaultCell")

        // 确定存储位置：优先 App Group 容器，退化到 Application Support
        let storeURL: URL
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            storeURL = groupURL.appendingPathComponent("VaultCell.sqlite")
        } else {
            let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            storeURL = supportURL.appendingPathComponent("VaultCell.sqlite")
        }

        // 与扩展侧日志对照可确认两端打开的是同一份数据库（App Group 不一致时两边各存一份）
        NSLog("CoreData: 数据库路径=%@", storeURL.path)

        let description = NSPersistentStoreDescription(url: storeURL)
        VaultCoreDataStoreConfiguration.configure(description)
        container.persistentStoreDescriptions = [description]

        // 加载持久化存储
        // loadPersistentStores 对本地 SQLite 存储为同步调用，完成回调在方法返回前执行
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let error = loadError {
            // 不使用 fatalError：密码库加载失败时应让应用继续运行，
            // 由上层（PasswordVaultService / ViewModel）捕获错误并向用户展示，
            // 而不是直接崩溃导致用户失去对全部密码的访问
            print("❌ Core Data load failed: \(error.localizedDescription)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = VaultCoreDataStoreConfiguration.hostAuthor

        // 跨进程写入感知：扩展保存密码后主 App 的界面必须知道数据变了。
        // 只靠 AppState 回前台比对时间戳不够——主 App 一直留在前台时不会触发，
        // 因此这里在收到别的进程提交时直接广播，让列表重新加载。
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak container] _ in
            NSLog("CoreData: 检测到其它进程写入共享数据库（AutoFill 扩展）")
            container?.viewContext.perform {
                guard let context = container?.viewContext else { return }
                // 主 App 用 viewContext 直接写入并即时保存，正常没有未提交更改；
                // 万一有（编辑中未保存），不能 refresh，否则会丢掉用户刚输入的内容
                guard !context.hasChanges else { return }
                context.refreshAllObjects()
            }
            NotificationCenter.default.post(name: .autoFillDidSaveCredential, object: nil)
        }

        return (container, loadError)
    }
}

final class CoreDataDataSource: @unchecked Sendable {
    let context: NSManagedObjectContext
    let encryptionService: EncryptionServiceProtocol
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext,
         encryptionService: EncryptionServiceProtocol = EncryptionService.shared) {
        self.context = context
        self.encryptionService = encryptionService
    }

    /// 持久化存储是否可用。
    ///
    /// 当协调器没有任何持久化存储时（迁移失败等），Core Data 的 `save()`
    /// 会抛出无法被 Swift `catch` 捕获的 ObjC 异常并直接闪退，因此保存前必须校验。
    var isStoreAvailable: Bool {
        !(context.persistentStoreCoordinator?.persistentStores.isEmpty ?? true)
    }

    /// 统一的保存入口：持久化存储不可用时安全跳过（返回 false），避免闪退
    @discardableResult
    func saveIfPossible() throws -> Bool {
        guard isStoreAvailable else {
            print("⚠️ 持久化存储不可用，跳过保存以避免闪退")
            return false
        }
        if context.hasChanges {
            try context.save()
        }
        return true
    }
    
    private func optionalBoolNumber(from value: Bool?) -> NSNumber? {
        value.map { NSNumber(value: $0) }
    }
    
    private func optionalBoolValue(from value: NSNumber?) -> Bool? {
        value?.boolValue
    }

    private func encryptCodable<T: Codable>(_ value: T) throws -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try encryptionService.encrypt(data).combined
    }
    
    private func decryptCodable<T: Codable>(_ data: Data) throws -> T {
        let decryptedData = try encryptionService.decryptToData(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: decryptedData)
    }
    
    func fetchAllPasswords() throws -> [CDPasswordEntry] {
        let request: NSFetchRequest<CDPasswordEntry> = CDPasswordEntry.fetchRequest()
        let sortDescriptor = NSSortDescriptor(key: "siteName", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return try context.fetch(request)
    }
    
    func fetchPassword(by id: UUID) throws -> CDPasswordEntry? {
        let request: NSFetchRequest<CDPasswordEntry> = CDPasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }
    
    func searchPasswords(query: String) throws -> [CDPasswordEntry] {
        let request: NSFetchRequest<CDPasswordEntry> = CDPasswordEntry.fetchRequest()
        let predicate = NSPredicate(format: "siteName CONTAINS[cd] %@ OR username CONTAINS[cd] %@ OR siteURL CONTAINS[cd] %@", query, query, query)
        request.predicate = predicate
        let sortDescriptor = NSSortDescriptor(key: "siteName", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return try context.fetch(request)
    }
    
    func createPasswordEntry(from entry: PasswordEntry) throws -> CDPasswordEntry {
        let cdEntry = CDPasswordEntry(context: context)
        cdEntry.id = entry.id
        cdEntry.siteName = entry.siteName
        cdEntry.siteURL = entry.siteURL
        cdEntry.username = entry.username
        cdEntry.encryptedPassword = try encryptionService.encrypt(entry.password).combined
        if let notes = entry.notes {
            cdEntry.encryptedNotes = try encryptionService.encrypt(notes).combined
        }
        cdEntry.categoryID = entry.categoryID
        try syncTagsRelationship(on: cdEntry, from: entry.tags ?? [])
        cdEntry.isFavorite = entry.isFavorite
        cdEntry.passwordStrengthRaw = Int16((entry.passwordStrength ?? .medium).rawValue)
        cdEntry.createdAt = entry.createdAt ?? Date()
        cdEntry.updatedAt = entry.updatedAt ?? Date()
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.deletedAt = entry.deletedAt
        cdEntry.icon = entry.icon
        cdEntry.has2FA = entry.has2FA
        cdEntry.bundlePhoneNumber = entry.bundlePhoneNumber
        cdEntry.bundleEmailAddress = entry.bundleEmailAddress
        cdEntry.hasBundlePhone = !(entry.bundlePhoneNumber?.isEmpty ?? true)
        cdEntry.hasBundleEmail = !(entry.bundleEmailAddress?.isEmpty ?? true)
        cdEntry.isPasswordResetEmail = entry.isPasswordResetEmail
        cdEntry.isPasswordResetPhone = entry.isPasswordResetPhone
        cdEntry.passwordChangedAt = entry.passwordChangedAt
        cdEntry.version = entry.version
        cdEntry.isSynced = entry.isSynced
        cdEntry.isDuplicatePassword = entry.isDuplicatePassword
        cdEntry.breachStatusRaw = Int16((entry.breachStatus ?? .unknown).rawValue)
        cdEntry.accountStatusRaw = Int16((entry.accountStatus ?? .active).rawValue)
        cdEntry.dataSourceRaw = Int16((entry.dataSource ?? .manual).rawValue)

        if let oauth = entry.oAuthProvider {
            cdEntry.passwordlessLoginTypeRaw = PasswordlessLoginType.oauth.rawValue
            cdEntry.OAuthProviderID = oauth.provider

            let cdOAuth = CDOAuthProvider(context: context)
            cdOAuth.id = oauth.providerID
            if let secret = oauth.secret {
                cdOAuth.encryptedSecret = try encryptionService.encrypt(secret).combined
            }
            cdOAuth.provider = oauth.provider
            cdOAuth.boundValue = oauth.boundValue
            cdOAuth.isEnabled = oauth.isEnabled
            cdOAuth.lastVerifiedAt = oauth.lastVerifiedAt
            cdOAuth.expiresAt = oauth.expiresAt
            cdOAuth.notes = oauth.notes
            cdOAuth.passwordEntry = cdEntry
            cdEntry.oAuthProvider = cdOAuth
        } else {
            cdEntry.passwordlessLoginTypeRaw = PasswordlessLoginType.none.rawValue
            cdEntry.OAuthProviderID = nil
            cdEntry.oAuthProvider = nil
        }

        if let passwordHistory = entry.passwordHistory, !passwordHistory.isEmpty {
            cdEntry.encryptedPasswordHistory = try encryptCodable(passwordHistory)
        }
        if let customFields = entry.customFields, !customFields.isEmpty {
            cdEntry.encryptedCustomFields = try encryptCodable(customFields)
        }

        for config in entry.twoFactorConfigs ?? [] {
            let cdConfig = CDTwoFactorConfig(context: context)
            cdConfig.id = config.id
            cdConfig.type = config.type.rawValue
            if let secret = config.secret {
                cdConfig.encryptedSecret = try encryptionService.encrypt(secret).combined
            }
            cdConfig.algorithm = config.algorithm
            cdConfig.digits = Int16(clamping: config.digits)
            cdConfig.period = Int16(clamping: config.period)
            cdConfig.issuer = config.issuer
            cdConfig.boundValue = config.boundValue
            cdConfig.isEnabled = config.isEnabled
            cdConfig.lastVerifiedAt = config.lastVerifiedAt
            cdConfig.expiresAt = config.expiresAt
            cdConfig.notes = config.notes
            cdConfig.passwordEntry = cdEntry
        }
        
        return cdEntry
    }
    
    func savePasswordEntry(
        _ entry: PasswordEntry,
        origin: VaultWriteOrigin = .local
    ) throws {
        var persistedEntry = entry
        if let existing = try fetchPassword(by: entry.id) {
            if origin == .local {
                persistedEntry.version = VaultSyncRevision.next(
                    current: existing.version,
                    proposed: entry.version
                )
                persistedEntry.isSynced = false
            } else {
                persistedEntry.isSynced = true
            }
            try updatePasswordEntry(existing, from: persistedEntry)
        } else {
            persistedEntry.version = max(VaultSyncRevision.initial, entry.version)
            persistedEntry.isSynced = origin == .remote
            _ = try createPasswordEntry(from: persistedEntry)
        }
        try saveIfPossible()
    }

    func markPasswordSynced(_ id: UUID) throws {
        guard let entry = try fetchPassword(by: id) else { return }
        entry.isSynced = true
        try saveIfPossible()
    }
    
    func updatePasswordEntry(_ cdEntry: CDPasswordEntry, from entry: PasswordEntry) throws {
        cdEntry.siteName = entry.siteName
        cdEntry.siteURL = entry.siteURL
        cdEntry.username = entry.username
        cdEntry.encryptedPassword = try encryptionService.encrypt(entry.password).combined
        if let notes = entry.notes {
            cdEntry.encryptedNotes = try encryptionService.encrypt(notes).combined
        } else {
            cdEntry.encryptedNotes = nil
        }
        cdEntry.categoryID = entry.categoryID
        try syncTagsRelationship(on: cdEntry, from: entry.tags ?? [])
        cdEntry.isFavorite = entry.isFavorite
        cdEntry.passwordStrengthRaw = Int16((entry.passwordStrength ?? .medium).rawValue)
        cdEntry.updatedAt = entry.updatedAt ?? Date()
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.deletedAt = entry.deletedAt
        cdEntry.icon = entry.icon
        cdEntry.has2FA = entry.has2FA
        cdEntry.bundlePhoneNumber = entry.bundlePhoneNumber
        cdEntry.bundleEmailAddress = entry.bundleEmailAddress
        cdEntry.hasBundlePhone = !(entry.bundlePhoneNumber?.isEmpty ?? true)
        cdEntry.hasBundleEmail = !(entry.bundleEmailAddress?.isEmpty ?? true)
        cdEntry.isPasswordResetEmail = entry.isPasswordResetEmail
        cdEntry.isPasswordResetPhone = entry.isPasswordResetPhone
        cdEntry.passwordChangedAt = entry.passwordChangedAt
        cdEntry.version = entry.version
        cdEntry.isSynced = entry.isSynced
        cdEntry.isDuplicatePassword = entry.isDuplicatePassword
        cdEntry.breachStatusRaw = Int16((entry.breachStatus ?? .unknown).rawValue)
        cdEntry.accountStatusRaw = Int16((entry.accountStatus ?? .active).rawValue)
        cdEntry.dataSourceRaw = Int16((entry.dataSource ?? .manual).rawValue)

        if let existingOAuth = cdEntry.oAuthProvider {
            context.delete(existingOAuth)
            cdEntry.oAuthProvider = nil
        }

        if let oauth = entry.oAuthProvider {
            cdEntry.passwordlessLoginTypeRaw = PasswordlessLoginType.oauth.rawValue
            cdEntry.OAuthProviderID = oauth.provider

            let cdOAuth = CDOAuthProvider(context: context)
            cdOAuth.id = oauth.providerID
            if let secret = oauth.secret {
                cdOAuth.encryptedSecret = try encryptionService.encrypt(secret).combined
            }
            cdOAuth.provider = oauth.provider
            cdOAuth.boundValue = oauth.boundValue
            cdOAuth.isEnabled = oauth.isEnabled
            cdOAuth.lastVerifiedAt = oauth.lastVerifiedAt
            cdOAuth.expiresAt = oauth.expiresAt
            cdOAuth.notes = oauth.notes
            cdOAuth.passwordEntry = cdEntry
            cdEntry.oAuthProvider = cdOAuth
        } else {
            cdEntry.passwordlessLoginTypeRaw = PasswordlessLoginType.none.rawValue
            cdEntry.OAuthProviderID = nil
            cdEntry.oAuthProvider = nil
        }

        if let passwordHistory = entry.passwordHistory, !passwordHistory.isEmpty {
            cdEntry.encryptedPasswordHistory = try encryptCodable(passwordHistory)
        } else {
            cdEntry.encryptedPasswordHistory = nil
        }
        if let customFields = entry.customFields, !customFields.isEmpty {
            cdEntry.encryptedCustomFields = try encryptCodable(customFields)
        } else {
            cdEntry.encryptedCustomFields = nil
        }


        if let existingConfigs = cdEntry.twoFactorConfigs?.allObjects as? [CDTwoFactorConfig] {
            for config in existingConfigs {
                context.delete(config)
            }
        }
        
        for config in entry.twoFactorConfigs ?? [] {
            let cdConfig = CDTwoFactorConfig(context: context)
            cdConfig.id = config.id
            cdConfig.type = config.type.rawValue
            if let secret = config.secret {
                cdConfig.encryptedSecret = try encryptionService.encrypt(secret).combined
            }
            cdConfig.algorithm = config.algorithm
            cdConfig.digits = Int16(clamping: config.digits)
            cdConfig.period = Int16(clamping: config.period)
            cdConfig.issuer = config.issuer
            cdConfig.boundValue = config.boundValue
            cdConfig.isEnabled = config.isEnabled
            cdConfig.lastVerifiedAt = config.lastVerifiedAt
            cdConfig.expiresAt = config.expiresAt
            cdConfig.notes = config.notes
            cdConfig.passwordEntry = cdEntry
        }
    }
    
    func deletePasswordEntry(_ id: UUID, origin: VaultWriteOrigin = .local) throws {
        if let entry = try fetchPassword(by: id) {
            if origin == .local {
                SyncLocalStore.shared.recordTombstone(
                    itemID: id,
                    itemKind: .password,
                    revision: entry.version
                )
            }
            context.delete(entry)
            try saveIfPossible()
        }
    }

    func fetchAllBankcards() throws -> [CDBankcardEntry] {
        let request: NSFetchRequest<CDBankcardEntry> = CDBankcardEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "bankName", ascending: true)]
        return try context.fetch(request)
    }
    
    func fetchBankcard(by id: UUID) throws -> CDBankcardEntry? {
        let request: NSFetchRequest<CDBankcardEntry> = CDBankcardEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }
    
    func searchBankcards(query: String) throws -> [CDBankcardEntry] {
        let request: NSFetchRequest<CDBankcardEntry> = CDBankcardEntry.fetchRequest()
        request.predicate = NSPredicate(format: "bankName CONTAINS[cd] %@ OR cardholder CONTAINS[cd] %@", query, query)
        request.sortDescriptors = [NSSortDescriptor(key: "bankName", ascending: true)]
        return try context.fetch(request)
    }
    
    func createBankcardEntry(from entry: BankcardEntry) throws -> CDBankcardEntry {
        let cdEntry = CDBankcardEntry(context: context)
        cdEntry.id = entry.id
        cdEntry.bankName = entry.bankName
        cdEntry.encryptedCardNumber = try encryptionService.encrypt(entry.cardNumber).combined
        if let cvv = entry.cvv {
            cdEntry.encryptedCvv = try encryptionService.encrypt(cvv).combined
        }
        cdEntry.cardholder = entry.cardholder
        cdEntry.expiryDate = entry.expiryDate
        if let pin = entry.pin {
            cdEntry.encryptedPin = try encryptionService.encrypt(pin).combined
        }
        cdEntry.issuingChannel = entry.issuingChannel
        if let onlineBankingPassword = entry.onlineBankingPassword {
            cdEntry.encryptedOnlineBankingPassword = try encryptionService.encrypt(onlineBankingPassword).combined
        }
        cdEntry.cardTypeRaw = Int16(entry.cardType.map { $0.rawValue + 1 } ?? 0)
        cdEntry.cardNetworks = joinedNetworks(entry.cardNetworks ?? [])
        if let notes = entry.notes {
            cdEntry.encryptedNotes = try encryptionService.encrypt(notes).combined
        }
        cdEntry.categoryID = entry.categoryID
        try syncTagsRelationship(on: cdEntry, from: entry.tags ?? [])
        cdEntry.isFavorite = entry.isFavorite
        if let customFields = entry.customFields, !customFields.isEmpty {
            cdEntry.encryptedCustomFields = try encryptCodable(customFields)
        }
        cdEntry.version = entry.version
        cdEntry.isSynced = entry.isSynced
        cdEntry.createdAt = entry.createdAt ?? Date()
        cdEntry.updatedAt = entry.updatedAt ?? Date()
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.deletedAt = entry.deletedAt
        cdEntry.icon = entry.icon
        cdEntry.dataSourceRaw = Int16((entry.dataSource ?? .manual).rawValue)
        return cdEntry
    }
    
    func saveBankcardEntry(_ entry: BankcardEntry) throws {
        if let existing = try fetchBankcard(by: entry.id) {
            try updateBankcardEntry(existing, from: entry)
        } else {
            _ = try createBankcardEntry(from: entry)
        }
        try saveIfPossible()
    }
    
    func updateBankcardEntry(_ cdEntry: CDBankcardEntry, from entry: BankcardEntry) throws {
        cdEntry.bankName = entry.bankName
        cdEntry.encryptedCardNumber = try encryptionService.encrypt(entry.cardNumber).combined
        if let cvv = entry.cvv {
            cdEntry.encryptedCvv = try encryptionService.encrypt(cvv).combined
        } else {
            cdEntry.encryptedCvv = nil
        }
        cdEntry.cardholder = entry.cardholder
        cdEntry.expiryDate = entry.expiryDate
        if let pin = entry.pin {
            cdEntry.encryptedPin = try encryptionService.encrypt(pin).combined
        } else {
            cdEntry.encryptedPin = nil
        }
        cdEntry.issuingChannel = entry.issuingChannel
        if let onlineBankingPassword = entry.onlineBankingPassword {
            cdEntry.encryptedOnlineBankingPassword = try encryptionService.encrypt(onlineBankingPassword).combined
        } else {
            cdEntry.encryptedOnlineBankingPassword = nil
        }
        cdEntry.cardTypeRaw = Int16(entry.cardType.map { $0.rawValue + 1 } ?? 0)
        cdEntry.cardNetworks = joinedNetworks(entry.cardNetworks ?? [])
        if let notes = entry.notes {
            cdEntry.encryptedNotes = try encryptionService.encrypt(notes).combined
        } else {
            cdEntry.encryptedNotes = nil
        }
        cdEntry.categoryID = entry.categoryID
        try syncTagsRelationship(on: cdEntry, from: entry.tags ?? [])
        cdEntry.isFavorite = entry.isFavorite
        if let customFields = entry.customFields, !customFields.isEmpty {
            cdEntry.encryptedCustomFields = try encryptCodable(customFields)
        } else {
            cdEntry.encryptedCustomFields = nil
        }
        cdEntry.version = entry.version
        cdEntry.isSynced = entry.isSynced
        cdEntry.updatedAt = entry.updatedAt ?? Date()
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.deletedAt = entry.deletedAt
        cdEntry.icon = entry.icon
        cdEntry.dataSourceRaw = Int16((entry.dataSource ?? .manual).rawValue)
    }
    
    func deleteBankcardEntry(_ id: UUID) throws {
        if let entry = try fetchBankcard(by: id) {
            context.delete(entry)
            try saveIfPossible()
        }
    }
    
    func fetchAllPincodes() throws -> [CDPincodeEntry] {
        let request: NSFetchRequest<CDPincodeEntry> = CDPincodeEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return try context.fetch(request)
    }
    
    func fetchPincode(by id: UUID) throws -> CDPincodeEntry? {
        let request: NSFetchRequest<CDPincodeEntry> = CDPincodeEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }
    
    func searchPincodes(query: String) throws -> [CDPincodeEntry] {
        let request: NSFetchRequest<CDPincodeEntry> = CDPincodeEntry.fetchRequest()
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", query)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return try context.fetch(request)
    }
    
    func createPincodeEntry(from entry: PincodeEntry) throws -> CDPincodeEntry {
        let cdEntry = CDPincodeEntry(context: context)
        cdEntry.id = entry.id
        cdEntry.title = entry.title
        cdEntry.encryptedPincode = try encryptionService.encrypt(entry.pincode).combined
        if let notes = entry.notes {
            cdEntry.encryptedNotes = try encryptionService.encrypt(notes).combined
        }
        cdEntry.categoryID = entry.categoryID
        try syncTagsRelationship(on: cdEntry, from: entry.tags ?? [])
        cdEntry.isFavorite = entry.isFavorite
        cdEntry.isNumericOnly = entry.isNumericOnly
        cdEntry.createdAt = entry.createdAt ?? Date()
        cdEntry.updatedAt = entry.updatedAt ?? Date()
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.deletedAt = entry.deletedAt
        cdEntry.icon = entry.icon
        cdEntry.version = entry.version
        cdEntry.isSynced = entry.isSynced
        cdEntry.dataSourceRaw = Int16((entry.dataSource ?? .manual).rawValue)
        
        if let pincodeHistory = entry.pincodeHistory, !pincodeHistory.isEmpty {
            cdEntry.encryptedPincodeHistory = try encryptCodable(pincodeHistory)
        }
        if let customFields = entry.customFields, !customFields.isEmpty {
            cdEntry.encryptedCustomFields = try encryptCodable(customFields)
        }
        
        return cdEntry
    }
    
    func savePincodeEntry(_ entry: PincodeEntry) throws {
        if let existing = try fetchPincode(by: entry.id) {
            try updatePincodeEntry(existing, from: entry)
        } else {
            _ = try createPincodeEntry(from: entry)
        }
        try saveIfPossible()
    }
    
    func updatePincodeEntry(_ cdEntry: CDPincodeEntry, from entry: PincodeEntry) throws {
        cdEntry.title = entry.title
        cdEntry.encryptedPincode = try encryptionService.encrypt(entry.pincode).combined
        if let notes = entry.notes {
            cdEntry.encryptedNotes = try encryptionService.encrypt(notes).combined
        } else {
            cdEntry.encryptedNotes = nil
        }
        cdEntry.categoryID = entry.categoryID
        try syncTagsRelationship(on: cdEntry, from: entry.tags ?? [])
        cdEntry.isFavorite = entry.isFavorite
        cdEntry.isNumericOnly = entry.isNumericOnly
        cdEntry.updatedAt = entry.updatedAt ?? Date()
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.deletedAt = entry.deletedAt
        cdEntry.icon = entry.icon
        cdEntry.version = entry.version
        cdEntry.isSynced = entry.isSynced
        cdEntry.dataSourceRaw = Int16((entry.dataSource ?? .manual).rawValue)
        
        if let pincodeHistory = entry.pincodeHistory, !pincodeHistory.isEmpty {
            cdEntry.encryptedPincodeHistory = try encryptCodable(pincodeHistory)
        } else {
            cdEntry.encryptedPincodeHistory = nil
        }
        if let customFields = entry.customFields, !customFields.isEmpty {
            cdEntry.encryptedCustomFields = try encryptCodable(customFields)
        } else {
            cdEntry.encryptedCustomFields = nil
        }
    }
    
    func deletePincodeEntry(_ id: UUID) throws {
        if let entry = try fetchPincode(by: id) {
            context.delete(entry)
            try saveIfPossible()
        }
    }

    func fetchAllSafeNotes() throws -> [CDSafeNote] {
        let request: NSFetchRequest<CDSafeNote> = CDSafeNote.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(request)
    }

    func fetchSafeNote(by id: UUID) throws -> CDSafeNote? {
        let request: NSFetchRequest<CDSafeNote> = CDSafeNote.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func createSafeNote(from note: SafeNote) throws -> CDSafeNote {
        let cdNote = CDSafeNote(context: context)
        cdNote.id = note.id
        cdNote.encryptedTitle = try encryptionService.encrypt(note.title).combined
        cdNote.encryptedContent = try encryptionService.encrypt(note.content).combined
        cdNote.coverAssetID = note.coverAssetID
        cdNote.imageCount = Int32(note.assets.count)
        cdNote.isFavorite = note.isFavorite
        cdNote.createdAt = note.createdAt
        cdNote.updatedAt = note.updatedAt
        cdNote.lastViewedAt = note.lastViewedAt
        cdNote.deletedAt = note.deletedAt
        cdNote.version = note.version
        cdNote.isSynced = note.isSynced
        cdNote.dataSourceRaw = Int16(note.dataSource.rawValue)

        try syncSafeNoteAssets(on: cdNote, from: note.assets)
        return cdNote
    }

    func saveSafeNote(
        _ note: SafeNote,
        origin: VaultWriteOrigin = .local
    ) throws {
        var persistedNote = note
        if let existing = try fetchSafeNote(by: note.id) {
            if origin == .local {
                persistedNote.version = VaultSyncRevision.next(
                    current: existing.version,
                    proposed: note.version
                )
                persistedNote.isSynced = false
            } else {
                persistedNote.isSynced = true
            }
            try updateSafeNote(existing, from: persistedNote)
        } else {
            persistedNote.version = max(VaultSyncRevision.initial, note.version)
            persistedNote.isSynced = origin == .remote
            _ = try createSafeNote(from: persistedNote)
        }
        try saveIfPossible()
    }

    func markSafeNoteSynced(_ id: UUID) throws {
        guard let note = try fetchSafeNote(by: id) else { return }
        note.isSynced = true
        try saveIfPossible()
    }

    func updateSafeNote(_ cdNote: CDSafeNote, from note: SafeNote) throws {
        cdNote.encryptedTitle = try encryptionService.encrypt(note.title).combined
        cdNote.encryptedContent = try encryptionService.encrypt(note.content).combined
        cdNote.coverAssetID = note.coverAssetID
        cdNote.imageCount = Int32(note.assets.count)
        cdNote.isFavorite = note.isFavorite
        cdNote.updatedAt = note.updatedAt
        cdNote.lastViewedAt = note.lastViewedAt
        cdNote.deletedAt = note.deletedAt
        cdNote.version = note.version
        cdNote.isSynced = note.isSynced
        cdNote.dataSourceRaw = Int16(note.dataSource.rawValue)

        try syncSafeNoteAssets(on: cdNote, from: note.assets)
    }

    func deleteSafeNote(_ id: UUID, origin: VaultWriteOrigin = .local) throws {
        if let note = try fetchSafeNote(by: id) {
            if origin == .local {
                SyncLocalStore.shared.recordTombstone(
                    itemID: id,
                    itemKind: .safeNote,
                    revision: note.version
                )
            }
            context.delete(note)
            try saveIfPossible()
        }
    }

    func fetchAllCategories() throws -> [CDPasswordCategory] {
        let request: NSFetchRequest<CDPasswordCategory> = CDPasswordCategory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request)
    }

    func fetchCategory(by id: UUID) throws -> CDPasswordCategory? {
        let request: NSFetchRequest<CDPasswordCategory> = CDPasswordCategory.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func createCategory(from category: PasswordCategory) throws {
        let cdCategory = CDPasswordCategory(context: context)
        cdCategory.id = category.id
        cdCategory.name = category.name
        cdCategory.icon = category.icon
        cdCategory.hexColor = category.hexColor
        cdCategory.isSystem = category.isSystem
        cdCategory.sortOrder = category.sortOrder
        cdCategory.createdAt = category.createdAt
        cdCategory.updatedAt = category.updatedAt
        try saveIfPossible()
    }

    func updateCategory(_ cdCategory: CDPasswordCategory, from category: PasswordCategory) throws {
        cdCategory.name = category.name
        cdCategory.icon = category.icon
        cdCategory.hexColor = category.hexColor
        cdCategory.sortOrder = category.sortOrder
        cdCategory.updatedAt = category.updatedAt
        try saveIfPossible()
    }

    func deleteCategory(_ id: UUID) throws {
        if let category = try fetchCategory(by: id) {
            if category.isSystem { return }
            context.delete(category)
            try saveIfPossible()
        }
    }

    /// 把某个分类下的全部条目（密码 / PIN 码 / 银行卡，含回收站中的条目）迁移到目标分类。
    ///
    /// 删除自定义分类前调用，避免条目保留指向已删除分类的 `categoryID`。
    /// - Returns: 实际迁移的条目总数
    @discardableResult
    func reassignCategoryEntries(from sourceID: UUID, to targetID: UUID) throws -> Int {
        guard sourceID != targetID else { return 0 }
        var migrated = 0

        let passwordRequest: NSFetchRequest<CDPasswordEntry> = CDPasswordEntry.fetchRequest()
        passwordRequest.predicate = NSPredicate(format: "categoryID == %@", sourceID as CVarArg)
        for entry in try context.fetch(passwordRequest) {
            entry.categoryID = targetID
            migrated += 1
        }

        let pincodeRequest: NSFetchRequest<CDPincodeEntry> = CDPincodeEntry.fetchRequest()
        pincodeRequest.predicate = NSPredicate(format: "categoryID == %@", sourceID as CVarArg)
        for entry in try context.fetch(pincodeRequest) {
            entry.categoryID = targetID
            migrated += 1
        }

        let bankcardRequest: NSFetchRequest<CDBankcardEntry> = CDBankcardEntry.fetchRequest()
        bankcardRequest.predicate = NSPredicate(format: "categoryID == %@", sourceID as CVarArg)
        for entry in try context.fetch(bankcardRequest) {
            entry.categoryID = targetID
            migrated += 1
        }

        if migrated > 0 {
            try saveIfPossible()
        }
        return migrated
    }

    func convertToPasswordCategory(_ cdCategory: CDPasswordCategory) -> PasswordCategory {
        PasswordCategory(
            id: cdCategory.id,
            name: cdCategory.name,
            icon: cdCategory.icon,
            hexColor: cdCategory.hexColor,
            isSystem: cdCategory.isSystem,
            sortOrder: cdCategory.sortOrder,
            createdAt: cdCategory.createdAt,
            updatedAt: cdCategory.updatedAt
        )
    }

    func ensureDefaultCategories() throws {
        let existing = try fetchAllCategories()

        if existing.isEmpty {
            for category in PasswordCategory.systemDefaults {
                insertCategory(category)
            }
            try saveIfPossible()
            return
        }

        // 已有分类时补齐后续版本新增的系统分类（系统分类不可删除/重命名，缺失即为新增）：
        // 先把占位顺序让出来，再插入，保证展示顺序与 systemDefaults 一致。
        let existingIDs = Set(existing.map(\.id))
        let missing = PasswordCategory.systemDefaults.filter { !existingIDs.contains($0.id) }
        guard !missing.isEmpty else { return }

        for category in missing {
            for cdCategory in existing where cdCategory.sortOrder >= category.sortOrder {
                cdCategory.sortOrder += 1
            }
            insertCategory(category)
        }
        try saveIfPossible()
    }

    private func insertCategory(_ category: PasswordCategory) {
        let cdCategory = CDPasswordCategory(context: context)
        cdCategory.id = category.id
        cdCategory.name = category.name
        cdCategory.icon = category.icon
        cdCategory.hexColor = category.hexColor
        cdCategory.isSystem = category.isSystem
        cdCategory.sortOrder = category.sortOrder
        cdCategory.createdAt = category.createdAt
        cdCategory.updatedAt = category.updatedAt
    }

    // MARK: - Tag CRUD

    func fetchAllTags() throws -> [CDTag] {
        let request: NSFetchRequest<CDTag> = CDTag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request)
    }

    func fetchTag(by id: UUID) throws -> CDTag? {
        let request: NSFetchRequest<CDTag> = CDTag.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func fetchTagByName(_ name: String) throws -> CDTag? {
        let request: NSFetchRequest<CDTag> = CDTag.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[cd] %@", name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func createTag(from tag: Tag) throws {
        let cdTag = CDTag(context: context)
        cdTag.id = tag.id
        cdTag.name = tag.name
        cdTag.hexColor = tag.hexColor
        cdTag.sortOrder = tag.sortOrder
        cdTag.createdAt = tag.createdAt
        cdTag.updatedAt = tag.updatedAt
        try saveIfPossible()
    }

    func updateTag(_ cdTag: CDTag, from tag: Tag) throws {
        cdTag.name = tag.name
        cdTag.hexColor = tag.hexColor
        cdTag.sortOrder = tag.sortOrder
        cdTag.updatedAt = tag.updatedAt
        try saveIfPossible()
    }

    func deleteTag(_ id: UUID) throws {
        if let tag = try fetchTag(by: id) {
            context.delete(tag)
            try saveIfPossible()
        }
    }

    func ensureDefaultTags() throws {
        if try fetchAllTags().isEmpty {
            let entries = try fetchAllPasswords()

            var extracted: [String] = []
            extracted.reserveCapacity(entries.count * 2)

            for entry in entries {
                if let names = entry.tagsRelationship?.allObjects as? [CDTag] {
                    extracted.append(contentsOf: names.map(\.name))
                }

                if let legacy = entry.tags, !legacy.isEmpty {
                    extracted.append(contentsOf: legacy.split(separator: ",").map { String($0) })
                }
            }

            var unique: [String] = []
            unique.reserveCapacity(extracted.count)
            var seen = Set<String>()

            for name in extracted {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if seen.insert(key).inserted {
                    unique.append(trimmed)
                }
            }

            if unique.isEmpty {
                for tag in Tag.systemDefaults {
                    let cdTag = CDTag(context: context)
                    cdTag.id = tag.id
                    cdTag.name = tag.name
                    cdTag.hexColor = tag.hexColor
                    cdTag.sortOrder = tag.sortOrder
                    cdTag.createdAt = tag.createdAt
                    cdTag.updatedAt = tag.updatedAt
                }
            } else {
                for (index, name) in unique.enumerated() {
                    let cdTag = CDTag(context: context)
                    cdTag.id = UUID()
                    cdTag.name = name
                    cdTag.hexColor = tagColor(for: name)
                    cdTag.sortOrder = Int32(index)
                    cdTag.createdAt = Date()
                    cdTag.updatedAt = Date()
                }
            }

            try saveIfPossible()
        }
    }

    func convertToTag(_ cdTag: CDTag) -> Tag {
        Tag(
            id: cdTag.id,
            name: cdTag.name,
            hexColor: cdTag.hexColor,
            sortOrder: cdTag.sortOrder,
            createdAt: cdTag.createdAt,
            updatedAt: cdTag.updatedAt
        )
    }

    /// 同步密码条目的标签关系：根据名称查找或创建 CDTag，设置多对多关系
    /// 同时保持旧 tags 字符串字段（向后兼容）
    private func syncTagsRelationship(on cdEntry: CDPasswordEntry, from tagNames: [String]) throws {
        // 清除旧关系
        cdEntry.tagsRelationship = nil

        // 旧字段双写（向后兼容）
        let joined = tagNames.joined(separator: ",")
        cdEntry.tags = joined.isEmpty ? nil : joined

        // 建立新关系
        var tagSet: Set<CDTag> = []
        for name in tagNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let cdTag = try fetchTagByName(trimmed) ?? createTagEntity(name: trimmed)
            tagSet.insert(cdTag)
        }
        cdEntry.tagsRelationship = NSSet(set: tagSet)
    }
    
    private func syncTagsRelationship(on cdEntry: CDPincodeEntry, from tagNames: [String]) throws {
        cdEntry.tagsRelationship = nil
        
        let joined = tagNames.joined(separator: ",")
        cdEntry.tags = joined.isEmpty ? nil : joined
        
        var tagSet: Set<CDTag> = []
        for name in tagNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let cdTag = try fetchTagByName(trimmed) ?? createTagEntity(name: trimmed)
            tagSet.insert(cdTag)
        }
        cdEntry.tagsRelationship = NSSet(set: tagSet)
    }
    
    private func syncTagsRelationship(on cdEntry: CDBankcardEntry, from tagNames: [String]) throws {
        cdEntry.tagsRelationship = nil
        
        let joined = tagNames.joined(separator: ",")
        cdEntry.tags = joined.isEmpty ? nil : joined
        
        var tagSet: Set<CDTag> = []
        for name in tagNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let cdTag = try fetchTagByName(trimmed) ?? createTagEntity(name: trimmed)
            tagSet.insert(cdTag)
        }
        cdEntry.tagsRelationship = NSSet(set: tagSet)
    }

    private func createTagEntity(name: String) -> CDTag {
        let cdTag = CDTag(context: context)
        cdTag.id = UUID()
        cdTag.name = name
        cdTag.hexColor = tagColor(for: name)
        cdTag.sortOrder = Int32((try? fetchAllTags().count) ?? 0)
        cdTag.createdAt = Date()
        cdTag.updatedAt = Date()
        return cdTag
    }

    private func syncSafeNoteAssets(on cdNote: CDSafeNote, from assets: [SafeNoteAsset]) throws {
        if let existingAssets = cdNote.assets?.allObjects as? [CDSafeNoteAsset] {
            for existingAsset in existingAssets {
                context.delete(existingAsset)
            }
        }

        for asset in assets.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let cdAsset = CDSafeNoteAsset(context: context)
            cdAsset.id = asset.id
            cdAsset.sortOrder = Int32(asset.sortOrder)
            cdAsset.mimeType = asset.mimeType
            cdAsset.pixelWidth = Int32(asset.pixelWidth)
            cdAsset.pixelHeight = Int32(asset.pixelHeight)
            cdAsset.byteSize = asset.byteSize
            cdAsset.encryptedFilePath = asset.encryptedFilePath
            cdAsset.encryptedThumbnailPath = asset.encryptedThumbnailPath
            cdAsset.createdAt = asset.createdAt
            cdAsset.note = cdNote
        }
    }
    
    private func joinedNetworks(_ networks: [String]) -> String? {
        let cleaned = networks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = cleaned.joined(separator: ",")
        return joined.isEmpty ? nil : joined
    }
    
    private func splitNetworks(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    func convertToBankcardEntry(_ cdEntry: CDBankcardEntry) throws -> BankcardEntry {
        let cardNumber = try encryptionService.decryptToData(cdEntry.encryptedCardNumber)
        guard let cardNumberString = String(data: cardNumber, encoding: .utf8) else {
            throw CryptoError.invalidData
        }
        
        var cvv: String?
        if let encryptedCvv = cdEntry.encryptedCvv {
            let cvvData = try encryptionService.decryptToData(encryptedCvv)
            cvv = String(data: cvvData, encoding: .utf8)
        }
        
        var pin: String?
        if let encryptedPin = cdEntry.encryptedPin {
            let pinData = try encryptionService.decryptToData(encryptedPin)
            pin = String(data: pinData, encoding: .utf8)
        }
        
        var onlineBankingPassword: String?
        if let encryptedPassword = cdEntry.encryptedOnlineBankingPassword {
            let passwordData = try encryptionService.decryptToData(encryptedPassword)
            onlineBankingPassword = String(data: passwordData, encoding: .utf8)
        }
        
        var notes: String?
        if let encryptedNotes = cdEntry.encryptedNotes {
            let notesData = try encryptionService.decryptToData(encryptedNotes)
            notes = String(data: notesData, encoding: .utf8)
        }
        
        let tags: [String]
        if let cdTags = cdEntry.tagsRelationship?.allObjects as? [CDTag], !cdTags.isEmpty {
            tags = cdTags.map { $0.name }.sorted()
        } else if let tagsString = cdEntry.tags, !tagsString.isEmpty {
            tags = tagsString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else {
            tags = []
        }
        
        let customFields: [CustomField]
        if let encryptedCustom = cdEntry.encryptedCustomFields {
            customFields = try decryptCodable(encryptedCustom)
        } else {
            customFields = []
        }
        
        let cardType: CardType? = cdEntry.cardTypeRaw == 0 ? nil : CardType(rawValue: Int(cdEntry.cardTypeRaw) - 1)
        
        return BankcardEntry(
            id: cdEntry.id,
            bankName: cdEntry.bankName,
            cardNumber: cardNumberString,
            cvv: cvv,
            cardholder: cdEntry.cardholder,
            expiryDate: cdEntry.expiryDate,
            pin: pin,
            issuingChannel: cdEntry.issuingChannel,
            onlineBankingPassword: onlineBankingPassword,
            cardType: cardType,
            cardNetworks: splitNetworks(cdEntry.cardNetworks),
            notes: notes,
            categoryID: cdEntry.categoryID,
            tags: tags,
            isFavorite: cdEntry.isFavorite,
            customFields: customFields,
            version: cdEntry.version,
            isSynced: cdEntry.isSynced,
            createdAt: cdEntry.createdAt,
            updatedAt: cdEntry.updatedAt,
            lastUsedAt: cdEntry.lastUsedAt,
            expiresAt: cdEntry.expiresAt,
            deletedAt: cdEntry.deletedAt,
            icon: cdEntry.icon,
            dataSource: PasswordDataSource(rawValue: Int(cdEntry.dataSourceRaw)) ?? .manual
        )
    }
    
    func convertToPincodeEntry(_ cdEntry: CDPincodeEntry) throws -> PincodeEntry {
        let pincode = try encryptionService.decryptToData(cdEntry.encryptedPincode)
        guard let pincodeString = String(data: pincode, encoding: .utf8) else {
            throw CryptoError.invalidData
        }
        
        var notes: String?
        if let encryptedNotes = cdEntry.encryptedNotes {
            let notesData = try encryptionService.decryptToData(encryptedNotes)
            notes = String(data: notesData, encoding: .utf8)
        }
        
        let tags: [String]
        if let cdTags = cdEntry.tagsRelationship?.allObjects as? [CDTag], !cdTags.isEmpty {
            tags = cdTags.map { $0.name }.sorted()
        } else if let tagsString = cdEntry.tags, !tagsString.isEmpty {
            tags = tagsString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else {
            tags = []
        }
        
        let pincodeHistory: [PincodeHistoryEntry]
        if let encryptedHistory = cdEntry.encryptedPincodeHistory {
            pincodeHistory = try decryptCodable(encryptedHistory)
        } else {
            pincodeHistory = []
        }
        
        let customFields: [CustomField]
        if let encryptedCustom = cdEntry.encryptedCustomFields {
            customFields = try decryptCodable(encryptedCustom)
        } else {
            customFields = []
        }
        
        return PincodeEntry(
            id: cdEntry.id,
            title: cdEntry.title,
            pincode: pincodeString,
            isNumericOnly: cdEntry.isNumericOnly,
            pincodeHistory: pincodeHistory,
            notes: notes,
            categoryID: cdEntry.categoryID,
            tags: tags,
            isFavorite: cdEntry.isFavorite,
            customFields: customFields,
            version: cdEntry.version,
            isSynced: cdEntry.isSynced,
            createdAt: cdEntry.createdAt,
            updatedAt: cdEntry.updatedAt,
            lastUsedAt: cdEntry.lastUsedAt,
            expiresAt: cdEntry.expiresAt,
            deletedAt: cdEntry.deletedAt,
            icon: cdEntry.icon,
            dataSource: PasswordDataSource(rawValue: Int(cdEntry.dataSourceRaw)) ?? .manual
        )
    }

    func convertToSafeNoteSummary(_ cdNote: CDSafeNote) throws -> SafeNote {
        try makeSafeNote(from: cdNote, decryptContent: false)
    }

    func convertToSafeNote(_ cdNote: CDSafeNote) throws -> SafeNote {
        try makeSafeNote(from: cdNote, decryptContent: true)
    }

    func convertToPasswordEntry(_ cdEntry: CDPasswordEntry) throws -> PasswordEntry {
        let password = try encryptionService.decryptToData(cdEntry.encryptedPassword)
        guard let passwordString = String(data: password, encoding: .utf8) else {
            throw CryptoError.invalidData
        }
        
        var notes: String?
        if let encryptedNotes = cdEntry.encryptedNotes {
            let notesData = try encryptionService.decryptToData(encryptedNotes)
            notes = String(data: notesData, encoding: .utf8)
        }

        var oAuthProvider: OAuthProviderConfig?
        if let cdOAuth = cdEntry.oAuthProvider {
            var secret: String?
            if let encryptedSecret = cdOAuth.encryptedSecret {
                let secretData = try encryptionService.decryptToData(encryptedSecret)
                secret = String(data: secretData, encoding: .utf8)
            }

            oAuthProvider = OAuthProviderConfig(
                providerID: cdOAuth.id,
                secret: secret,
                provider: cdOAuth.provider,
                boundValue: cdOAuth.boundValue,
                isEnabled: cdOAuth.isEnabled,
                lastVerifiedAt: cdOAuth.lastVerifiedAt,
                expiresAt: cdOAuth.expiresAt,
                notes: cdOAuth.notes
            )
        }

        let twoFactorConfigs: [TwoFactorConfig]
        if let cdConfigs = cdEntry.twoFactorConfigs?.allObjects as? [CDTwoFactorConfig] {
            twoFactorConfigs = try cdConfigs.map { cdConfig in
                var secret: String?
                if let encryptedSecret = cdConfig.encryptedSecret {
                    let secretData = try encryptionService.decryptToData(encryptedSecret)
                    secret = String(data: secretData, encoding: .utf8)
                }
                
                return TwoFactorConfig(
                    id: cdConfig.id,
                    type: TwoFactorType(rawValue: cdConfig.type)!,
                    secret: secret,
                    algorithm: cdConfig.algorithm ?? "SHA1",
                    digits: cdConfig.digits > 0 ? Int(cdConfig.digits) : 6,
                    period: cdConfig.period > 0 ? Int(cdConfig.period) : 30,
                    issuer: cdConfig.issuer,
                    boundValue: cdConfig.boundValue,
                    isEnabled: cdConfig.isEnabled,
                    lastVerifiedAt: cdConfig.lastVerifiedAt,
                    expiresAt: cdConfig.expiresAt,
                    notes: cdConfig.notes
                )
            }
        } else {
            twoFactorConfigs = []
        }
        
        // 标签：优先从 tagsRelationship 关系读取，回退到旧 tags 字符串字段
        let tags: [String]
        if let cdTags = cdEntry.tagsRelationship?.allObjects as? [CDTag], !cdTags.isEmpty {
            tags = cdTags.map { $0.name }.sorted()
        } else if let tagsString = cdEntry.tags, !tagsString.isEmpty {
            tags = tagsString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else {
            tags = []
        }

        let passwordHistory: [PasswordHistoryEntry]
        if let encryptedHistory = cdEntry.encryptedPasswordHistory {
            passwordHistory = try decryptCodable(encryptedHistory)
        } else {
            passwordHistory = []
        }

        let customFields: [CustomField]
        if let encryptedCustom = cdEntry.encryptedCustomFields {
            customFields = try decryptCodable(encryptedCustom)
        } else {
            customFields = []
        }

        return PasswordEntry(
            id: cdEntry.id,
            siteName: cdEntry.siteName,
            siteURL: cdEntry.siteURL,
            username: cdEntry.username,
            password: passwordString,
            oAuthProvider: oAuthProvider,
            bundlePhoneNumber: cdEntry.bundlePhoneNumber,
            bundleEmailAddress: cdEntry.bundleEmailAddress,
            notes: notes,
            categoryID: cdEntry.categoryID,
            tags: tags,
            isFavorite: cdEntry.isFavorite,
            isPasswordResetEmail: cdEntry.isPasswordResetEmail,
            isPasswordResetPhone: cdEntry.isPasswordResetPhone,
            has2FA: cdEntry.has2FA,
            passwordStrength: PasswordStrength(rawValue: Int(cdEntry.passwordStrengthRaw)) ?? .medium,
            passwordHistory: passwordHistory,
            passwordChangedAt: cdEntry.passwordChangedAt,
            customFields: customFields,
            version: cdEntry.version,
            isSynced: cdEntry.isSynced,
            isDuplicatePassword: cdEntry.isDuplicatePassword,
            breachStatus: BreachStatus(rawValue: Int(cdEntry.breachStatusRaw)) ?? .unknown,
            accountStatus: AccountStatus(rawValue: Int(cdEntry.accountStatusRaw)) ?? .active,
            createdAt: cdEntry.createdAt,
            updatedAt: cdEntry.updatedAt,
            lastUsedAt: cdEntry.lastUsedAt,
            expiresAt: cdEntry.expiresAt,
            deletedAt: cdEntry.deletedAt,
            icon: cdEntry.icon,
            twoFactorConfigs: twoFactorConfigs,
            dataSource: PasswordDataSource(rawValue: Int(cdEntry.dataSourceRaw)) ?? .manual
        )
    }

    private func makeSafeNote(from cdNote: CDSafeNote, decryptContent: Bool) throws -> SafeNote {
        let titleData = try encryptionService.decryptToData(cdNote.encryptedTitle)
        guard let title = String(data: titleData, encoding: .utf8) else {
            throw CryptoError.invalidData
        }

        let content: String
        if decryptContent {
            let contentData = try encryptionService.decryptToData(cdNote.encryptedContent)
            guard let contentString = String(data: contentData, encoding: .utf8) else {
                throw CryptoError.invalidData
            }
            content = contentString
        } else {
            content = ""
        }

        let assets = ((cdNote.assets?.allObjects as? [CDSafeNoteAsset]) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                SafeNoteAsset(
                    id: $0.id,
                    noteID: cdNote.id,
                    sortOrder: Int($0.sortOrder),
                    mimeType: $0.mimeType,
                    pixelWidth: Int($0.pixelWidth),
                    pixelHeight: Int($0.pixelHeight),
                    byteSize: $0.byteSize,
                    encryptedFilePath: $0.encryptedFilePath,
                    encryptedThumbnailPath: $0.encryptedThumbnailPath,
                    createdAt: $0.createdAt
                )
            }

        return SafeNote(
            id: cdNote.id,
            title: title,
            content: content,
            assets: assets,
            coverAssetID: cdNote.coverAssetID,
            isFavorite: cdNote.isFavorite,
            createdAt: cdNote.createdAt,
            updatedAt: cdNote.updatedAt,
            lastViewedAt: cdNote.lastViewedAt,
            deletedAt: cdNote.deletedAt,
            version: cdNote.version,
            isSynced: cdNote.isSynced,
            dataSource: PasswordDataSource(rawValue: Int(cdNote.dataSourceRaw)) ?? .manual
        )
    }
}
