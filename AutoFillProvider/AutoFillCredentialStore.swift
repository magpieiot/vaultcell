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
        container.persistentStoreDescriptions = [description]

        let loadStart = Date()
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        NSLog("AutoFill: 共享数据库打开完成（%.2fs）", Date().timeIntervalSince(loadStart))

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
