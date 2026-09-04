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
            return "尚未设置密码库，请先打开 VaultCell 创建密码库并保存密码"
        case .vaultLocked:
            return "密码库已锁定"
        case .authenticationFailed:
            return "身份验证失败"
        case .databaseUnavailable:
            return "无法访问密码库数据"
        case .invalidData:
            return "密码数据格式错误"
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

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainDEKAccount,
            kSecReturnData as String: kCFBooleanTrue,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

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
            // 含 errSecUserCanceled（用户取消认证）、errSecInteractionNotAllowed 等
            throw AutoFillCredentialStoreError.authenticationFailed(status)
        }
    }

    /// 清除内存中的 DEK（扩展结束/中断时可调用）
    func lockVault() {
        lock.lock()
        _dek = nil
        lock.unlock()
    }

    // MARK: - 凭据读取

    /// 读取全部未被软删除的密码条目（解密后的明文仅存在于内存）。
    /// 需先成功调用 unlock()；Core Data 的 viewContext 绑定主线程，
    /// 因此本方法应在主线程调用。
    func fetchCredentials() throws -> [CredentialItem] {
        lock.lock()
        let dek = _dek
        lock.unlock()
        guard let dek else {
            throw AutoFillCredentialStoreError.vaultLocked
        }

        let container = try persistentContainer()
        let context = container.viewContext

        let request = NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
        request.returnsObjectsAsFaults = false

        let cdEntries = try context.fetch(request)

        var items: [CredentialItem] = []
        items.reserveCapacity(cdEntries.count)

        for cdEntry in cdEntries {
            // 过滤回收站中的软删除条目（与主 App 列表一致）
            guard cdEntry.deletedAt == nil else { continue }
            guard let password = Self.decryptPassword(cdEntry.encryptedPassword, using: dek) else {
                // 单条解密失败不阻断整体列表（可能为损坏数据）
                continue
            }
            items.append(CredentialItem(
                id: cdEntry.id,
                siteName: cdEntry.siteName,
                siteURL: cdEntry.siteURL ?? "",
                username: cdEntry.username,
                password: password
            ))
        }

        return items.sorted {
            $0.siteName.localizedCaseInsensitiveCompare($1.siteName) == .orderedAscending
        }
    }

    // MARK: - 匹配辅助

    /// 判断系统传入的 serviceIdentifier（域名或 URL）与条目站点 URL 是否匹配
    static func matches(service: String, siteURL: String) -> Bool {
        let serviceTrimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteTrimmed = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serviceTrimmed.isEmpty, !siteTrimmed.isEmpty else {
            return false
        }

        let serviceHost = Self.hostname(from: serviceTrimmed)
        let siteHost = Self.hostname(from: siteTrimmed)

        if let serviceHost, let siteHost {
            return serviceHost == siteHost
                || serviceHost.hasSuffix("." + siteHost)
                || siteHost.hasSuffix("." + serviceHost)
        }

        // 无法解析 host 时退化为子串包含匹配
        return siteTrimmed.localizedCaseInsensitiveContains(serviceTrimmed)
            || serviceTrimmed.localizedCaseInsensitiveContains(siteTrimmed)
    }

    /// 从任意 URL/域名文本中提取 hostname（小写、去 www）
    private static func hostname(from text: String) -> String? {
        let candidate: String
        if text.contains("://"), let url = URL(string: text), let host = url.host {
            candidate = host
        } else {
            // 去掉 scheme 与路径后取第一段
            let withoutScheme = text.replacingOccurrences(of: ".*://", with: "", options: .regularExpression)
            candidate = withoutScheme.split(separator: "/").first.map(String.init) ?? withoutScheme
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        // 剥离常见前缀
        let prefixes = ["www.", "m."]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return trimmed
    }

    // MARK: - Private

    /// 打开主 App 在 App Group 容器中的 Core Data 数据库
    private func persistentContainer() throws -> NSPersistentContainer {
        lock.lock()
        if let container = _container {
            lock.unlock()
            return container
        }
        lock.unlock()

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

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            // 主 App 从未启动过（数据库文件不存在）时给出更友好的提示
            if !FileManager.default.fileExists(atPath: storeURL.path) {
                throw AutoFillCredentialStoreError.vaultNotConfigured
            }
            print("AutoFill: Core Data load failed: \(loadError.localizedDescription)")
            throw AutoFillCredentialStoreError.databaseUnavailable
        }

        lock.lock()
        _container = container
        lock.unlock()
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
