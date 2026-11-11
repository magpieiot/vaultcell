/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ReusedPasswordCenterView.swift
/// created on: 30/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 复用密码中心
///
/// 像“手机号 / 邮箱评审”那样按值聚合：一行是一个被多个账户共用的密码，
/// 点进去看它牵连了哪些账户 —— 回答的是“哪一个密码泄露会连带一串账户”。
///
/// 密码不是联系方式，它是完整凭据，因此本页有三条硬约束：
/// 1. 默认只显示首尾各 2 个字符、中间打码，完整明文由眼睛按钮切换（与 `PasswordDetailView` 同一套交互）；
/// 2. 不提供复制：明文不进系统剪贴板；
/// 3. 分组结果只含条目 id（见 `ReusedPasswordGroup`），明文按需现取，不落地、不缓存、不进日志。
struct ReusedPasswordCenterView: View {

    @StateObject private var reusedVM = ReusedPasswordViewModel()
    @EnvironmentObject var viewModel: VaultListViewModel

    /// 本页文案在 body 内本地化，需要这层依赖才会随语言切换重算
    @Environment(\.locale) private var locale

    /// 评审面向整个密码库，不受主列表当前筛选影响
    private var entries: [PasswordEntry] {
        viewModel.items.compactMap {
            guard case .password(let entry) = $0 else { return nil }
            return entry
        }
    }

    var body: some View {
        let _ = locale

        List {
            summarySection

            if reusedVM.visibleGroups.isEmpty {
                emptySection
            } else {
                groupsSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground())
        .navigationTitle(AppLocale.string("Reused Passwords"))
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
        .toolbar { filterToolbarItem }
        .onAppear {
            reusedVM.reload(entries: entries)
        }
        .onChange(of: viewModel.items.count) { _, _ in
            // 密码库条目增减后重新扫描
            reusedVM.reload(entries: entries)
        }
    }

    // MARK: - 分区

    /// 顶部结论：库里有多少个密码被共用、牵连多少账户
    private var summarySection: some View {
        Section {
            IdentityNote(
                icon: reusedVM.isEmpty ? "checkmark.shield.fill" : "key.horizontal.fill",
                text: summaryText,
                tint: reusedVM.isEmpty ? .successColor : reusedVM.topRisk.tint
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        } footer: {
            Text(
                AppLocale.string("Only the first and last two characters are shown. Open a group to see the full password — it never touches the clipboard."
                )
            )
        }
    }

    private var groupsSection: some View {
        Section {
            ForEach(reusedVM.visibleGroups) { group in
                NavigationLink {
                    ReusedPasswordGroupDetailView(group: group)
                } label: {
                    ReusedPasswordGroupRow(group: group)
                }
            }
        } header: {
            Text(AppLocale.string("Shared passwords"))
        } footer: {
            Text(
                AppLocale.string("Give each account its own password so one breach cannot unlock the rest."
                )
            )
        }
    }

    /// 区分两种空态：库里没有复用 / 被筛选掉了
    private var emptySection: some View {
        Section {
            IdentityNote(
                icon: reusedVM.isEmpty ? "checkmark.shield.fill" : "line.3.horizontal.decrease.circle",
                text: reusedVM.isEmpty ? summaryText : AppLocale.string("No password is shared by three or more accounts. Turn off the filter to see every shared password."
                ),
                tint: reusedVM.isEmpty ? .successColor : .primaryBrandColor
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        }
    }

    private var summaryText: String {
        guard !reusedVM.isEmpty else {
            return AppLocale.string("Every saved account has its own password. Nothing is reused."
            )
        }
        return String(
            format: AppLocale.string("%lld passwords are shared by %lld accounts."),
            reusedVM.groups.count,
            reusedVM.affectedAccountCount
        )
    }

    // MARK: - 工具栏

    private var filterToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    reusedVM.showOnlyWidespread.toggle()
                }
            } label: {
                Image(
                    systemName: reusedVM.showOnlyWidespread
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .foregroundColor(reusedVM.showOnlyWidespread ? .primaryBrandColor : .secondary)
            }
            .accessibilityLabel(AppLocale.string("Only show passwords shared by 3 or more accounts"))
        }
    }
}

// MARK: - 列表行

/// 一行 = 一个被共用的密码：只给掩码与影响面，明文留给详情页
private struct ReusedPasswordGroupRow: View {
    let group: ReusedPasswordGroup

    @EnvironmentObject private var viewModel: VaultListViewModel

