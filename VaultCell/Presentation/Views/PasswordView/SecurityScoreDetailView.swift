/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SecurityScoreDetailView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 安全评分详情页
/// 展示整个密码库的健康状况，包括总分、失分原因、改进建议以及需要优先处理的高风险账户。
/// 审计结果由上层列表页预先计算并传入，这里只负责展示。
///
/// 设计语言：与 Onboarding 保持一致 —— airy 浅色渐变背景、渐变图标、圆角字体、柔和阴影
/// 与弹簧入场动效，让“安全健康度”这一抽象概念通过视觉温度（分数色）被直观感知。
struct SecurityScoreDetailView: View {
    @ObservedObject var viewModel: VaultListViewModel
    let audit: VaultSecurityAudit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedScore: Double = 0

    private var passwordEntries: [PasswordEntry] {
        viewModel.passwordEntriesForAudit
    }

    /// 当前 vault 的失分原因列表
    /// 根据审计结果统计：重复密码、已泄露条目、未启用 2FA、超过一年未修改的弱密码等。
    private var scoreReasons: [VaultScoreReason] {
        var reasons: [VaultScoreReason] = []

        if audit.duplicateEntriesCount > 0 {
            reasons.append(
                VaultScoreReason(
                    title: String(localized: "Reused Passwords"),
                    countText: "\(audit.duplicateEntriesCount) entries",
                    detail: String(localized: "Reusing passwords increases the blast radius of a single leak."),
                    symbol: "arrow.triangle.2.circlepath"
                )
            )
        }

        if audit.compromisedEntriesCount > 0 {
            reasons.append(
                VaultScoreReason(
                    title: String(localized: "Compromised Entries"),
                    countText: "\(audit.compromisedEntriesCount) entries",
                    detail: String(localized: "Entries marked as compromised cap their own score and lower the vault score."),
                    symbol: "flame.fill"
                )
            )
        }

        if audit.no2FACount > 0 {
            reasons.append(
                VaultScoreReason(
                    title: String(localized: "Missing 2FA"),
                    countText: "\(audit.no2FACount) entries",
                    detail: String(localized: "Accounts without 2FA are easier to take over even when the password is strong."),
                    symbol: "lock.open.fill"
                )
            )
        }

        if audit.staleEntriesCount > 0 {
            reasons.append(
                VaultScoreReason(
                    title: String(localized: "Old Passwords"),
                    countText: "\(audit.staleEntriesCount) entries",
                    detail: String(localized: "Passwords that have not changed for over a year lose freshness points."),
                    symbol: "clock.fill"
                )
            )
        }

        if audit.weakEntriesCount > 0 {
            reasons.append(
                VaultScoreReason(
                    title: String(localized: "Low Entry Scores"),
                    countText: "\(audit.weakEntriesCount) entries",
                    detail: String(localized: "Short, predictable, or poorly protected passwords drag the vault average down."),
                    symbol: "chart.bar.fill"
                )
            )
        }

        return reasons
    }

    /// 存在安全问题的密码条目，按分数从低到高排序
    /// 用于“Accounts to improve first”区域，优先展示最危险的账户。
    private var riskyEntries: [PasswordEntry] {
        passwordEntries
            .filter { !(audit.entryIssues[$0.id] ?? []).isEmpty }
            .sorted { lhs, rhs in
                let lhsScore = audit.entryScores[lhs.id] ?? 100
                let rhsScore = audit.entryScores[rhs.id] ?? 100
                if lhsScore == rhsScore {
                    return lhs.siteName.localizedCaseInsensitiveCompare(rhs.siteName) == .orderedAscending
                }
                return lhsScore < rhsScore
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                EntranceWrapper(delay: 0.0) { heroSection }
                EntranceWrapper(delay: 0.07) { impactSection }
                EntranceWrapper(delay: 0.14) { recommendationsSection }
                EntranceWrapper(delay: 0.21) { riskyEntriesSection }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle("Security Score")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startScoreAnimation)
    }

