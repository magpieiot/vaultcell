/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IdentityReviewCenterView.swift
/// created on: 08/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 手机号 / 邮箱评审中心
///
/// 列出密码库中出现过的每个手机号与邮箱，以及它们各自的风险等级，
/// 用于回答“注销或换号之前，哪些账户会受影响”。
///
/// 设计上延续设置页的语言（insetGrouped 列表 + 自定义行），
/// 情绪化的表达全部留给详情页，这里保持克制。
struct IdentityReviewCenterView: View {

    @StateObject private var reviewVM = IdentityReviewViewModel()
    @EnvironmentObject var viewModel: VaultListViewModel
    /// 监听应用内语言切换：`String(localized:)` 在求值后被缓存，
    /// 不建立这层依赖时切换语言不会重算标题与列表文案
    @EnvironmentObject private var languageManager: AppLanguageManager

    @State private var showingManualCheck = false

    /// 本页只评审这一种联系方式：手机号与邮箱在工具中心是两个独立入口
    let kind: IdentityKind

    init(kind: IdentityKind = .phone) {
        self.kind = kind
    }

    /// 评审面向整个密码库，不受主列表当前筛选影响
    private var entries: [PasswordEntry] {
        viewModel.items.compactMap {
            guard case .password(let entry) = $0 else { return nil }
            return entry
        }
    }

    private var visibleReports: [IdentityReport] {
        reviewVM.reports(for: kind)
    }

    var body: some View {
        // 读取当前语言，使其在切换时触发本页重新计算本地化文案
        let _ = languageManager.current

        List {
            manualCheckSection

            if visibleReports.isEmpty {
                emptySection
            } else {
                reportsSection(
                    title: kind.pluralDisplayName,
                    reports: visibleReports
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground())
        .navigationTitle(
            kind == .phone
                ? String(localized: "Phone Migration")
                : String(localized: "Email Migration")
        )
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
        .toolbar { filterToolbarItem }
        .sheet(isPresented: $showingManualCheck) {
            NavigationStack {
                ManualIdentityCheckView(entries: entries)
            }
            .environmentObject(viewModel)
        }
        .onAppear {
            reviewVM.reload(entries: entries)
        }
        .onChange(of: viewModel.items.count) { _, _ in
            // 密码库条目增减后重新扫描
            reviewVM.reload(entries: entries)
        }
    }

    // MARK: - 分区

    /// 手动评估入口：评估一个还没入库的号码 / 邮箱
    private var manualCheckSection: some View {
        Section {
            Button {
                showingManualCheck = true
            } label: {
                CustomLabel(
                    leadingIcon: "magnifyingglass",
                    leadingIconColor: .primaryBrandColor,
                    trailingIcon: "chevron.right",
                    text: "Check a number or email"
                )
            }
            .foregroundColor(.primary)
        } footer: {
            Text(
                String(
                    localized:
                        "Before you cancel a number or close an email, see which accounts still depend on it."
                )
            )
        }
    }

    private func reportsSection(title: String, reports: [IdentityReport]) -> some View {
        Section(title) {
            ForEach(reports) { report in
                NavigationLink {
                    IdentityReviewDetailView(report: report)
                } label: {
                    IdentityReportRow(report: report)
                }
            }
        }
    }

    /// 区分三种空态：库里一条联系方式都没有 / 该类型还没有 / 被筛选掉了
    private var emptyText: String {
        if reviewVM.isEmpty {
            return String(
                localized:
                    "No phone numbers or email addresses are saved yet. Add one to an entry and this list will show what depends on it."
            )
        }
        if reviewVM.showOnlyActionable {
            return String(
                localized:
                    "Nothing here needs action. Turn off the filter to see every saved identity."
            )
        }
        return String(
            format: String(
                localized: "No %@ are saved yet. Add one to an entry and it will show up here."),
            kind.pluralDisplayName
        )
    }

    private var emptySection: some View {
        Section {
            IdentityNote(
                icon: kind == .phone
                    ? "phone.badge.questionmark" : "envelope.badge.questionmark",
                text: emptyText,
                tint: .primaryBrandColor
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        }
    }

    // MARK: - 工具栏

    private var filterToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    reviewVM.showOnlyActionable.toggle()
                }
            } label: {
                Image(
                    systemName: reviewVM.showOnlyActionable
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .foregroundColor(reviewVM.showOnlyActionable ? .primaryBrandColor : .secondary)
            }
            .accessibilityLabel(String(localized: "Only show identities that need action"))
        }
    }
}

