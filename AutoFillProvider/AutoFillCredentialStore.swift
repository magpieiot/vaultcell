/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AutoFillCredentialStore.swift
/// ------------------------------------------------------------------
///
/// AutoFill 扩展的凭据读取层：
///
/// 1. 从共享 Keychain 读取带生物识别保护（userPresence）的数据加密密钥
///    （DEK，account 为 `vaultcell.biometricDek`）。Keychain 访问组与主 App
///    一致（默认取 entitlement 中唯一的 keychain-access-group），系统会在
///    读取时自动弹出 Face ID / Touch ID 认证；
/// 2. 直接打开主 App 存放在 App Group 容器中的 Core Data 数据库
///    （VaultCell.sqlite），因此不需要任何数据同步/镜像机制，主 App 内
///    保存的密码立即可见；
/// 3. 使用 DEK 对 `encryptedPassword`（AES-GCM：nonce+tag+ciphertext）
///    解密，组装为 AutoFill 展示用的 `CredentialItem`。
///
/// 主 App 的 KeychainService / CoreDataStack 使用相同的 service 名、
/// 账户名与 App Group，保证两端访问同一份数据。

import CoreData
import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// AutoFill 扩展读取共享密码库时的错误类型
enum AutoFillCredentialStoreError: Error, LocalizedError {
    /// 尚未创建密码库（Keychain 无 DEK 或数据库中无数据文件）
    case vaultNotConfigured
    /// 密码库已锁定，需要先调用 unlock()
    case vaultLocked
    /// 生物识别认证失败或不可用（关联系统 OSStatus）
    case authenticationFailed(OSStatus)
    /// 无法打开共享数据库（App Group 不可用或数据库损坏）
    case databaseUnavailable
    /// 密文数据格式非法
    case invalidData

    var errorDescription: String? {
        switch self {
        case .vaultNotConfigured:
            return String(localized: "Vault is not set up yet. Open VaultCell to create a vault and save passwords first")
        case .vaultLocked:
            return String(localized: "Vault is locked")
        case .authenticationFailed:
            return String(localized: "Authentication failed")
        case .databaseUnavailable:
            return String(localized: "Vault data is unavailable")
        case .invalidData:
            return String(localized: "Password data is malformed")
        }
    }
}

/// 自动填充列表展示用的条目元数据。
/// 刻意不含密码：密码在用户选中某条时按 ID 单条解密，避免列表加载时解密整库。
struct CredentialSummary: Identifiable, Hashable {
    let id: UUID
    let siteName: String
    let siteURL: String
    let username: String
}

/// 系统保存密码请求映射出的待写入凭据。
/// 字段刻意与 `CDPasswordEntry` 的必填项对齐：Core Data 里
/// `siteName / username / encryptedPassword / categoryID / createdAt / updatedAt`
/// 均非 optional 且无默认值，写入前必须全部赋值。
struct CredentialSaveDraft {
    let siteName: String
    let siteURL: String?
    let username: String
    let password: String
}

/// 保存结果：区分新建与覆盖更新，供界面给出准确提示
enum CredentialSaveOutcome {
    case created(UUID)
    case updated(UUID)

    /// 涉及条目的 ID（新建为新建条目，更新为被覆盖的条目）
    var entryID: UUID {
        switch self {
        case .created(let id), .updated(let id): return id
        }
    }
}

/// AutoFill 扩展的凭据读取器（单例）
final class AutoFillCredentialStore {
    static let shared = AutoFillCredentialStore()

    /// 与主 App KeychainService 的 service 保持一致
    private let keychainServiceName = "com.magpie.vaultcell"
    /// 与主 App VaultKey.biometricDek 保持一致（存有 userPresence 保护的 DEK）
    private let keychainDEKAccount = "vaultcell.biometricDek"
    /// 与主 App CoreDataStack 的模型名保持一致
    private let coreDataModelName = "VaultCell"
    /// 与主 App CoreDataStack 的数据库文件名保持一致
    private let databaseFileName = "VaultCell.sqlite"

    private let lock = NSLock()
    private var _dek: SymmetricKey?
    private var _container: NSPersistentContainer?

    private init() {}

    /// 当前构建变体对应的 App Group
    private var appGroupIdentifier: String {
        #if CN
        return "group.com.magpie.vaultcell.cn.shared"
        #else
        return "group.com.magpie.vaultcell.shared"
        #endif
    }

