/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CredentialExchangeService.swift
/// created on: 2026/08/28
/// ------------------------------------------------------------------
///
/// 凭据交换（Credential Exchange，WWDC25 Session 279，iOS 26+）。
///
/// 兼容性设计（部署目标保持 iOS 17）：
/// 本文件整体标记 `@available(iOS 26, *)`，因为公开 API 的签名中直接使用了
/// iOS 26 才存在的类型（ASExportedCredentialData / ASImportableAccount 等）。
/// 调用方（VaultCellApp）必须在 `if #available(iOS 26, *)` 守卫内使用本服务，
/// 因此在 iOS 17 部署目标下，虽然文件被编译，但调用点不会触及 iOS 26 符号；
/// 运行时系统低于 iOS 26 时也不会路由 ASCredentialExchangeActivity。
///
/// 注册要点（由扩展而非主 App 完成）：
/// - 扩展 entitlements 含 com.apple.developer.authentication-services.autofill-credential-provider
/// - 扩展 Info.plist 的 NSExtensionAttributes 含 ASCredentialProviderExtensionCapabilities
///   （SupportsAutoFill=true, SupportsCredentialExchange=true, SupportedCredentialExchangeVersions=["1.0"]）
/// - 主 App Info.plist 声明 NSUserActivityTypes 含 ASCredentialExchangeActivity
///
/// 数据映射：
/// ASImportableAccount（账户，含 userName/email/items）
///   └─ ASImportableItem（条目，含 title/subtitle/scope/credentials）
///        └─ ASImportableCredential.basicAuthentication（账号密码，userName/password 均为
///           ASImportableEditableField，实际值在其 value 字符串上）
///
/// ⚠️ 联调必须在 iOS 26 真机/模拟器上进行；iOS 17 环境无法验证功能本身。
/// ------------------------------------------------------------------

import AuthenticationServices
import Foundation

/// Credential Exchange 导入完成通知。
/// 定义为无可用性限制的全局扩展，便于 iOS 17 部署目标下的调用点引用。
extension Notification.Name {
    static let credentialExchangeDidImport = Notification.Name("credentialExchangeDidImport")
}

@available(iOS 26, *)
enum CredentialExchangeService {

    /// 系统用于路由凭据交换导入的 UserActivity 类型字符串。
    /// 等价于 AuthenticationServices 的 `ASCredentialExchangeActivity` 常量。
    static let activityType: String = "ASCredentialExchangeActivity"

    // MARK: - 导入（作为目标 App 接收别人导出的凭据）

    /// 从系统拉起的 NSUserActivity 中提取导入 token。
    /// - Parameter activity: 系统以 ASCredentialExchangeActivity 路由的 activity
    /// - Returns: 导入令牌，用于向系统换取导出的凭据数据
    static func importToken(from activity: NSUserActivity) throws -> UUID {
        guard let userInfo = activity.userInfo,
              let token = userInfo[ASCredentialImportToken] as? UUID else {
            throw CredentialExchangeError.missingImportToken
        }
        return token
    }

    /// 用 token 向系统换取导出的凭据数据。
    static func importCredentials(token: UUID) async throws -> ASExportedCredentialData {
        let manager = ASCredentialImportManager()
        return try await manager.importCredentials(token: token)
    }