    private func startScoreAnimation() {
        guard !reduceMotion else {
            animatedScore = Double(audit.vaultScore)
            return
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.86)) {
            animatedScore = Double(audit.vaultScore)
        }
    }

    // MARK: - 色彩

    /// 分数色：绿 → 黄 → 红，随分数线性过渡
    private var scoreHue: Double { 0.33 * (Double(audit.vaultScore) / 100) }
    private var scoreColor: Color {
        Color(hue: scoreHue, saturation: 0.72, brightness: 0.62)
    }
    /// 用于深色填充面（分数胶囊、图标底），保证白色前景文字对比度
    private var scoreColorDeep: Color {
        Color(hue: scoreHue, saturation: 0.78, brightness: 0.50)
    }

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    scoreColor.opacity(0.16),
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 顶部柔和光晕，呼应 Onboarding 的 radial 氛围
            Circle()
                .fill(scoreColor.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: -220)
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero 区域

    /// 顶部总分卡片
    /// 展示动态环状分数、总条目数、低分条目数以及已泄露条目数。
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vault health at a glance")
                    .font(.title.bold())
                    .fontDesign(.rounded)
                    .foregroundColor(.primary)

                Text(heroSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 22) {
                    ScoreRingView(score: animatedScore, color: scoreColorDeep)
                        .frame(width: 128, height: 128)
                    heroMetrics
                }

                VStack(alignment: .center, spacing: 18) {
                    ScoreRingView(score: animatedScore, color: scoreColorDeep)
                        .frame(width: 128, height: 128)
                    heroMetrics
                        .frame(maxWidth: .infinity)
                }
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
                            scoreColor.opacity(0.10)
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
        .shadow(color: scoreColor.opacity(0.18), radius: 16, y: 10)
    }

    private var heroMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricPill(icon: "tray.full", title: String(localized: "Total Entries"), value: "\(passwordEntries.count)", tint: scoreColor)
            MetricPill(icon: "exclamationmark.triangle.fill", title: String(localized: "Low Scores"), value: "\(audit.weakEntriesCount)", tint: scoreColor)
            MetricPill(icon: "shield.slash.fill", title: String(localized: "Compromised"), value: "\(audit.compromisedEntriesCount)", tint: scoreColor)
            if audit.oauthEntriesCount > 0 {
                MetricPill(icon: "person.2.fill", title: String(localized: "OAuth Sign-ins"), value: "\(audit.oauthEntriesCount)", tint: scoreColor)
            }
        }
    }

    // MARK: - 失分原因

    /// 失分原因区域
    /// 列出导致 vault 分数下降的主要问题，如无重复密码等则显示空面板。
    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView(
                icon: "exclamationmark.shield.fill",
                title: String(localized: "Why points were lost"),
                subtitle: String(localized: "These patterns are the biggest reasons your vault score is not higher."),
                tint: scoreColor
            )

            if scoreReasons.isEmpty {
                EmptyPanel(
                    icon: "checkmark.circle.fill",
                    text: String(localized: "No active deduction reasons were found."),
                    tint: scoreColor
                )
            } else {
                Panel {
                    VStack(spacing: 0) {
                        ForEach(scoreReasons.indices, id: \.self) { index in
                            ImpactReasonRow(reason: scoreReasons[index], tint: scoreColor)
                                .padding(.vertical, 12)
                            if index != scoreReasons.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 改进建议

    /// 改进建议区域
    /// 根据审计结果给出可执行的优化建议，按优先级顺序展示。
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView(
                icon: "checkmark.seal.fill",
                title: String(localized: "Recommended next steps"),
                subtitle: String(localized: "Focus on the highest-impact fixes first."),
                tint: scoreColor
            )

            if audit.suggestions.isEmpty {
                EmptyPanel(
                    icon: "checkmark.circle.fill",
                    text: String(localized: "No recommendations right now."),
                    tint: scoreColor
                )
            } else {
                Panel {
                    VStack(spacing: 0) {
                        ForEach(Array(audit.suggestions.enumerated()), id: \.offset) { index, suggestion in
                            RecommendationRow(index: index + 1, text: suggestion, tint: scoreColorDeep)
                                .padding(.vertical, 12)
                            if index != audit.suggestions.count - 1 {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 高风险账户

    /// 高风险账户列表
    /// 展示存在安全问题的密码条目，点击可跳转至详情页。
    private var riskyEntriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView(
                icon: "person.crop.circle.badge.exclamationmark",
                title: String(localized: "Accounts to improve first"),
                subtitle: String(localized: "Start with the lowest scores and the most severe issues."),
                tint: scoreColor
            )

            if riskyEntries.isEmpty {
                EmptyPanel(
                    icon: "checkmark.circle.fill",
                    text: String(localized: "No risky entries were found."),
                    tint: scoreColor
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(riskyEntries) { entry in
                        NavigationLink(destination: PasswordDetailView(entry: entry, viewModel: viewModel, audit: audit)) {
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
    }

    /// 根据 vault 分数返回对应的评语
    private var heroSubtitle: String {
        switch audit.vaultScore {
        case 90...100:
            return "Your vault is in excellent shape. Keep monitoring reused and aging passwords."
        case 75...89:
            return "Your vault is strong overall, but a few weak spots are still dragging the score down."
        case 60...74:
            return "Your vault needs attention. Fix the highlighted issues to raise the score quickly."
        case 40...59:
            return "Your vault has several high-risk patterns. Address the top items as soon as possible."
        default:
            return "Your vault is at critical risk. Start with compromised and reused passwords immediately."
        }
    }
}

// MARK: - 入场动效容器

/// 分区入场包装：淡入 + 轻微上移，逐段延迟形成节奏；开启“减弱动态”时直接显示。
private struct EntranceWrapper<Content: View>: View {
    let delay: Double
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    init(delay: Double, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.content = content()
    }

    var body: some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 20)
            .onAppear {
                guard !reduceMotion else {
                    visible = true
                    return
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) {
                    visible = true
                }
            }
    }
}

// MARK: - 分区标题

/// 带渐变图标胶囊的分区标题，呼应 Onboarding 的渐变图标语言。
private struct SectionHeaderView: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: tint.opacity(0.3), radius: 8, y: 4)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 单条失分原因

/// 单条失分原因的模型
private struct VaultScoreReason: Identifiable {
    let id = UUID()
    let title: String
    let countText: String
    let detail: String
    let symbol: String
}

/// 单条失分原因的展示行
/// 左侧渐变图标胶囊，右侧标题、数量胶囊与详细说明。
private struct ImpactReasonRow: View {
    let reason: VaultScoreReason
    let tint: Color

    var body: some View {
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
    }
}

// MARK: - 单条改进建议

/// 单条改进建议的展示行
/// 左侧渐变序号圆点，右侧建议文本。建议按优先级排序，序号是有意义的。
private struct RecommendationRow: View {
    let index: Int
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(color: tint.opacity(0.28), radius: 6, y: 3)

                Text("\(index)")
                    .font(.subheadline.bold())
                    .fontDesign(.rounded)
                    .foregroundColor(.white)
            }

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 高风险账户摘要

/// 高风险账户的摘要行
/// 展示站点名、用户名、渐变分数胶囊以及前几条问题描述。
private struct EntryIssueSummaryRow: View {
    let entry: PasswordEntry
    let score: Int
    let issues: [String]

    private var scoreHue: Double { 0.33 * (Double(score) / 100) }
    private var scoreColor: Color {
        Color(hue: scoreHue, saturation: 0.72, brightness: 0.62)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.siteName)
                        .font(.headline)
                        .fontDesign(.rounded)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(score)")
                        .font(.subheadline.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [scoreColor, scoreColor.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                }

                Text(entry.username)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues.prefix(3), id: \.self) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(scoreColor.opacity(0.7))
                                .frame(width: 5, height: 5)

                            Text(issue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if issues.count > 3 {
                        Text("+\(issues.count - 3) more issues")
                            .font(.caption.weight(.semibold))
                            .fontDesign(.rounded)
                            .foregroundColor(scoreColor)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
        .contentShape(Rectangle())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.systemBackground))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }
}

// MARK: - 环状分数指示器

/// 环状分数指示器
/// 渐变弧线 + 外圈柔光，中心以圆角粗体展示分数。
private struct ScoreRingView: View {
    let score: Double
    let color: Color

    var body: some View {
        ZStack {
            // 外发光
            Circle()
                .fill(color.opacity(0.14))
                .blur(radius: 18)
                .padding(-10)

            // 轨道
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 13)

            // 进度弧
            Circle()
                .trim(from: 0, to: max(0.001, score / 100))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.45), color, color.opacity(0.8)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())

                Text("out of 100")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Security Score")
        .accessibilityValue("\(Int(score.rounded())) out of 100")
    }
}

// MARK: - 指标胶囊

/// 指标胶囊
/// 用于 hero 区域展示总条目数、低分条目数等关键数据，带语义图标。
private struct MetricPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - 空状态面板

/// 空状态面板
/// 当某个区域没有数据时展示友好提示。
private struct EmptyPanel: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }
}

// MARK: - 通用卡片容器

/// 通用卡片容器
/// 为内部内容提供圆角背景、细边框与柔和阴影。
private struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }
}

// MARK: - 预览

private struct SecurityScorePreviewContainer: View {
    @StateObject private var viewModel: VaultListViewModel

    private let previewEntries: [PasswordEntry]
    private let previewAudit: VaultSecurityAudit

    init() {
        let referenceData = ReferenceDataService()
        let entries = [
            PasswordEntry(
                siteName: "GitHub",
                siteURL: "https://github.com",
                username: "octocat@example.com",
                password: "GitHub#2026Dev",
                notes: "公司代码托管，已配置 SSH Key",
                categoryID: PasswordCategory.defaultCategoryID,
                tags: ["dev"],
                isFavorite: true,
                has2FA: true,
                breachStatus: .safe,
                twoFactorConfigs: [
                    TwoFactorConfig(type: .totp, issuer: "GitHub")
                ]
            ),
            PasswordEntry(
                siteName: "Notion",
                siteURL: "https://notion.so",
                username: "notes@example.com",
                password: "GitHub#2026Dev",
                notes: "重复密码样本",
                categoryID: PasswordCategory.defaultCategoryID,
                tags: ["work"],
                has2FA: false,
                breachStatus: .unknown
            ),
            PasswordEntry(
                siteName: "Old Bank",
                siteURL: "https://bank.example.com",
                username: "user@example.com",
                password: "abc123",
                notes: "弱密码与已泄露样本",
                categoryID: PasswordCategory.defaultCategoryID,
                has2FA: false,
                breachStatus: .compromised
            )
        ]

        _viewModel = StateObject(wrappedValue: VaultListViewModel(referenceData: referenceData))
        previewEntries = entries
        previewAudit = VaultSecurityAuditService().calculate(entries: entries)
    }

    var body: some View {
        NavigationStack {
            SecurityScoreDetailView(viewModel: viewModel, audit: previewAudit)
        }
        .task {
            viewModel.items = previewEntries.map { .password($0) }
        }
    }
}

#Preview("Light") {
    SecurityScorePreviewContainer()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SecurityScorePreviewContainer()
        .preferredColorScheme(.dark)
}