// MARK: - 列表行

private struct IdentityReportRow: View {
    let report: IdentityReport

    /// 副标题在 body 内本地化，语言切换时参数不变，需要自身依赖语言环境
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [report.risk.tint, report.risk.tint.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Image(systemName: report.kind.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                IdentityValueText(value: report.value, kind: report.kind, font: .body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            RiskBadge(level: report.risk)
        }
        .padding(.vertical, 4)
    }

    /// 副标题说后果，不说字段结构
    private var subtitle: String {
        let count = report.usages.count
        if report.criticalCount > 0 {
            return String(
                format: String(localized: "%lld accounts · %lld can’t be recovered"),
                count, report.criticalCount
            )
        }
        if !report.blockingUsages.isEmpty {
            return String(
                format: String(localized: "%lld accounts · %lld need rebinding"),
                count, report.blockingUsages.count
            )
        }
        return String(format: String(localized: "%lld accounts · safe to give up"), count)
    }
}

// MARK: - 手动评估

/// 输入任意号码 / 邮箱做一次评估，不要求它已经被保存
private struct ManualIdentityCheckView: View {

    @StateObject private var reviewVM = IdentityReviewViewModel()
    let entries: [PasswordEntry]

    @Environment(\.dismiss) private var dismiss
    /// 与评审中心同理：`String(localized:)` 需要这层依赖才会随语言切换重算
    @EnvironmentObject private var languageManager: AppLanguageManager
    @FocusState private var isFieldFocused: Bool

    @State private var result: IdentityReport?

    var body: some View {
        // 读取当前语言，使其在切换时触发本页重新计算本地化文案
        let _ = languageManager.current

        List {
            Section {
                TextField(
                    String(localized: "Phone number or email address"),
                    text: $reviewVM.manualText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .focused($isFieldFocused)

                if let error = reviewVM.manualInputError {
                    Text(errorMessage(for: error))
                        .font(.caption)
                        .foregroundColor(.errorColor)
                }
            } footer: {
                Text(
                    String(
                        localized:
                            "Nothing is saved. This only checks the entry you typed against your vault."
                    )
                )
            }

            Section {
                Button {
                    runEvaluation()
                } label: {
                    HStack {
                        Spacer()
                        Text(String(localized: "Check"))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(
                    reviewVM.manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result {
                resultSection(result)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground())
        .navigationTitle(String(localized: "Check an Identity"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(String(localized: "Close")) { dismiss() }
            }
        }
        .onAppear { isFieldFocused = true }
    }

    @ViewBuilder
    private func resultSection(_ report: IdentityReport) -> some View {
        Section(String(localized: "Result")) {
            if report.usages.isEmpty {
                IdentityNote(
                    icon: "checkmark.circle.fill",
                    text: String(
                        localized:
                            "No saved account uses this. If you still use it somewhere, add it to an entry first and check again."
                    ),
                    tint: .successColor
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            } else {
                NavigationLink {
                    IdentityReviewDetailView(report: report, isManualCheck: true)
                } label: {
                    IdentityReportRow(report: report)
                }
            }
        }
    }

    private func runEvaluation() {
        isFieldFocused = false
        result = reviewVM.evaluateManualInput(entries: entries)
    }

    /// 错误类型 → 本地化文案；在视图层求值，语言切换后提示随之刷新
    private func errorMessage(for error: ManualIdentityInputError) -> String {
        switch error {
        case .empty:
            return String(localized: "Enter a phone number or email address.")
        case .unrecognized:
            return String(localized: "That does not look like a phone number or email address.")
        }
    }
}

#Preview("Phone") {
    NavigationStack {
        IdentityReviewCenterView(kind: .phone)
    }
    .environmentObject(VaultListViewModel(referenceData: ReferenceDataService()))
    .environmentObject(AppLanguageManager.shared)
}

#Preview("Email") {
    NavigationStack {
        IdentityReviewCenterView(kind: .email)
    }
    .environmentObject(VaultListViewModel(referenceData: ReferenceDataService()))
    .environmentObject(AppLanguageManager.shared)
}