    /// 将导入得到的凭据数据写入本地密码库。
    ///
    /// 映射规则：
    /// - 账号密码取 `ASImportableCredential.basicAuthentication` 的 userName / password；
    /// - 站点名取 `ASImportableItem.title`，站点 URL 取 `scope.urls.first`；
    /// - 邮箱取 `ASImportableAccount.email`（为空时回退到 userName 若为邮箱格式）；
    /// - 已存在（siteURL + username 相同）则更新密码，否则新建。
    ///
    /// - Parameter data: 系统返回的 ASExportedCredentialData
    /// - Returns: （新建条数，更新条数）
    @discardableResult
    static func ingest(_ data: ASExportedCredentialData) async throws -> (created: Int, updated: Int) {
        let repository = PasswordRepository()
        var created = 0
        var updated = 0

        for account in data.accounts {
            for item in account.items {
                // 仅处理账号密码类凭据（basicAuthentication）；
                // 其他类型（passkey / TOTP / 信用卡等）当前版本不落库。
                guard let basicAuth = basicAuthentication(from: item.credentials) else { continue }

                let username = (basicAuth.userName?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let password = basicAuth.password?.value ?? ""
                // 站点名与密码为空则跳过，避免写入无意义记录
                guard !username.isEmpty, !password.isEmpty else { continue }

                let siteURL = item.scope?.urls.first?.absoluteString
                let siteName = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? (account.userName.isEmpty ? "Imported" : account.userName)
                    : item.title.trimmingCharacters(in: .whitespacesAndNewlines)

                if var existing = try await findExisting(repository: repository,
                                                        siteURL: siteURL,
                                                        username: username) {
                    // 已存在同名同站账号：更新密码与来源标记
                    existing.password = password
                    existing.updatedAt = Date()
                    existing.passwordChangedAt = Date()
                    existing.dataSource = .credentialExchange
                    if let notes = item.subtitle, !notes.isEmpty {
                        existing.notes = notes
                    }
                    try await repository.update(existing)
                    updated += 1
                } else {
                    var entry = PasswordEntry(
                        siteName: siteName,
                        siteURL: siteURL,
                        username: username,
                        password: password,
                        bundleEmailAddress: account.email.isEmpty ? nil : account.email,
                        notes: (item.subtitle?.isEmpty ?? true) ? nil : item.subtitle,
                        categoryID: PasswordCategory.systemDefaults[0].id,
                        isFavorite: item.favorite,
                        dataSource: .credentialExchange
                    )
                    if !item.tags.isEmpty { entry.tags = item.tags }
                    try await repository.save(entry)
                    created += 1
                }
            }
        }

        return (created, updated)
    }

    // MARK: - 导出（作为源 App 把凭据导出给别人的 App）

    /// 拉起系统级导出 UI，让用户选择目标 App，并导出给定凭据。
    /// - Parameters:
    ///   - entries: 待导出的 VaultCell 密码条目
    ///   - anchor: 用于呈现系统导出 UI 的窗口锚点
    static func requestExport(entries: [PasswordEntry],
                              anchor: ASPresentationAnchor) async throws {
        guard !entries.isEmpty else { throw CredentialExchangeError.nothingToExport }

        let manager = ASCredentialExportManager(presentationAnchor: anchor)
        // 拉起系统 UI，由用户选择目标 App；返回对方支持的格式版本
        let options = try await manager.requestExport(for: nil)

        let account = makeAccount(from: entries)
        let payload = ASExportedCredentialData(
            accounts: [account],
            formatVersion: options.formatVersion,
            exporterRelyingPartyIdentifier: Bundle.main.bundleIdentifier ?? "",
            exporterDisplayName: Bundle.main.displayName,
            timestamp: Date()
        )
        try await manager.exportCredentials(payload)
    }

    // MARK: - 映射辅助

    /// 从一条 item 的凭据数组中取出账号密码（basicAuthentication）。
    private static func basicAuthentication(
        from credentials: [ASImportableCredential]
    ) -> ASImportableCredential.BasicAuthentication? {
        for credential in credentials {
            if case .basicAuthentication(let basicAuth) = credential {
                return basicAuth
            }
        }
        return nil
    }

    /// 按站点 URL + 用户名查找是否已存在条目（避免重复导入）。
    private static func findExisting(repository: PasswordRepositoryProtocol,
                                     siteURL: String?,
                                     username: String) async throws -> PasswordEntry? {
        let all = try await repository.fetchAll()
        return all.first { entry in
            entry.username == username && entry.siteURL == siteURL
        }
    }

    /// 把 VaultCell 密码条目打包成一个可导出的账户（CXF 结构）。
    ///
    /// 每个 PasswordEntry 映射为一个 ASImportableItem；账户层面使用一个 UUID 作为 id，
    /// userName/email 取第一条条目的用户名。
    private static func makeAccount(from entries: [PasswordEntry]) -> ASImportableAccount {
        var accountID = UUID()
        let accountIDData = withUnsafeBytes(of: &accountID) { Data($0) }

        let items = entries.map { entry -> ASImportableItem in
            var itemID = entry.id
            let itemIDData = withUnsafeBytes(of: &itemID) { Data($0) }

            let basicAuth = ASImportableCredential.BasicAuthentication(
                userName: ASImportableEditableField(
                    id: nil,
                    fieldType: .string,
                    value: entry.username,
                    label: "Username"
                ),
                password: ASImportableEditableField(
                    id: nil,
                    fieldType: .concealedString,
                    value: entry.password,
                    label: "Password"
                )
            )

            var urls: [URL] = []
            if let siteURL = entry.siteURL, let url = URL(string: siteURL) {
                urls = [url]
            }
            let scope = urls.isEmpty ? nil : ASImportableCredentialScope(urls: urls)

            // 使用 iOS 26.0 起可用的基础构造器（created/lastModified 为非可选 Date）
            return ASImportableItem(
                id: itemIDData,
                created: entry.createdAt ?? Date(),
                lastModified: entry.updatedAt ?? Date(),
                title: entry.siteName,
                subtitle: entry.notes,
                favorite: entry.isFavorite,
                scope: scope,
                credentials: [.basicAuthentication(basicAuth)],
                tags: entry.tags ?? []
            )
        }

        let firstEntry = entries[0]
        return ASImportableAccount(
            id: accountIDData,
            userName: firstEntry.username,
            email: firstEntry.bundleEmailAddress ?? "",
            fullName: nil,
            collections: [],
            items: items
        )
    }

    // MARK: - 错误

    enum CredentialExchangeError: LocalizedError {
        case missingImportToken
        case nothingToExport

        var errorDescription: String? {
            switch self {
            case .missingImportToken:
                return "Credential Exchange 导入失败：缺少 ASCredentialImportToken。"
            case .nothingToExport:
                return "Credential Exchange 导出失败：没有可导出的密码条目。"
            }
        }
    }
}

@available(iOS 26, *)
private extension Bundle {
    /// 展示名称，缺失时回退到 bundleIdentifier。
    var displayName: String {
        (infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (infoDictionary?["CFBundleName"] as? String)
            ?? bundleIdentifier
            ?? "VaultCell"
    }
}
