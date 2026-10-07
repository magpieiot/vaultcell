/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ReusedPasswordAuditService.swift
/// created on: 30/09/2026
/// ------------------------------------------------------------------

import Foundation

/// 某个账户对一组复用密码的占用
struct ReusedPasswordAccount: Identifiable, Hashable {
    var id: UUID { entryID }

    let entryID: UUID
    let siteName: String
    let username: String
    /// 该账户是否已开启 2FA：密码泄露时至少还有第二道防线
    let has2FA: Bool
}

/// 一组共用同一个密码的账户
///
/// 结果里**不保存明文密码**：分组键只活在 `scan(entries:)` 的作用域内，
/// 需要展示时按 `entryID` 回到密码库现取，避免明文随分组结果长期驻留内存。
struct ReusedPasswordGroup: Identifiable, Hashable {
    /// 以组内首个条目的 id 作为标识（该 id 同时是取明文用的入口）
    let id: UUID
    let accounts: [ReusedPasswordAccount]

    var accountCount: Int { accounts.count }

    /// 组内已开启 2FA 的账户数
    var protectedCount: Int { accounts.filter(\.has2FA).count }

    /// 复用严重程度：共用账户越多，一次泄露的影响面越大。
    /// 3 个以上账户共用、且没有一个开启 2FA 时直接按最严重处理。
    var risk: IdentityRiskLevel {
        if accountCount >= 3, protectedCount == 0 { return .critical }
        switch accountCount {
        case 0, 1: return .low
        case 2: return .medium
        case 3, 4: return .high
        default: return .critical
        }
    }
}

/// 复用密码审计：把“哪些账户共用一个密码”聚成组
///
/// 与 `VaultSecurityAuditService` 的重复检测同一口径（同一套归一化与
/// OAuth 排除规则），只是这里要的是分组而不是计数：一行一个密码，
/// 回答“哪一个密码泄露会连带一串账户”。
///
/// 只做纯内存计算，不接触存储层，不写日志，也不保留明文。
struct ReusedPasswordAuditService {

    // MARK: - 对外接口

    /// 扫描整个密码库，返回共用密码的分组（影响面从大到小）
    func scan(entries: [PasswordEntry]) -> [ReusedPasswordGroup] {
        // 只统计自己持有凭据的条目：OAuth 衍生条目用的是源账户的凭据，
        // 算进来会重复计数（口径与 `VaultSecurityAuditService` 一致）。
        let owned = entries.filter { $0.oAuthProvider == nil || Self.isSelfContainedOAuthEntry($0) }

        // 明文键只活在这个作用域：函数返回后剩下的只有条目 id
        var buckets: [String: [PasswordEntry]] = [:]
        var order: [String] = []
        buckets.reserveCapacity(owned.count)

        for entry in owned {
            let key = Self.normalize(entry.password)
            guard !key.isEmpty else { continue }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }

        return order.compactMap { key in
            guard let members = buckets[key], members.count > 1 else { return nil }
            let accounts = members
                .map {
                    ReusedPasswordAccount(
                        entryID: $0.id,
                        siteName: $0.siteName,
                        username: $0.username,
                        has2FA: $0.has2FA
                    )
                }
                .sorted { $0.siteName.localizedCaseInsensitiveCompare($1.siteName) == .orderedAscending }
            return ReusedPasswordGroup(id: members[0].id, accounts: accounts)
        }
        .sorted { lhs, rhs in
            // 只按影响面排序：不按密码内容排序，否则列表顺序会把明文前缀带出来
            guard lhs.accountCount == rhs.accountCount else {
                return lhs.accountCount > rhs.accountCount
            }
            return (lhs.accounts.first?.siteName ?? "")
                .localizedCaseInsensitiveCompare(rhs.accounts.first?.siteName ?? "") == .orderedAscending
        }
    }

    // MARK: - 私有规则

    /// 与 `VaultSecurityAuditService.normalizePassword` 同一套规则：
    /// 去首尾空白 + 转小写 + 去重音，保证两处判定出来的“同一个密码”是同一个。
    private static func normalize(_ password: String) -> String {
        password
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    /// 判断条目是否为“OAuth 凭据源账户”型（与 `VaultSecurityAuditService` 同规则）：
    /// 其 OAuth 绑定值等于自身登录名，说明它自己持有该凭据，而非通过他人账户登录。
    private static func isSelfContainedOAuthEntry(_ entry: PasswordEntry) -> Bool {
        guard let bound = entry.oAuthProvider?.boundValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !bound.isEmpty else { return false }
        let ownValues = [entry.username, entry.bundleEmailAddress ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return ownValues.contains(bound)
    }
}
