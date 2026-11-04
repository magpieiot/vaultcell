/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppLocale.swift
/// created on: 24/10/2026
/// ------------------------------------------------------------------
///
/// 按“应用内语言选择”解析文案的入口。
///
/// 为什么需要它：`String(localized:)` 由 Foundation 直接按进程语言解析
/// （`AppleLanguages`，进程启动时缓存），既不经过
/// `Bundle.localizedString(forKey:value:table:)`（`Bundle+Language` 的 swizzling 拦不到），
/// 也不受 SwiftUI `\.locale` 环境值影响。因此切换语言后它仍返回旧语言文案，
/// 只有重启进程才会变。
///
/// 需要即时跟随语言切换、且类型必须是 `String`（导航标题、Alert、服务层错误文案等）时，
/// 统一用 `AppLocale.string(_:)`：显式指定覆盖语言对应的 lproj Bundle 解析。
///
/// 视图里的 SwiftUI 字面量（`Text("…")`）本来就走 `\.locale` 环境，
/// 只需保证视图依赖 `AppLanguageManager` 重算，不需要经过这里。
/// ------------------------------------------------------------------

import Foundation

enum AppLocale {
    /// 覆盖语言缺少自己的 lproj（即覆盖语言就是 String Catalog 的源语言 en）时使用的表名。
    /// 该表不存在，Foundation 会原样返回 key —— 正是源语言文案，且占位符替换照常进行。
    private static let sourceLanguageTable = "__AppLocaleSource__"

    /// 按当前应用内语言解析文案；跟随系统时与 `String(localized:)` 等价。
    static func string(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
        guard let bcp47 = AppLanguage.storedLanguage().bcp47 else {
            return String(localized: key, comment: comment)
        }

        let locale = Locale(identifier: bcp47)
        if let bundle = overrideBundle(for: bcp47) {
            return String(localized: key, table: nil, bundle: bundle, locale: locale, comment: comment)
        }

        return String(
            localized: key, table: sourceLanguageTable, bundle: .main, locale: locale,
            comment: comment)
    }

    /// lproj Bundle 缓存：文案解析会被列表行等高频调用，避免重复查路径
    private static let bundleCache = NSCache<NSString, Bundle>()

    private static func overrideBundle(for bcp47: String) -> Bundle? {
        let cacheKey = bcp47 as NSString
        if let cached = bundleCache.object(forKey: cacheKey) {
            return cached
        }
        guard
            let path = Bundle.main.path(forResource: bcp47, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return nil
        }
        bundleCache.setObject(bundle, forKey: cacheKey)
        return bundle
    }
}
