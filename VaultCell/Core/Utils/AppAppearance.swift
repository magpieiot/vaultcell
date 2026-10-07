/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppAppearance.swift
/// created on: 07/10/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 应用外观选择：浅色 / 深色 / 跟随系统。
///
/// 通过 `@AppStorage` 以 rawValue(Int) 持久化，并在 App 根视图上以
/// `preferredColorScheme` 生效——设置页只负责写入选择，不各自覆盖配色。
enum AppAppearance: Int, CaseIterable, Identifiable {
    /// 强制浅色
    case light = 0
    /// 强制深色
    case dark = 1
    /// 跟随系统（默认）
    case system = 2

    var id: Int { rawValue }

    /// 覆盖到视图树上的配色方案；.system 返回 nil，表示不覆盖、交由系统决定。
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// 选择器条目文案（复用已有本地化 key）
    var localizedTitle: String {
        switch self {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        case .system: return String(localized: "Follow System")
        }
    }
}
