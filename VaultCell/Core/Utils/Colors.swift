/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// colors.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import SwiftUI

extension Color {
    /// 主品牌色：蓝紫渐变起始色，用于主按钮、链接、强调态。
    static let primaryBrandColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.56, blue: 1.00, alpha: 1.00) // #408FFF
            : UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1.00) // #007AFF
    })

    /// 品牌紫已退场：保留同名入口兼容存量引用，统一返回主蓝色。
    /// 原先的「蓝 → 紫」渐变因此退化为纯色，界面只保留一个强调色。
    static let secondaryBrandColor = Color.primaryBrandColor

    /// 安全色：用于 2FA 已启用、加密保护等安全相关提示。
    static let safetyColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.62, blue: 0.30, alpha: 1.00) // #29A04D
            : UIColor(red: 0.12, green: 0.55, blue: 0.27, alpha: 1.00) // #1F8C45
    })

    /// 成功色：用于复制成功、保存成功等正向反馈。
    static let successColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.85, blue: 0.44, alpha: 1.00) // #4DD970
            : UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.00) // #34C759
    })

    /// 警告色：用于弱密码、2FA 风险等需要关注的中等风险提示。
    static let warningColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.71, blue: 0.25, alpha: 1.00) // #FFB540
            : UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1.00) // #FF9500
    })

    /// 错误色：用于删除、泄露密码、验证失败等危险/错误状态。
    static let errorColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.47, blue: 0.43, alpha: 1.00) // #FF786E
            : UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1.00) // #FF3B30
    })
}

// 颜色扩展：根据域名生成柔和的背景色
extension Color {
    /// 根据域名生成柔和的背景色
    static func backgroundFor(domain: String) -> Color {
        let cleanDomain = extractMainDomain(from: domain)
        let hash = deterministicHash(for: cleanDomain)
        let hue = Double(hash % 360) / 360.0

        return Color(uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                UIColor(hue: hue, saturation: 0.10, brightness: 0.22, alpha: 1.0)
            } else {
                UIColor(hue: hue, saturation: 0.12, brightness: 0.94, alpha: 1.0)
            }
        })
    }

    /// 根据域名生成与 backgroundFor 匹配的前景/强调色。
    /// 与 backgroundFor 使用同一套「主域名 + 确定性哈希」映射，
    /// 保证相同 domain 得到相同 hue，只是饱和度/亮度不同以确保对比度。
    static func tintFor(domain: String) -> Color {
        let cleanDomain = extractMainDomain(from: domain)
        let hash = deterministicHash(for: cleanDomain)
        let hue = Double(hash % 360) / 360.0

        return Color(uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                UIColor(hue: hue, saturation: 0.40, brightness: 0.85, alpha: 1.0)
            } else {
                UIColor(hue: hue, saturation: 0.45, brightness: 0.38, alpha: 1.0)
            }
        })
    }
    
    /// 辅助方法：提取主域名 (简单版)
    private static func extractMainDomain(from url: String) -> String {
        var domain = url.lowercased()
        domain = domain.replacingOccurrences(of: "^(https?://)?(www\\.)?", with: "", options: .regularExpression)
        domain = domain.replacingOccurrences(of: "/.*$", with: "", options: .regularExpression)
        return domain
    }
}   

// 颜色扩展：12 对颜色对
extension Color {
    /// 标签色原先只有浅色固定值，深色模式下会过亮。
    /// 按同一色相派生深色变体：背景压暗、前景提亮，保证前景在背景上仍可读。
    private static func adaptiveTagColor(
        _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, isBackground: Bool
    ) -> Color {
        let light = UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        return Color(uiColor: UIColor { trait in
            guard trait.userInterfaceStyle == .dark else { return light }
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            light.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            return isBackground
                ? UIColor(hue: hue, saturation: min(saturation, 0.35), brightness: 0.22, alpha: 1)
                : UIColor(
                    hue: hue, saturation: min(saturation * 0.8, 0.6), brightness: 0.80, alpha: 1)
        })
    }

    // MARK: - Misty Blue 雾蓝
    static let mistyBlueBackground = adaptiveTagColor(213, 221, 227, isBackground: true)
    static let mistyBlueForeground = adaptiveTagColor(46, 92, 138, isBackground: false)

