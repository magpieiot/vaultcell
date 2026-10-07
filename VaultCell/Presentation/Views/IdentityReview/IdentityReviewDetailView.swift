/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IdentityReviewDetailView.swift
/// created on: 08/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 单个手机号 / 邮箱的评审详情
///
/// 这一页负责传达“后果”：顶部给出结论，下面给出换号前必须处理的账户清单。
/// 视觉上沿用安全评分页的渐变大卡语言，但把分数圆环换成了依赖条带 ——
/// 这里没有得分，只有依赖。
struct IdentityReviewDetailView: View {

    let report: IdentityReport
    /// 由“手动评估”进入时展示来源说明
    var isManualCheck = false

    @EnvironmentObject var viewModel: VaultListViewModel
    /// 监听应用内语言切换：本页文案由 `String(localized:)` 求值，
    /// 没有这层依赖时切换语言不会重算标题与结论
    @EnvironmentObject private var languageManager: AppLanguageManager

    /// 跳转条目详情所需的审计结果（进入页面时计算一次）
    @State private var audit: VaultSecurityAudit?

    private var entriesByID: [UUID: PasswordEntry] {
        var map: [UUID: PasswordEntry] = [:]
        for item in viewModel.items {
            guard case .password(let entry) = item else { continue }
            map[entry.id] = entry
        }
        return map
    }

    private var blockingUsages: [IdentityUsage] {
        report.blockingUsages
    }

    private var remainingUsages: [IdentityUsage] {
        report.usages.filter { $0.risk < .high }
    }

    var body: some View {
        // 读取当前语言，使其在切换时触发本页重新计算本地化文案
        let _ = languageManager.current

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                IdentityEntrance(delay: 0) { heroCard }
                IdentityEntrance(delay: 0.07) { actionSection }
                if !remainingUsages.isEmpty {
                    IdentityEntrance(delay: 0.14) { remainingSection }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(report.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .preference(key: TabBarVisibilityKey.self, value: true)
        .onAppear {
            // 只在进入页面时计算一次，供条目详情跳转使用
            guard audit == nil else { return }
            let entries = viewModel.items.compactMap { item -> PasswordEntry? in
                guard case .password(let entry) = item else { return nil }
                return entry
            }
            audit = VaultSecurityAuditService().calculate(entries: entries)
        }
    }

    // MARK: - 色彩

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                report.risk.tint.opacity(0.16),
                Color(.systemBackground),
                Color(.secondarySystemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.kind.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    IdentityValueText(value: report.value, kind: report.kind, font: .title3)
                }
                Spacer(minLength: 8)
                RiskBadge(level: report.risk)
            }

            if !report.usages.isEmpty {
                DependencyBand(report: report)
            }

            Text(conclusion)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if isManualCheck {
                Text(String(localized: "Checked on demand — this value is not saved as an entry field."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            report.risk.tint.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: report.risk.tint.opacity(0.18), radius: 16, y: 10)
    }

    private var conclusion: String {
        guard !report.usages.isEmpty else {
            return String(
                localized:
                    "No saved account depends on this. If you still use it somewhere, add it to an entry first."
            )
        }
        if report.criticalCount > 0 {
            return String(
                format: String(
                    localized:
                        "Without it, %lld accounts can’t be recovered. Rebind them before you give it up."
                ),
                report.criticalCount
            )
        }
        if !blockingUsages.isEmpty {
            return String(
                format: String(
                    localized:
                        "%lld accounts use it for verification. Rebind those before you give it up."
                ),
                blockingUsages.count
            )
        }
        return String(
            format: String(
                localized:
                    "%lld accounts keep it on file, but all of them have another way to recover."
            ),
            report.usages.count
        )
    }

    // MARK: - 待办清单

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            IdentitySectionHeader(
                icon: "exclamationmark.shield.fill",
                title: String(localized: "Before you give it up"),
                subtitle: String(localized: "Rebind these accounts first."),
                tint: report.risk.tint
            )

            if blockingUsages.isEmpty {
                IdentityNote(
                    icon: "checkmark.circle.fill",
                    text: String(
                        localized:
                            "Nothing blocks you. No saved account depends on this to get back in."
                    ),
                    tint: .successColor
                )
            } else {
                IdentityPanel {
                    ForEach(Array(blockingUsages.enumerated()), id: \.element.id) { index, usage in
                        usageRow(usage, index: index)
                        if index != blockingUsages.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    private var remainingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            IdentitySectionHeader(
                icon: "clock.badge.checkmark",
                title: String(localized: "Can wait"),
                subtitle: String(localized: "These accounts have another way to recover."),
                tint: .secondary
            )

            IdentityPanel {
                ForEach(Array(remainingUsages.enumerated()), id: \.element.id) { index, usage in
                    usageRow(usage, index: nil)
                    if index != remainingUsages.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func usageRow(_ usage: IdentityUsage, index: Int?) -> some View {
        let entry = entriesByID[usage.entryID]

        HStack(alignment: .center, spacing: 12) {
            if let index {
                Text(verbatim: "\(index + 1)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(usage.risk.tint)
                    .frame(width: 22, height: 22)
                    .background(usage.risk.tint.opacity(0.14), in: Circle())
            }

            CachedIconView(
                request: IconRequest(
                    title: entry?.siteName ?? usage.siteName,
                    siteURL: entry?.siteURL,
                    manualIconURL: entry?.icon
                ),
                fallbackSystemName: "globe",
                placeholderColor: .secondary,
                placeholderFont: .callout
            )
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(usage.siteName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(reason(for: usage))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                roleChips(for: usage)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .ifLet(entry, audit: audit) { content, entry, audit in
            NavigationLink {
                PasswordDetailView(entry: entry, viewModel: viewModel, audit: audit)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private func roleChips(for usage: IdentityUsage) -> some View {
        let roles = usage.sortedRoles
        let visible = Array(roles.prefix(2))
        let hidden = roles.count - visible.count

        return HStack(spacing: 6) {
            ForEach(visible, id: \.self) { role in
                UsageChip(role: role)
            }
            if hidden > 0 {
                Text(verbatim: "+\(hidden)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// 用后果而不是字段名来描述依赖
    private func reason(for usage: IdentityUsage) -> String {
        if usage.roles.contains(.recovery) {
            return usage.risk == .critical
                ? String(localized: "Only way to get back into this account")
                : String(localized: "Password reset, with another way in")
        }
        if usage.roles.contains(.twoFactor) {
            if usage.twoFactorTypes.contains(.sms) {
                return String(localized: "Receives SMS sign-in codes")
            }
            if usage.twoFactorTypes.contains(.email) {
                return String(localized: "Receives email sign-in codes")
            }
            return String(localized: "Receives sign-in codes")
        }
        if usage.roles.contains(.oauth) {
            return String(localized: "Bound to third-party sign-in")
        }
        if usage.roles.contains(.login) {
            return String(localized: "Used as the login name")
        }
        if usage.roles.contains(.contact) {
            return String(localized: "Kept on file as a contact")
        }
        return String(localized: "Mentioned in notes or custom fields")
    }
}

// MARK: - 条件包装

private extension View {
    /// 条目与审计结果都可用时才允许跳转到条目详情
    @ViewBuilder
    func ifLet<Content: View>(
        _ entry: PasswordEntry?,
        audit: VaultSecurityAudit?,
        transform: (Self, PasswordEntry, VaultSecurityAudit) -> Content
    ) -> some View {
        if let entry, let audit {
            transform(self, entry, audit)
        } else {
            self
        }
    }
}
