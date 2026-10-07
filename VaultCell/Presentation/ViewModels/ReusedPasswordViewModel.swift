/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ReusedPasswordViewModel.swift
/// created on: 30/09/2026
/// ------------------------------------------------------------------

import Foundation

/// 复用密码中心的状态容器
///
/// 只负责调度 `ReusedPasswordAuditService` 与保存筛选状态，
/// 分组规则全部留在领域层。这里持有的分组结果不含明文密码。
@MainActor
final class ReusedPasswordViewModel: ObservableObject {

    // MARK: - 状态

    /// 库中共用密码的分组（影响面从大到小）
    @Published private(set) var groups: [ReusedPasswordGroup] = []
    /// 只显示被 3 个及以上账户共用的密码组
    @Published var showOnlyWidespread = false

    // MARK: - 依赖

    private let auditService = ReusedPasswordAuditService()

    // MARK: - 派生数据

    var visibleGroups: [ReusedPasswordGroup] {
        guard showOnlyWidespread else { return groups }
        return groups.filter { $0.accountCount >= 3 }
    }

    /// 库中所有复用分组涉及的账户数之和（一个账户落在多组时按占用次数计）
    var affectedAccountCount: Int {
        groups.reduce(0) { $0 + $1.accountCount }
    }

    /// 最严重的复用等级，用于顶部结论的配色
    var topRisk: IdentityRiskLevel {
        groups.map(\.risk).max() ?? .low
    }

    var isEmpty: Bool { groups.isEmpty }

    // MARK: - 操作

    func reload(entries: [PasswordEntry]) {
        groups = auditService.scan(entries: entries)
    }
}
