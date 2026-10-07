/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SecurityIssueEntriesView.swift
/// created on: 22/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 分数配色（绿 → 黄 → 红），安全评分页与其下钻列表共用
enum SecurityScorePalette {
    static func color(forScore score: Int) -> Color {
        Color(hue: hue(forScore: score), saturation: 0.72, brightness: 0.62)
    }

    /// 用于深色填充面（分数胶囊、图标底），保证白色前景文字对比度
    static func deepColor(forScore score: Int) -> Color {
        Color(hue: hue(forScore: score), saturation: 0.78, brightness: 0.50)
    }

    private static func hue(forScore score: Int) -> Double {
        0.33 * (Double(clamped(score)) / 100)
    }

    private static func clamped(_ score: Int) -> Int {
        min(max(score, 0), 100)
    }
}

/// 安全评分"为何被扣分"某一分类的条目列表
///
/// 从失分原因卡片下钻进入，只展示命中该分类的条目，点击可进入条目详情处理。
/// 成员判定来自 `VaultSecurityAudit.issueEntryIDs`，与审计计分在同一个循环内收集，
/// 因此卡片上的数量与本页条数不会漂移。
///
/// 视觉语言与安全评分页保持一致：同色系渐变背景 + 圆角卡片。
struct SecurityIssueEntriesView: View {
    @ObservedObject var viewModel: VaultListViewModel
    let audit: VaultSecurityAudit
    let reason: VaultScoreReason

    /// 本页条目取自产成本次审计的同一批数据，避免与卡片数量对不上
    private var entries: [PasswordEntry] {
        let ids = Set(audit.entryIDs(for: reason.kind))
        return viewModel.passwordEntriesForAudit
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsScore = audit.entryScores[lhs.id] ?? 100
                let rhsScore = audit.entryScores[rhs.id] ?? 100
                if lhsScore == rhsScore {
                    return lhs.siteName.localizedCaseInsensitiveCompare(rhs.siteName) == .orderedAscending
                }
                return lhsScore < rhsScore
            }
    }

    private var tint: Color { SecurityScorePalette.color(forScore: audit.vaultScore) }
    private var tintDeep: Color { SecurityScorePalette.deepColor(forScore: audit.vaultScore) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(reason.title)
        .navigationBarTitleDisplayMode(.inline)
        // 安全评分的下级页面同样隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
    }

    // MARK: - 分区

    /// 分类说明卡：图标、数量胶囊与该分类的说明（与安全评分页卡片文案同源）
    private var header: some View {
        Panel {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.16), tint.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)

                    Image(systemName: reason.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(reason.title)
                            .font(.headline)
                            .fontDesign(.rounded)

                        Spacer(minLength: 8)

                        Text(reason.countText)
                            .font(.caption.weight(.semibold))
                            .fontDesign(.rounded)
                            .foregroundColor(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.12), in: Capsule())
                    }

                    Text(reason.detail)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            EmptyPanel(
                icon: "checkmark.circle.fill",
                text: String(localized: "No entries in this category."),
                tint: tint
            )
        } else {
            VStack(spacing: 12) {
                ForEach(entries) { entry in
                    NavigationLink {
                        PasswordDetailView(entry: entry, viewModel: viewModel, audit: audit)
                    } label: {
                        EntryIssueSummaryRow(
                            entry: entry,
                            score: audit.entryScores[entry.id] ?? 100,
                            issues: audit.entryIssues[entry.id] ?? []
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 背景

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    tint.opacity(0.16),
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(tintDeep.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: -220)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    struct Container: View {
        @StateObject var viewModel = VaultListViewModel(referenceData: ReferenceDataService())
        @State private var audit: VaultSecurityAudit?

        var body: some View {
            NavigationStack {
                if let audit {
                    SecurityIssueEntriesView(
                        viewModel: viewModel,
                        audit: audit,
                        reason: VaultScoreReason(
                            kind: .missing2FA,
                            title: String(localized: "Missing 2FA"),
                            count: audit.no2FACount,
                            countText: String(format: String(localized: "%lld entries"), audit.no2FACount),
                            detail: String(localized: "Accounts without 2FA are easier to take over even when the password is strong."),
                            symbol: "lock.open.fill"
                        )
                    )
                } else {
                    ProgressView()
                }
            }
            .task {
                await viewModel.loadItems()
                audit = VaultSecurityAuditService().calculate(entries: viewModel.passwordEntriesForAudit)
            }
        }
    }

    return Container()
}
