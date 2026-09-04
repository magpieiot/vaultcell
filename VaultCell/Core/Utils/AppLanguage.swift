/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppLanguage.swift
/// created on: 22/08/2026
/// ------------------------------------------------------------------

import Combine
import Foundation
import SwiftUI

/// 应用内语言选择。
/// 通过 UserDefaults 持久化，配合 Bundle 运行时 swizzling 实现无需重启的即时切换。
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    /// 跟随系统 — 不覆盖，回退到系统语言
    case followOS
    /// 英语 "en"
    case english
    /// 简体中文 "zh-Hans"
    case simplifiedChinese
    /// 法语 "fr"
    case french
    /// 日语 "ja"
    case japanese
    /// 德语 "de"
    case german
    /// 西班牙语 "es"
    case spanish
    /// 俄语 "ru"
    case russian

    var id: String { rawValue }

    /// BCP-47 语言代码，写入 AppleLanguages；.followOS 返回 nil 表示不覆盖。
    var bcp47: String? {
        switch self {
        case .followOS: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .french: return "fr"
        case .japanese: return "ja"
        case .german: return "de"
        case .spanish: return "es"
        case .russian: return "ru"
        }
    }

    /// 以自身文字书写的本地化名称，用于列表行主标题 / 选择器条目。
    var nativeDisplayName: String {
        switch self {
        case .followOS:
            // 跟随系统没有“自身文字”，使用当前应用语言的本地化文案
            return String(localized: "Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .french: return "Français"
        case .japanese: return "日本語"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .russian: return "Русский"
        }
    }

    /// 英文显示名称，用于列表行中本地化名称下方的次要说明。
    var englishDisplayName: String {
        switch self {
        case .followOS: return "Follow System"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .french: return "French"
        case .japanese: return "Japanese"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .russian: return "Russian"
        }
    }

    /// 解析当前应生效的语言；未设置覆盖时返回 .followOS。
    static var current: AppLanguage { storedLanguage() }

    /// 持久化并立即生效。选择 .followOS 时移除覆盖。
    @MainActor
    static func set(_ language: AppLanguage) {
        AppLanguageManager.shared.set(language)
    }

    /// 应用启动时调用：安装 Bundle swizzling。
    static func bootstrap() {
        // 确保 swizzling 只安装一次
        _ = Bundle._swizzleOnce
    }
}

extension AppLanguage {
    /// 读取已持久化的语言；不存在时返回 .followOS。
    static func storedLanguage() -> AppLanguage {
        guard
            let raw = UserDefaults.standard.string(forKey: VaultKey.appLanguage),
            let language = AppLanguage(rawValue: raw)
        else {
            return .followOS
        }
        return language
    }

    /// 持久化语言选择；.followOS 会清除覆盖项。
    static func persist(_ language: AppLanguage) {
        if language == .followOS {
            UserDefaults.standard.removeObject(forKey: VaultKey.appLanguage)
        } else {
            UserDefaults.standard.set(language.rawValue, forKey: VaultKey.appLanguage)
        }
    }

    /// 将当前选择写入 AppleLanguages，使系统在下一次启动时也使用该语言。
    static func applyAppleLanguages() {
        if let bcp47 = storedLanguage().bcp47 {
            UserDefaults.standard.set([bcp47], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// 应用语言管理器（可观察对象），用于驱动 SwiftUI 视图在语言变更时重新渲染。
/// 单例。所有视图通过环境对象读写。
@MainActor
final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()

    @Published private(set) var current: AppLanguage

    private init() {
        self.current = AppLanguage.storedLanguage()
    }

    /// 设置新语言并立即发布变更。调用后 SwiftUI 依赖本对象的视图会自动重绘。
    func set(_ language: AppLanguage) {
        AppLanguage.persist(language)
        AppLanguage.applyAppleLanguages()
        current = language
    }

    /// 重置为“跟随系统”，发布变更。
    func resetToSystem() {
        set(.followOS)
    }
}