    /// 是否已解锁（DEK 已在内存中）
    var isUnlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _dek != nil
    }

    // MARK: - 解锁

    /// 通过系统生物识别解锁密码库。
    /// 底层读取带 userPresence 访问控制的 Keychain 条目，系统会自动弹出
    /// Face ID / Touch ID 认证界面；该方法应在后台线程调用，避免阻塞 UI。
    func unlock() throws {
        if isUnlocked { return }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(dekQuery(authenticationContext: nil) as CFDictionary, &result)
        try handleUnlockResult(status: status, result: result)
    }

    /// 免交互路径专用解锁：**绝不弹出任何认证界面**。
    ///
    /// 为什么不能用 `unlock()`：免交互入口（`provideCredentialWithoutUserInteraction`）运行在
    /// 扩展 UI 还没上屏的上下文里，此时读 userPresence 条目会让系统弹出的 Face ID 被立即取消。
    /// 这一次"失败的认证"会占用尝试次数并让随后的交互路径第一次也失败，最终表现为
    /// "每次都报错、必须点一次重试才能填"。带 `interactionNotAllowed` 的上下文只会复用
    /// 近期已有的认证结果，取不到就立刻报错，由调用方干净地回落到交互流程。
    func unlockWithoutUserInteraction() throws {
        if isUnlocked { return }

        let context = LAContext()
        context.interactionNotAllowed = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(dekQuery(authenticationContext: context) as CFDictionary, &result)
        try handleUnlockResult(status: status, result: result)
    }

    /// 读取 DEK 的 Keychain 查询；传入已认证的 `LAContext` 可复用该次认证、避免二次弹窗。
    private func dekQuery(authenticationContext: LAContext?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainDEKAccount,
            kSecReturnData as String: kCFBooleanTrue ?? "",
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let authenticationContext {
            query[kSecUseAuthenticationContext as String] = authenticationContext
        }
        return query
    }

    private func handleUnlockResult(status: OSStatus, result: CFTypeRef?) throws {
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, !data.isEmpty else {
                throw AutoFillCredentialStoreError.invalidData
            }
            lock.lock()
            _dek = SymmetricKey(data: data)
            lock.unlock()
        case errSecItemNotFound:
            // 主 App 从未创建过密码库（DEK 不存在）
            throw AutoFillCredentialStoreError.vaultNotConfigured
        default:
            // 含 errSecUserCanceled(-128)、errSecAuthFailed(-25293)、errSecInteractionNotAllowed(-25308)
            // 打出 OSStatus 便于区分"系统取消"与"用户取消"
            NSLog("AutoFill: Keychain 解锁失败 status=%d", status)
            throw AutoFillCredentialStoreError.authenticationFailed(status)
        }
    }

    /// 清除内存中的 DEK（扩展结束/中断时可调用）
    func lockVault() {
        lock.lock()
        _dek = nil
        lock.unlock()
    }

    // MARK: - 预热

    /// 在后台线程提前打开共享数据库（幂等，失败静默）。
    ///
    /// 首次填充的耗时大头之一是扩展进程内第一次打开共享 SQLite
    /// （模型加载 + 迁移兼容性检查 + WAL 恢复）。放在入口立刻触发，
    /// 与"系统呈现扩展面板 + 生物识别认证"并行执行，
    /// 让解锁成功后的单条读取直接命中已就绪的容器。
    func warmUpDatabase() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = try? self?.persistentContainer()
        }
    }

    // MARK: - 凭据读取

    /// 读取列表所需的元数据：**不解密任何密文**，也不读取 `encryptedPassword` 大字段。
    /// 在私有队列上下文执行，不占用主线程；需先成功调用 unlock()。
    func fetchCredentialSummaries() throws -> [CredentialSummary] {
        guard currentDek() != nil else {
            throw AutoFillCredentialStoreError.vaultLocked
        }

        let rows: [[String: Any]] = try perform { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "CDPasswordEntry")
            request.resultType = .dictionaryResultType
            // 与主 App 列表一致：回收站中的条目不出现在自动填充里
            request.predicate = NSPredicate(format: "deletedAt == nil")
            // 只取展示字段，避免把整库密文读进内存再逐条解密（大库下即秒级卡顿的来源）
            request.propertiesToFetch = ["id", "siteName", "siteURL", "username"]
            return try context.fetch(request).compactMap { $0 as? [String: Any] }
        }

        let summaries: [CredentialSummary] = rows.compactMap { row in
            // 字典结果里 UUID 属性可能桥接为 NSUUID，两种都接受，避免列表整体变空
            let id = (row["id"] as? UUID) ?? (row["id"] as? NSUUID).map { $0 as UUID }
            guard let id,
                  let siteName = row["siteName"] as? String,
                  let username = row["username"] as? String else {
                return nil
            }
            return CredentialSummary(
                id: id,
                siteName: siteName,
                siteURL: row["siteURL"] as? String ?? "",
                username: username
            )
        }

        return summaries.sorted {
            $0.siteName.localizedCaseInsensitiveCompare($1.siteName) == .orderedAscending
        }
    }

    /// 按条目 ID 取「用户名 + 解密后的密码」：单行查询，只解密这一条。
    /// 所有填充路径都走这里，因此代价与库大小无关。
    func credential(for id: UUID) throws -> (username: String, password: String)? {
        guard let dek = currentDek() else {
            throw AutoFillCredentialStoreError.vaultLocked
        }

        return try perform { context in
            let request = NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entry = try context.fetch(request).first,
                  let password = Self.decryptPassword(entry.encryptedPassword, using: dek) else {
                // 条目已被删除或密文损坏
                return nil
            }
            return (username: entry.username, password: password)
        }
    }

    // MARK: - 凭据保存

    /// 查找与待保存凭据「同站点 + 同用户名」的已有条目。
    ///
    /// 只读取明文元数据（不解密），因此**不需要解锁**：界面可以在弹 Face ID
    /// 之前就告诉用户这次是"新建"还是"覆盖更新"。
    /// - Returns: 命中条目的 ID；无匹配时 nil
    func existingEntryID(for draft: CredentialSaveDraft) throws -> UUID? {
        let service = draft.siteURL ?? ""
        return try perform { context in
            let request = NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
            // 与列表一致：回收站中的条目不参与匹配
            request.predicate = NSPredicate(format: "deletedAt == nil && username ==[c] %@", draft.username)
            let candidates = try context.fetch(request)
            return candidates.first {
                AutoFillDomainMatcher.matches(service: service, siteURL: $0.siteURL ?? "")
            }?.id
        }
    }

    /// 写入一条凭据：已存在同站点 + 同用户名的条目时更新其密码，否则新建。
    ///
    /// 需要已解锁（密码要用 DEK 加密后落库）。写入发生在扩展进程里，直接打开
    /// 与主 App 同一份 SQLite，因此主 App 下次读库即可看到新条目，无需同步机制。
    /// - Returns: 新建 / 更新后的条目 ID
    func saveCredential(_ draft: CredentialSaveDraft) throws -> CredentialSaveOutcome {
        guard let dek = currentDek() else {
            throw AutoFillCredentialStoreError.vaultLocked
        }
        guard let encryptedPassword = Self.encryptPassword(draft.password, using: dek) else {
            throw AutoFillCredentialStoreError.invalidData
        }

        let service = draft.siteURL ?? ""

        // 主 App 可能正持有同一个 SQLite 文件的连接（列表加载、身份同步），
        // 扩展撞上去会被 SQLite 拒绝（SQLITE_BUSY / database is locked）。
        // 这类失败是瞬时的，整轮重建对象图重试即可；非瞬时错误立刻抛出。
        var lastError: Error?
        for attempt in 0..<Self.saveAttempts {
            do {
                let outcome: CredentialSaveOutcome = try perform { context in
                    let request = NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
                    request.predicate = NSPredicate(format: "deletedAt == nil && username ==[c] %@", draft.username)
                    let candidates = try context.fetch(request)

                    if let existing = candidates.first(where: {
                        AutoFillDomainMatcher.matches(service: service, siteURL: $0.siteURL ?? "")
                    }) {
                        existing.username = draft.username
                        existing.encryptedPassword = encryptedPassword
                        if draft.siteURL?.isEmpty == false { existing.siteURL = draft.siteURL }
                        existing.updatedAt = Date()
                        existing.passwordChangedAt = Date()
                        try context.save()
                        return CredentialSaveOutcome.updated(existing.id)
                    }

                    let entry = CDPasswordEntry(context: context)
                    entry.id = UUID()
                    entry.siteName = draft.siteName
                    entry.siteURL = draft.siteURL
                    entry.username = draft.username
                    entry.encryptedPassword = encryptedPassword
                    // 与主 App 默认分类（Primary）保持一致，否则条目在主 App 里会落到空分类
                    entry.categoryID = AutoFillCredentialIdentityFactory.defaultCategoryID
                    let now = Date()
                    entry.createdAt = now
                    entry.updatedAt = now
                    entry.passwordChangedAt = now
                    Self.applyRequiredDefaults(to: entry)
                    try context.save()
                    return CredentialSaveOutcome.created(entry.id)
                }

                markSavedForHostApp()
                verifySaved(entryID: outcome.entryID)
                return outcome
            } catch {
                lastError = error
                guard Self.isTransient(error), attempt < Self.saveAttempts - 1 else { throw error }
                NSLog("AutoFill: 保存被占用，退避后重试（第 %d 次）：%@", attempt + 1, String(describing: error))
                Thread.sleep(forTimeInterval: 0.15 * Double(attempt + 1))
            }
        }
        throw lastError ?? AutoFillCredentialStoreError.databaseUnavailable
    }

    /// 补齐模型中「非 optional」标量字段的默认值。
    ///
    /// 这些属性在 .xcdatamodel 里虽然写了 defaultValue，但扩展进程新建对象时
    /// 默认值并不会落到对象上，保存即失败（NSValidationErrorKey=accountStatusRaw 等）。
    /// 这里与主 App `CoreDataDataSource.createPasswordEntry` 保持同一套取值：
    /// - breachStatus = .unknown(0)、accountStatus = .active(0)
    /// - passwordStrength = .medium(2)、passwordlessLoginType = .none(0)
    /// - dataSource = .manual(0)、version = 1、isSynced = true
    private static func applyRequiredDefaults(to entry: CDPasswordEntry) {
        entry.breachStatusRaw = 0
        entry.accountStatusRaw = 0
        entry.passwordStrengthRaw = 2
        entry.passwordlessLoginTypeRaw = 0
        entry.version = 1
        entry.isFavorite = false
        entry.isSynced = true
        entry.has2FA = false
        entry.hasBundleEmail = false
        entry.hasBundlePhone = false
        entry.isPasswordResetEmail = false
        entry.isPasswordResetPhone = false
        entry.isDuplicatePassword = false
        entry.dataSourceRaw = 0
    }

    /// 写入尝试次数（首次 + 两次退避重试）
    private static let saveAttempts = 3

    /// 是否瞬时错误：SQLite 被其它进程/连接占用时可重试，其余（模型不匹配、
    /// 校验失败等）重试多少次都一样，直接交给调用方。
    private static func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        // SQLITE_BUSY(5) / SQLITE_LOCKED(6)；Core Data 会把它包成 NSPersistentStoreSaveError
        if nsError.domain == NSSQLiteErrorDomain { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSSQLiteErrorDomain {
            return true
        }
        let description = nsError.localizedDescription.lowercased()
        return description.contains("busy") || description.contains("locked")
    }

    /// 写入后立即回读校验（诊断用）。
    ///
    /// 排查"扩展说保存成功、主 App 却查不到"时，这一步能把问题二分到
    /// 「根本没写进共享库」还是「写了但主 App 没刷新」。
    private func verifySaved(entryID: UUID) {
        let found = try? perform { context -> Bool in
            let request = NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
            request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
            request.fetchLimit = 1
            return (try context.fetch(request).first) != nil
        }
        NSLog("AutoFill: 写入回读校验%@（id=%@）", found == true ? "通过" : "失败", entryID.uuidString)
    }

    /// 通知主 App 密码库已被扩展写入。
    ///
    /// 扩展是独立进程，主 App 的列表不会自动感知新增条目。这里在 App Group
    /// 里留下一个时间戳，主 App 回到前台时比对并触发列表刷新（见
    /// AppState.handleAppBecameActive）。用时间戳而非布尔值，避免"扩展写了但
    /// 主 App 恰好没读到"时被下一次读取覆盖掉。
    private func markSavedForHostApp() {
        UserDefaults(suiteName: appGroupIdentifier)?.set(
            Date().timeIntervalSince1970,
            forKey: AutoFillSharedKeys.savedCredentialAt
        )
    }

    // MARK: - Private

    /// 取当前内存中的 DEK（未解锁时为 nil）
    private func currentDek() -> SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        return _dek
    }

    /// 在私有队列上下文执行读取。
    /// 扩展进程内没有主线程 UI 需求，用 backgroundContext 同步执行可避免
    /// 之前把整库读取压在主线程（viewContext）上造成的界面卡顿。
    private func perform<T>(_ body: (NSManagedObjectContext) throws -> T) throws -> T {
        let container = try persistentContainer()
        let context = container.newBackgroundContext()

        var outcome: Result<T, Error>?
        context.performAndWait {
            outcome = Result { try body(context) }
        }

        guard let outcome else {
            throw AutoFillCredentialStoreError.databaseUnavailable
        }
        return try outcome.get()
    }

    /// 打开主 App 在 App Group 容器中的 Core Data 数据库。
    ///
    /// 加载全程持锁：`loadPersistentStores` 在 `shouldAddStoreAsynchronously`
    /// 为默认 false 时同步完成，持锁期间其它调用方最多等待、不会重复加载；
    /// 这也是 `warmUpDatabase()` 能与正式读取并发调用的前提。
    private func persistentContainer() throws -> NSPersistentContainer {
        lock.lock()
        defer { lock.unlock() }
        if let container = _container {
            return container
        }

        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw AutoFillCredentialStoreError.databaseUnavailable
        }
        let storeURL = groupURL.appendingPathComponent(databaseFileName)

        // 与主 App CoreDataStack 相同的迁移配置，保证任意历史版本可读
        let container = NSPersistentContainer(name: coreDataModelName)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        // 与主 App 对齐：让对方（主 App 连接）能感知本进程的写入
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        // 主 App 可能同时持有该文件的连接，写入撞上会立刻 SQLITE_BUSY；
        // 给 SQLite 一个等待窗口，而不是马上失败。
        // 必须用 setOption：setValue(_:forKey:) 会抛 NSUnknownKeyException 闪退
        description.setOption(["busy_timeout": "5000"] as NSDictionary,
                              forKey: NSSQLitePragmasOption)
        container.persistentStoreDescriptions = [description]

        let loadStart = Date()
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        NSLog("AutoFill: 共享数据库打开完成（%.2fs）路径=%@", Date().timeIntervalSince(loadStart), storeURL.path)

        if let loadError {
            // 主 App 从未启动过（数据库文件不存在）时给出更友好的提示
            if !FileManager.default.fileExists(atPath: storeURL.path) {
                throw AutoFillCredentialStoreError.vaultNotConfigured
            }
            NSLog("AutoFill: Core Data load failed: %@", loadError.localizedDescription)
            throw AutoFillCredentialStoreError.databaseUnavailable
        }

        _container = container
        return container
    }

    /// 加密密码（格式与主 App `EncryptedData.combined` 一致：nonce+tag+ciphertext）。
    /// 注意顺序：CryptoKit 的 `SealedBox.combined` 是 nonce+ciphertext+tag，与本项目
    /// 的存储格式不同，因此这里手动拼装，保证主 App 的 `EncryptionService` 能解回来。
    private static func encryptPassword(_ password: String, using dek: SymmetricKey) -> Data? {
        guard let plaintext = password.data(using: .utf8),
              let sealedBox = try? AES.GCM.seal(plaintext, using: dek) else {
            return nil
        }
        var data = Data()
        data.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        data.append(sealedBox.tag)
        data.append(sealedBox.ciphertext)
        return data
    }

    /// 解密 AES-GCM 密文（格式与主 App EncryptionService 一致：nonce+tag+ciphertext）
    private static func decryptPassword(_ encryptedData: Data, using dek: SymmetricKey) -> String? {
        // nonce(12) + tag(16) + ciphertext(>=0)，明文为空时总长 28 字节
        guard encryptedData.count >= 28 else { return nil }
        let start = encryptedData.startIndex
        let nonceData = encryptedData.subdata(in: start..<(start + 12))
        let tagData = encryptedData.subdata(in: (start + 12)..<(start + 28))
        let ciphertext = encryptedData.subdata(in: (start + 28)..<encryptedData.endIndex)

        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tagData
            )
            let plaintext = try AES.GCM.open(sealedBox, using: dek)
            return String(data: plaintext, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