    // MARK: - Moss Green 苔藓绿
    static let mossGreenBackground = adaptiveTagColor(216, 222, 208, isBackground: true)
    static let mossGreenForeground = adaptiveTagColor(74, 124, 63, isBackground: false)

    // MARK: - Terracotta 陶土粉
    static let terracottaBackground = adaptiveTagColor(232, 213, 204, isBackground: true)
    static let terracottaForeground = adaptiveTagColor(184, 92, 60, isBackground: false)

    // MARK: - Twilight Gray 暮云灰
    static let twilightGrayBackground = adaptiveTagColor(222, 222, 224, isBackground: true)
    static let twilightGrayForeground = adaptiveTagColor(90, 90, 110, isBackground: false)

    // MARK: - Amber Gold 琥珀金
    static let amberGoldBackground = adaptiveTagColor(237, 224, 204, isBackground: true)
    static let amberGoldForeground = adaptiveTagColor(200, 146, 10, isBackground: false)

    // MARK: - Iris Purple 鸢尾紫
    static let irisPurpleBackground = adaptiveTagColor(221, 213, 224, isBackground: true)
    static let irisPurpleForeground = adaptiveTagColor(107, 61, 122, isBackground: false)

    // MARK: - Sea Mist 海雾青
    static let seaMistBackground = adaptiveTagColor(208, 220, 220, isBackground: true)
    static let seaMistForeground = adaptiveTagColor(42, 122, 120, isBackground: false)

    // MARK: - Rose Ash 玫瑰灰
    static let roseAshBackground = adaptiveTagColor(224, 213, 216, isBackground: true)
    static let roseAshForeground = adaptiveTagColor(168, 69, 90, isBackground: false)

    // MARK: - Olive Gold 橄榄黄
    static let oliveGoldBackground = adaptiveTagColor(224, 224, 204, isBackground: true)
    static let oliveGoldForeground = adaptiveTagColor(138, 122, 26, isBackground: false)

    // MARK: - Slate Blue 石板蓝
    static let slateBlueBackground = adaptiveTagColor(210, 214, 220, isBackground: true)
    static let slateBlueForeground = adaptiveTagColor(58, 90, 140, isBackground: false)

    // MARK: - Ochre Brown 赭石棕
    static let ochreBrownBackground = adaptiveTagColor(226, 216, 204, isBackground: true)
    static let ochreBrownForeground = adaptiveTagColor(138, 90, 42, isBackground: false)

    // MARK: - Lavender 薰衣草
    static let lavenderBackground = adaptiveTagColor(220, 213, 227, isBackground: true)
    static let lavenderForeground = adaptiveTagColor(106, 74, 154, isBackground: false)
}

extension Color {
    /// 密码库分类背景色 (低饱和度)
    enum CategoryBackground {
        static let Primary = Color("Category_Primary_Bg")
        static let Social  = Color("Category_Social_Bg")
        static let Work    = Color("Category_Work_Bg")
        static let Life    = Color("Category_Life_Bg")
        static let Finance = Color("Category_Finance_Bg")
        static let Media   = Color("Category_Media_Bg")
        
    }
    
    /// 密码库分类前景/Tint色 (高对比度)
    enum CategoryTint {
        static let Primary = Color("Category_Primary_Tint")
        static let Social  = Color("Category_Social_Tint")
        static let Work    = Color("Category_Work_Tint")
        static let Life    = Color("Category_Life_Tint")
        static let Finance = Color("Category_Finance_Tint")
        static let Media   = Color("Category_Media_Tint")
    }
}

/// 根据标签名生成一个确定性颜色（十六进制字符串），保证同名标签颜色一致
func tagColor(for name: String) -> String {
    let palette = [
        "#007AFF", "#34C759", "#FF9500", "#AF52DE",
        "#FF2D55", "#5856D6", "#30B0C7", "#8E8E93"
    ]
    let sum = name.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
}

/// 经典的 djb2 哈希算法，保证跨设备、跨启动的确定性
private func deterministicHash(for string: String) -> Int {
    var hash = 5381
    for char in string.unicodeScalars {
        // hash * 33 + char
        hash = ((hash << 5) &+ hash) &+ Int(char.value) 
    }
    return abs(hash)
}
