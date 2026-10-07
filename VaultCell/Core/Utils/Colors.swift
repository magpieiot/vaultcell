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

    /// 副品牌色：蓝紫渐变结束色，用于渐变背景、次级强调。
    static let secondaryBrandColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.50, green: 0.48, blue: 0.92, alpha: 1.00) // #807AEB
            : UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.00) // #5856D6
    })

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
                UIColor(hue: hue, saturation: 0.18, brightness: 0.22, alpha: 1.0)
            } else {
                UIColor(hue: hue, saturation: 0.25, brightness: 0.94, alpha: 1.0)
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
                UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1.0)
            } else {
                UIColor(hue: hue, saturation: 0.65, brightness: 0.38, alpha: 1.0)
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
    // MARK: - Misty Blue 雾蓝
    static let mistyBlueBackground = Color(red: 213/255, green: 221/255, blue: 227/255)
    static let mistyBlueForeground = Color(red: 46/255, green: 92/255, blue: 138/255)

    // MARK: - Moss Green 苔藓绿
    static let mossGreenBackground = Color(red: 216/255, green: 222/255, blue: 208/255)
    static let mossGreenForeground = Color(red: 74/255, green: 124/255, blue: 63/255)

    // MARK: - Terracotta 陶土粉
    static let terracottaBackground = Color(red: 232/255, green: 213/255, blue: 204/255)
    static let terracottaForeground = Color(red: 184/255, green: 92/255, blue: 60/255)

    // MARK: - Twilight Gray 暮云灰
    static let twilightGrayBackground = Color(red: 222/255, green: 222/255, blue: 224/255)
    static let twilightGrayForeground = Color(red: 90/255, green: 90/255, blue: 110/255)

    // MARK: - Amber Gold 琥珀金
    static let amberGoldBackground = Color(red: 237/255, green: 224/255, blue: 204/255)
    static let amberGoldForeground = Color(red: 200/255, green: 146/255, blue: 10/255)

    // MARK: - Iris Purple 鸢尾紫
    static let irisPurpleBackground = Color(red: 221/255, green: 213/255, blue: 224/255)
    static let irisPurpleForeground = Color(red: 107/255, green: 61/255, blue: 122/255)

    // MARK: - Sea Mist 海雾青
    static let seaMistBackground = Color(red: 208/255, green: 220/255, blue: 220/255)
    static let seaMistForeground = Color(red: 42/255, green: 122/255, blue: 120/255)

    // MARK: - Rose Ash 玫瑰灰
    static let roseAshBackground = Color(red: 224/255, green: 213/255, blue: 216/255)
    static let roseAshForeground = Color(red: 168/255, green: 69/255, blue: 90/255)

    // MARK: - Olive Gold 橄榄黄
    static let oliveGoldBackground = Color(red: 224/255, green: 224/255, blue: 204/255)
    static let oliveGoldForeground = Color(red: 138/255, green: 122/255, blue: 26/255)

    // MARK: - Slate Blue 石板蓝
    static let slateBlueBackground = Color(red: 210/255, green: 214/255, blue: 220/255)
    static let slateBlueForeground = Color(red: 58/255, green: 90/255, blue: 140/255)

    // MARK: - Ochre Brown 赭石棕
    static let ochreBrownBackground = Color(red: 226/255, green: 216/255, blue: 204/255)
    static let ochreBrownForeground = Color(red: 138/255, green: 90/255, blue: 42/255)

    // MARK: - Lavender 薰衣草
    static let lavenderBackground = Color(red: 220/255, green: 213/255, blue: 227/255)
    static let lavenderForeground = Color(red: 106/255, green: 74/255, blue: 154/255)
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
