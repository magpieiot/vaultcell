/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// UIDesignTokens.swift
/// ------------------------------------------------------------------

import SwiftUI

/// 主 App 与 AutoFill 扩展共用的界面常量。
/// 只依赖 SwiftUI，不引用主 App 的 Colors.swift / BiometricType，
/// 这样两个 target 都能编译同一份设计语言。

extension CGFloat {
    /// 间距统一走 4pt 网格：组内小于组间，页面边距 24
    static let spaceXs: CGFloat = 4
    static let spaceSm: CGFloat = 8
    static let spaceMd: CGFloat = 12
    static let spaceLg: CGFloat = 16
    static let spaceXl: CGFloat = 24
    static let spaceXxl: CGFloat = 32

    /// 控件 8 / 卡片 12~16 / 面板 24，嵌套圆角 = 外层 − padding
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 24
}

extension Color {
    /// 界面唯一的强调色。浅色下加深以保证白字 ≥4.5:1，深色下保持明亮蓝便于作为文字色。
    static let appAccent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.56, blue: 1.00, alpha: 1.00)
            : UIColor(red: 0.00, green: 0.38, blue: 0.82, alpha: 1.00)
    })

    /// 填充按钮上的前景色：浅色用白字，深色用深字，保证与强调色都有足够对比度
    static let appOnAccent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })

    /// 抬起的表面，深色下靠表面阶梯而不是阴影表达层级
    static let appSurface = Color(.secondarySystemBackground)
    /// 安静的描边
    static let appHairline = Color.primary.opacity(0.08)
}

extension Font {
    /// 大标题：语义字号，跟随动态类型
    static let appTitle = Font.system(.title, design: .default, weight: .medium)
    /// 关键数字统一等宽，避免 TOTP / 分数 / 计数跳动
    static func appNumber(_ style: Font.TextStyle = .title2) -> Font {
        Font.system(style, design: .default, weight: .medium).monospacedDigit()
    }
}

extension Animation {
    /// 反馈 120~180ms，入场 300ms，全 App 用同一条曲线
    static let appFeedback = Animation.easeOut(duration: 0.15)
    static let appEntrance = Animation.easeOut(duration: 0.3)
}
