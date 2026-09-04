/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// LanguageBadge.swift
/// ------------------------------------------------------------------

import SwiftUI

// MARK: - AppLanguage 视觉扩展

extension AppLanguage {
    /// 徽标中展示的语言代码缩写；.followOS 不使用缩写（改用地球图标）。
    var badgeCode: String {
        switch self {
        case .followOS: return ""
        case .english: return "EN"
        case .simplifiedChinese: return "中"
        case .french: return "FR"
        case .japanese: return "日"
        case .german: return "DE"
        case .spanish: return "ES"
        case .russian: return "RU"
        }
    }

    /// 徽标浅色模式下的背景色（柔和浅色）。
    var badgeBackground: Color {
        switch self {
        case .followOS: return .primaryBrandColor
        case .english: return .mistyBlueBackground
        case .simplifiedChinese: return .terracottaBackground
        case .french: return .irisPurpleBackground
        case .japanese: return .roseAshBackground
        case .german: return .amberGoldBackground
        case .spanish: return .ochreBrownBackground
        case .russian: return .slateBlueBackground
        }
    }

    /// 徽标前景色（文字/图标）。
    var badgeForeground: Color {
        switch self {
        case .followOS: return .white
        case .english: return .mistyBlueForeground
        case .simplifiedChinese: return .terracottaForeground
        case .french: return .irisPurpleForeground
        case .japanese: return .roseAshForeground
        case .german: return .amberGoldForeground
        case .spanish: return .ochreBrownForeground
        case .russian: return .slateBlueForeground
        }
    }
}

// MARK: - 语言徽标视图

/// 语言徽标：圆角方形，内嵌语言代码缩写；“跟随系统”使用品牌渐变地球图标。
struct LanguageBadge: View {
    let language: AppLanguage
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(background)

            if language == .followOS {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundColor(.white)
            } else {
                Text(language.badgeCode)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(language.badgeForeground)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private var background: Color {
        if language == .followOS {
            return .primaryBrandColor
        }
        return language.badgeBackground
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(AppLanguage.allCases) { language in
            LanguageBadge(language: language)
        }
    }
    .padding()
}
