/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IdentityReviewComponents.swift
/// created on: 08/09/2026
/// ------------------------------------------------------------------

import SwiftUI

// MARK: - 风险配色

extension IdentityRiskLevel {
    /// 风险等级对应的语义色（与项目 Colors.swift 中的语义色保持一致）
    var tint: Color {
        switch self {
        case .low: return .secondary
        case .medium: return .primaryBrandColor
        case .high: return .warningColor
        case .critical: return .errorColor
        }
    }

    /// 用于深色填充面：保证白色前景文字的对比度
    var deepTint: Color {
        switch self {
        case .low:
            return Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1.00) // #C7C7CC
                    : UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1.00) // #3C3C43
            })
        case .medium: return .primaryBrandColor
        case .high: return .warningColor
        case .critical: return .errorColor
        }
    }
}

extension IdentityRole {
    /// 用途对应的语义色：越靠近“找回通道”越危险
    var tint: Color {
        switch self {
        case .recovery: return .errorColor
        case .twoFactor, .oauth: return .warningColor
        case .login, .contact: return .primaryBrandColor
        case .mention: return .secondary
        }
    }
}

// MARK: - 脱敏

/// 联系方式脱敏
///
/// 密码管理器里不应默认把完整号码铺在列表上，
/// 默认只暴露可辨认的前后段，点击后才完整显示。
enum IdentityMasker {
    static func masked(_ value: String, kind: IdentityKind) -> String {
        switch kind {
        case .phone:
            return maskedPhone(value)
        case .email:
            return maskedEmail(value)
        }
    }

    private static func maskedPhone(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        guard digits.count >= 7 else {
            return String(repeating: "•", count: max(digits.count, 3))
        }
        let prefix = digits.prefix(3)
        let suffix = digits.suffix(4)
        let prefixText = value.hasPrefix("+") ? "+" : ""
        return "\(prefixText)\(prefix)••••\(suffix)"
    }

    private static func maskedEmail(_ value: String) -> String {
        guard let atIndex = value.lastIndex(of: "@") else {
            return String(repeating: "•", count: min(value.count, 10))
        }
        let local = String(value[value.startIndex..<atIndex])
        let domain = String(value[value.index(after: atIndex)...])
        let head = local.prefix(1)
        let stars = String(repeating: "•", count: min(max(local.count - 1, 2), 4))
        return "\(head)\(stars)@\(domain)"
    }
}

// MARK: - 联系方式文本（可切换明文）

/// 默认脱敏，点击眼睛按钮切换完整显示
struct IdentityValueText: View {
    let value: String
    let kind: IdentityKind
    var font: Font = .body

    @State private var isRevealed = false
    /// 辅助功能文案由 `AppLocale.string` 求值，需要语言依赖才会随切换重绘
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale

        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isRevealed.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(isRevealed ? value : IdentityMasker.masked(value, kind: kind))
                    .font(font.monospaced())
                    .lineLimit(1)
                    .contentTransition(.numericText())

                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isRevealed ? value : AppLocale.string("Hidden, double tap to reveal")
        )
    }
}

// MARK: - 风险徽标

/// 风险胶囊：填充色 + 图标 + 文字三重编码，不依赖颜色单独表意
struct RiskBadge: View {
    let level: IdentityRiskLevel
    var showsIcon = true

    /// 风险名在 body 内本地化，语言切换时参数不变，需要自身依赖语言环境
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale

        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: level.iconName)
                    .font(.caption2.weight(.bold))
            }
            Text(level.displayName)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(level.deepTint))
    }
}

// MARK: - 用途标签

struct UsageChip: View {
    let role: IdentityRole

    /// 用途名在 body 内本地化，语言切换时参数不变，需要自身依赖语言环境
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale

        HStack(spacing: 4) {
            Image(systemName: role.iconName)
                .font(.caption2)
            Text(role.displayName)
                .font(.caption)
        }
        .foregroundColor(role.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().strokeBorder(role.tint.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - 依赖条带

/// 本页的签名元素：把“这个号码绑了多少东西”画成一根堆叠条。
/// 只有高风险的段使用饱和色，视线会自动落在最危险的那一段。
struct DependencyBand: View {
    let report: IdentityReport

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 图例与辅助功能摘要含本地化文案，需要语言依赖才会随切换重算
    @Environment(\.locale) private var locale
    @State private var progress: CGFloat = 0

    private struct Segment: Identifiable {
        let role: IdentityRole
        let count: Int
        var id: Int { role.rawValue }
    }

    /// 每个条目按其最重的用途归入一段，避免同一条目被重复计数
    private var segments: [Segment] {
        var counts: [IdentityRole: Int] = [:]
        for usage in report.usages {
            guard let dominant = usage.sortedRoles.first else { continue }
            counts[dominant, default: 0] += 1
        }
        let order: [IdentityRole] = [.recovery, .twoFactor, .oauth, .login, .contact, .mention]
        return order.compactMap { role in
            guard let count = counts[role], count > 0 else { return nil }
            return Segment(role: role, count: count)
        }
    }

    private var total: Int {
        max(report.usages.count, 1)
    }

    var body: some View {
        let _ = locale

        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        let width = proxy.size.width * CGFloat(segment.count) / CGFloat(total) * progress
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(segment.role.tint)
                            .frame(width: max(width, segment.count > 0 ? 3 : 0))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
            .clipShape(Capsule())

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Image(systemName: segment.role.iconName)
                            .font(.caption2)
                            .foregroundColor(segment.role.tint)
                            .frame(width: 14)
                        // 用途名已本地化，数字无需翻译，整段按原样输出
                        Text(verbatim: "\(segment.role.displayName) \(segment.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear {
            guard reduceMotion else {
                progress = 1
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.88)) {
                progress = 1
            }
        }
    }

    private var accessibilitySummary: String {
        let detail = segments
            .map { "\($0.role.displayName) \($0.count)" }
            .joined(separator: ", ")
        return String(
            format: AppLocale.string("%lld accounts depend on it: %@"),
            report.usages.count,
            detail
        )
    }
}

// MARK: - 容器与分区标题

/// 分区标题：渐变图标胶囊 + 标题 + 说明，与安全评分页保持同一语言
struct IdentitySectionHeader: View {
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
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fontDesign(.rounded)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct IdentityPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 入场动效

/// 分区入场包装：淡入 + 轻微上移，逐段延迟形成节奏；开启“减弱动态”时直接显示
struct IdentityEntrance<Content: View>: View {
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
            .offset(y: visible || reduceMotion ? 0 : 16)
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

/// 空态与结论态共用的提示面板
struct IdentityNote: View {
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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}