    /// 组内条目的密码相同，取标识条目的明文做局部展示
    private var password: String {
        for item in viewModel.items {
            guard case .password(let entry) = item else { continue }
            if entry.id == group.id { return entry.password }
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [group.risk.tint, group.risk.tint.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                // 首尾各 2 个字符明码，用于分辨是哪一组；
                // 中间掩码固定 8 个点，不随真实长度变化，长度信息不外泄
                Text(verbatim: partiallyMaskedPassword(password))
                    .font(.body.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            RiskBadge(level: group.risk)
        }
        .padding(.vertical, 4)
    }

    /// 副标题说后果：影响几个账户、其中几个还有 2FA 兜底
    private var subtitle: String {
        let count = group.accountCount
        if group.protectedCount == 0 {
            return String(
                format: AppLocale.string("%lld accounts · none has 2FA"),
                count
            )
        }
        return String(
            format: AppLocale.string("%lld accounts · %lld protected by 2FA"),
            count,
            group.protectedCount
        )
    }
}

// MARK: - 分组详情

/// 单个复用密码的详情：揭示明文 + 列出牵连的账户
private struct ReusedPasswordGroupDetailView: View {

    let group: ReusedPasswordGroup

    @EnvironmentObject var viewModel: VaultListViewModel
    @Environment(\.locale) private var locale

    /// 跳转条目详情所需的审计结果（进入页面时计算一次）
    @State private var audit: VaultSecurityAudit?

    @State private var isRevealed = false

    private var entriesByID: [UUID: PasswordEntry] {
        var map: [UUID: PasswordEntry] = [:]
        for item in viewModel.items {
            guard case .password(let entry) = item else { continue }
            map[entry.id] = entry
        }
        return map
    }

    /// 明文按需现取：组内条目的密码相同，取标识条目即可
    private var password: String {
        entriesByID[group.id]?.password ?? ""
    }

    var body: some View {
        let _ = locale

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                IdentityEntrance(delay: 0) { heroCard }
                IdentityEntrance(delay: 0.07) { accountsSection }
                IdentityEntrance(delay: 0.14) { guidanceSection }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(AppLocale.string("Shared Password"))
        .navigationBarTitleDisplayMode(.inline)
        .preference(key: TabBarVisibilityKey.self, value: true)
        .onAppear {
            // 只在进入页面时计算一次，供条目详情跳转使用
            guard audit == nil else { return }
            audit = VaultSecurityAuditService().calculate(entries: Array(entriesByID.values))
        }
    }

    // MARK: - 色彩

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                group.risk.tint.opacity(0.16),
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
                    Text(AppLocale.string("Shared by"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    passwordLine
                }
                Spacer(minLength: 8)
                RiskBadge(level: group.risk)
            }

            Text(conclusion)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            group.risk.tint.opacity(0.10)
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
        .shadow(color: group.risk.tint.opacity(0.18), radius: 16, y: 10)
    }

    /// 眼睛按钮在“中间打码”和“完整明文”之间切换，与条目详情页的密码行同一套交互
    private var passwordLine: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    // 明文：标记 privacySensitive，系统截图 / 录屏时自动隐藏该区域
                    PasswordText(
                        password,
                        font: .system(.title3, design: .monospaced),
                        letterColor: .primary,
                        digitColor: .primaryBrandColor,
                        symbolColor: .warningColor
                    )
                    .lineLimit(1)
                    .privacySensitive()
                } else {
                    Text(verbatim: partiallyMaskedPassword(password))
                        .font(.title3.monospaced())
                        .foregroundColor(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .accessibilityLabel(
                isRevealed
                    ? AppLocale.string("Password revealed")
                    : AppLocale.string("Password hidden")
            )

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRevealed.toggle()
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isRevealed
                    ? AppLocale.string("Hide password")
                    : AppLocale.string("Reveal password")
            )
        }
    }

    private var conclusion: String {
        let count = group.accountCount
        if group.protectedCount == 0 {
            return String(
                format: AppLocale.string("%lld accounts share this password, and none of them has 2FA. One leak opens all of them."
                ),
                count
            )
        }
        return String(
            format: AppLocale.string("%lld accounts share this password. %lld of them still have 2FA as a second lock."
            ),
            count,
            group.protectedCount
        )
    }

    // MARK: - 牵连的账户

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            IdentitySectionHeader(
                icon: "person.2.fill",
                title: AppLocale.string("Accounts using it"),
                subtitle: AppLocale.string("Give each one its own password."),
                tint: group.risk.tint
            )

            IdentityPanel {
                ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                    accountRow(account)
                    if index != group.accounts.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ account: ReusedPasswordAccount) -> some View {
        let entry = entriesByID[account.entryID]

        HStack(alignment: .center, spacing: 12) {
            CachedIconView(
                request: IconRequest(
                    title: entry?.siteName ?? account.siteName,
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
                Text(account.siteName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle(for: account))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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

    private func subtitle(for account: ReusedPasswordAccount) -> String {
        if account.username.isEmpty {
            return account.has2FA
                ? AppLocale.string("2FA is on")
                : AppLocale.string("No 2FA")
        }
        return account.has2FA
            ? String(
                format: AppLocale.string("%@ · 2FA is on"),
                account.username
            )
            : String(
                format: AppLocale.string("%@ · no 2FA"),
                account.username
            )
    }

    // MARK: - 收尾建议

    private var guidanceSection: some View {
        IdentityNote(
            icon: "lock.shield.fill",
            text: AppLocale.string("Change these accounts one at a time. Breach detection is planned, so reuse is the clearest signal you have."
            ),
            tint: .primaryBrandColor
        )
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

// MARK: - 常量

/// 掩码固定 8 个点：不随密码长度变化，避免把长度也泄露出去
private let maskedPassword = String(repeating: "•", count: 8)

/// 列表行的局部展示：首 2 字符 + 固定长度掩码 + 尾 2 字符
///
/// 首尾明码用来分辨“这是哪一组”，中间仍是固定 8 个点；
/// 密码过短（≤4 个字符）时首尾几乎就是全部，直接整段掩码。
private func partiallyMaskedPassword(_ password: String) -> String {
    guard password.count > 4 else { return maskedPassword }
    return "\(password.prefix(2))\(maskedPassword)\(password.suffix(2))"
}

#Preview {
    NavigationStack {
        ReusedPasswordCenterView()
    }
    .environmentObject(VaultListViewModel(referenceData: ReferenceDataService()))
}
