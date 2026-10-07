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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

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
                icon: "sparkles",
                tint: .secondaryBrandColor,
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
                .navigationTitle(String(localized: "Password Generator"))
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

/// 单张工具卡：渐变图标方块 + 标题 + 一行说明，图标行右侧可选红色数量徽标
///
/// 卡片底色是实色而不是材质：它下面是 `SettingsBackground` 渐变，
/// 半透明叠在渐变上会让正文对比度掉下去（Apple：颜色要放在实心层上）。
struct ToolCard: View {
    let icon: String
    /// 卡片主色：图标渐变与卡片底色的光晕都取自它，一张卡一个气质
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var badgeCount: Int = 0

    private let cornerRadius: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                iconBadge
                Spacer(minLength: 0)
                if badgeCount > 0 {
                    countBadge
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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
        .padding(12)
        // maxHeight 让卡片底铺满黄金比例算出的高度，内容仍顶对齐
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        // 黄金分割：宽 : 高 = 1.618 : 1
        .aspectRatio(1.618, contentMode: .fit)
        .contentShape(Rectangle())
    }

    /// 渐变图标方块：与 `SecurityScoreDetailView` 的分区图标同一个写法
    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .shadow(color: tint.opacity(0.3), radius: 6, y: 3)

            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .accessibilityHidden(true)
    }

    /// 待处理数量徽标：红色是"有东西要处理"的唯一强信号，不随卡片主色变化
    private var countBadge: some View {
        Text("\(badgeCount)")
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.errorColor))
    }

    /// 卡片底：实色底 + 主色光晕（右下角淡染）+ 极淡描边 + 轻投影
    ///
    /// 投影收到 6pt：行 insets 已归零，卡片左右边缘与下方设置块齐平，
    /// 原来的 10pt 阴影会外溢到设置块边缘之外，看起来"出框"。
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(.systemBackground), tint.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
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
