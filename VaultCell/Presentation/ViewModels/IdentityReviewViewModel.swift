/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IdentityReviewViewModel.swift
/// created on: 08/09/2026
/// ------------------------------------------------------------------

import Foundation

/// 手动评估的输入校验错误
///
/// 只存错误类型而不存已本地化的文案，视图层再映射为文案，
/// 这样应用内切换语言后提示会随之刷新。
enum ManualIdentityInputError {
    /// 输入为空
    case empty
    /// 既不像手机号也不像邮箱
    case unrecognized
}

/// 手机号 / 邮箱评审中心的状态容器
///
/// 只负责调度 `IdentityUsageAuditService` 与保存筛选状态，
/// 所有判定规则都留在领域层，便于单独验证。
@MainActor
final class IdentityReviewViewModel: ObservableObject {

    // MARK: - 状态

    /// 密码库中出现的全部手机号 / 邮箱（风险从高到低）
    @Published var reports: [IdentityReport] = []
    /// 只显示“换号前必须处理”的联系方式
    @Published var showOnlyActionable = false
    /// 手动评估的输入
    @Published var manualText = ""
    /// 手动评估的格式错误（视图层负责本地化）
    @Published var manualInputError: ManualIdentityInputError?

    // MARK: - 依赖

    private let auditService = IdentityUsageAuditService()

    // MARK: - 派生数据

    var phoneReports: [IdentityReport] {
        filtered(reports.filter { $0.kind == .phone })
    }

    var emailReports: [IdentityReport] {
        filtered(reports.filter { $0.kind == .email })
    }

    /// 按类型取报告（手机号与邮箱在设置页是两个独立入口）
    func reports(for kind: IdentityKind) -> [IdentityReport] {
        switch kind {
        case .phone: return phoneReports
        case .email: return emailReports
        }
    }

    /// 指定类型下“换号前必须处理”的联系方式数量，用于入口徽标
    func blockingCount(for kind: IdentityKind) -> Int {
        reports.filter { $0.kind == kind && $0.risk >= .high }.count
    }

    var isEmpty: Bool {
        reports.isEmpty
    }

    // MARK: - 操作

    func reload(entries: [PasswordEntry]) {
        reports = auditService.scan(entries: entries)
    }

    /// 评估任意输入的号码 / 邮箱，即使它还没被任何条目使用
    /// - Returns: 评估报告；`usages` 为空表示库中没有任何账户依赖它。
    ///           输入既不是手机号也不是邮箱时返回 nil。
    func evaluateManualInput(entries: [PasswordEntry]) -> IdentityReport? {
        let trimmed = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            manualInputError = .empty
            return nil
        }
        guard let report = auditService.evaluate(trimmed, in: entries) else {
            manualInputError = .unrecognized
            return nil
        }
        manualInputError = nil
        return report
    }

    func resetManualInput() {
        manualText = ""
        manualInputError = nil
    }

    // MARK: - 私有

    private func filtered(_ source: [IdentityReport]) -> [IdentityReport] {
        guard showOnlyActionable else { return source }
        return source.filter { $0.risk >= .high }
    }
}
