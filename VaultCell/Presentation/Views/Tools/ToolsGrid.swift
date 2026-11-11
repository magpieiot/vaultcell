/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ToolsGrid.swift
/// created on: 23/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 工具卡点击后的目标页面
///
/// 用状态驱动跳转而不是 `NavigationLink`：卡片区是 `List` 的一行，
/// List 会给行内的 NavigationLink 自动加 disclosure（右侧箭头），
/// 并且同一行里放四个链接时，点击会串到错误的 destination。
private enum ToolRoute: Identifiable {
    case passwordGenerator
    case reusedPasswords
    case phoneMigration
    case emailMigration

    var id: Self { self }
}

/// 工具中心顶部的工具卡片网格
///
/// 用卡片而不是列表行，是为了和下方"配置型"的设置项区分开：
/// 卡片代表一个动作，列表行代表一个开关或一项配置。
/// 视觉语言沿用 `SecurityScoreDetailView`：渐变图标方块 + 实底圆角卡 + 极淡描边。
struct ToolsGrid: View {

    /// 生成器配置由工具中心独立持有，避免与编辑页的生成结果互相串改
    @ObservedObject var passwordGeneratorService: PasswordGeneratorService

    /// 换号前必须处理的手机号数量（0 时不显示徽标）
    let phoneBlockingCount: Int
    /// 换邮箱前必须处理的邮箱数量（0 时不显示徽标）
    let emailBlockingCount: Int
    /// 被多个账户共用的密码组数量（0 时不显示徽标）
    let reusedGroupCount: Int

    /// 当前要跳转的工具页，nil 表示停在工具中心
    @State private var route: ToolRoute?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 常规宽度（iPad / 横屏）给三列，紧凑宽度保持两列
    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: .spaceMd), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            generatorEntry
            reusedEntry
            phoneEntry
            emailEntry
        }
        // 这里不自己加 padding：水平缩进由 List 行的 insets 统一控制
        // （见 ToolsView.toolsSection），卡片左右边缘才能和下方设置块对齐；
        // 网格内再补 padding 就会比设置块多缩进一截
        .navigationDestination(item: $route) { destinationView(for: $0) }
    }

    // MARK: - 四个工具入口

    private var generatorEntry: some View {
        Button {
            route = .passwordGenerator
        } label: {
            ToolCard(
                icon: "key.fill",
                tint: .appAccent,
                title: "Password Generator",
                subtitle: "Make a strong password"
            )
        }
        .buttonStyle(ToolCardPressStyle())
    }

    private var reusedEntry: some View {
        Button {
            route = .reusedPasswords
        } label: {
            ToolCard(
                icon: "key.horizontal.fill",
                tint: .errorColor,
                title: "Reused Passwords",
                subtitle: "One password, many accounts",
                badgeCount: reusedGroupCount
            )
        }
        .buttonStyle(ToolCardPressStyle())
    }

    private var phoneEntry: some View {
        Button {
            route = .phoneMigration
        } label: {
            ToolCard(
                icon: "phone.fill",
                tint: .warningColor,
                title: "Phone Migration",
                subtitle: "What depends on a number",
                badgeCount: phoneBlockingCount
            )
        }
        .buttonStyle(ToolCardPressStyle())
    }

    private var emailEntry: some View {
        Button {
            route = .emailMigration
        } label: {
            ToolCard(
                icon: "envelope.fill",
                tint: .safetyColor,
                title: "Email Migration",
                subtitle: "What depends on an address",
                badgeCount: emailBlockingCount
            )
        }
        .buttonStyle(ToolCardPressStyle())
    }

    @ViewBuilder
    private func destinationView(for route: ToolRoute) -> some View {
        switch route {
        case .passwordGenerator:
            PasswordGeneratorView(service: passwordGeneratorService)
                .navigationTitle(AppLocale.string("Password Generator"))
                .navigationBarTitleDisplayMode(.inline)
                // 二级页面隐藏底部 TabBar
                .preference(key: TabBarVisibilityKey.self, value: true)
        case .reusedPasswords:
            ReusedPasswordCenterView()
        case .phoneMigration:
            IdentityReviewCenterView(kind: .phone)
        case .emailMigration:
            IdentityReviewCenterView(kind: .email)
        }
    }
}

/// 单张工具卡：中性图标方块 + 标题 + 一行说明，右侧可选数量徽标
///
/// 卡片底色是实色而不是材质：半透明叠在内容上会让正文对比度掉下去。
struct ToolCard: View {
    let icon: String
    /// 只用于图标与数量徽标，卡片本身保持中性表面
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var badgeCount: Int = 0

    private let cornerRadius: CGFloat = .radiusLg

    var body: some View {
        VStack(alignment: .leading, spacing: .spaceSm) {
            HStack(alignment: .top) {
                iconBadge
                Spacer(minLength: 0)
                if badgeCount > 0 {
                    countBadge
                }
            }

            VStack(alignment: .leading, spacing: .spaceXs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.spaceLg)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(cardBackground)
        .contentShape(Rectangle())
    }

    /// 中性抬起的图标方块，图标跟随文本角色色
    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .fill(Color.appSurface)
                .frame(width: 32, height: 32)

            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(tint)
        }
        .accessibilityHidden(true)
    }

    /// 待处理数量徽标：红色是"有东西要处理"的唯一强信号
    private var countBadge: some View {
        Text("\(badgeCount)")
            .font(.system(.caption, weight: .medium).monospacedDigit())
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.errorColor))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.appSurface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.appHairline, lineWidth: 1)
            )
    }
}

/// 工具卡按压反馈：按下即缩放、松手回弹
///
/// 按压由点击驱动而非手势拖拽，用临界阻尼弹簧（damping 1.0，无过冲）——
/// 没有速度需要承接，过冲只会让卡片看起来在抖。
private struct ToolCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 1), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        ToolsGrid(
            passwordGeneratorService: PasswordGeneratorService(),
            phoneBlockingCount: 2,
            emailBlockingCount: 0,
            reusedGroupCount: 3
        )
        .background(SettingsBackground().ignoresSafeArea())
    }
    .environmentObject(VaultListViewModel(referenceData: ReferenceDataService()))
}
