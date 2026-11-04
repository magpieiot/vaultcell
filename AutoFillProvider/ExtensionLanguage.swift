/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ExtensionLanguage.swift
/// ------------------------------------------------------------------
////
/// 扩展侧语言解析：
/// 1. 优先读取主 App 在 App Group 中持久化的"应用内语言选择"
///    （主 App AppLanguage.persist 同步写入；扩展进程读不到主 App 的
///    UserDefaults.standard，只能走共享容器）；
/// 2. 未设置覆盖时回退系统语言（扩展 Bundle 的 preferredLocalization）。
////
/// 实现机制与主 App 的 Bundle+Language 一致：运行时交换
/// `Bundle.localizedString(forKey:value:table:)`，让走该方法解析的文案启用覆盖语言。
/// 注意 `String(localized:)` 不经过该方法（Foundation 按进程语言解析），
/// 需要即时跟随覆盖语言的字符串一律用 `ExtensionLocale.string(_:)`。

import Foundation
import ObjectiveC

enum ExtensionLanguage {
    /// 与主 App VaultKey.appLanguage 一致
    private static let appLanguageKey = "vaultcell.appLanguage"

    /// 当前构建变体对应的 App Group（与主 App AppLanguage.persist 保持一致）
    private static var appGroupIdentifier: String {
        #if CN
        return "group.com.magpie.vaultcell.cn.shared"
        #else
        return "group.com.magpie.vaultcell.shared"
        #endif
    }

    /// 安装 swizzle（幂等）。在扩展任一入口最先调用。
    static func activate() {
        _ = Bundle._vcExtLanguageSwizzleOnce
    }

    /// 当前覆盖语言的 BCP-47；未设置（跟随系统）或值无法识别时为 nil
    static var overrideBCP47: String? {
        let raw = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: appLanguageKey)
        return raw.flatMap(Self.bcp47(forRawValue:))
    }

    /// 与主 App AppLanguage 的 rawValue → BCP-47 映射保持一致
    private static func bcp47(forRawValue raw: String) -> String? {
        switch raw {
        case "english": return "en"
        case "simplifiedChinese": return "zh-Hans"
        case "french": return "fr"
        case "japanese": return "ja"
        case "german": return "de"
        case "spanish": return "es"
        case "russian": return "ru"
        default: return nil // 含 followOS（跟随系统）与未知值
        }
    }
}

private var _vcExtLanguageBundleKey: UInt8 = 0

private extension Bundle {
    /// 覆盖语言对应的 lproj Bundle（缓存，语言变化时自动重建）
    var overrideLanguageBundle: Bundle? {
        get { objc_getAssociatedObject(self, &_vcExtLanguageBundleKey) as? Bundle }
        set { objc_setAssociatedObject(self, &_vcExtLanguageBundleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

extension Bundle {
    /// 只安装一次的 swizzling 标记。首次访问时交换
    /// `localizedString(forKey:value:table:)` 与 `_vcExt_localizedString(forKey:value:table:)`。
    static let _vcExtLanguageSwizzleOnce: Void = {
        let cls: AnyClass = Bundle.self
        let original = class_getInstanceMethod(cls, #selector(localizedString(forKey:value:table:)))
        let swizzled = class_getInstanceMethod(cls, #selector(_vcExt_localizedString(forKey:value:table:)))
        if let o = original, let s = swizzled {
            method_exchangeImplementations(o, s)
        }
    }()

    /// 交换后的本地化入口。交换完成后，调用本方法实际执行的是原始实现。
    @objc func _vcExt_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // 原始系统结果（交换后本方法即原始实现）
        let systemResult = _vcExt_localizedString(forKey: key, value: value, table: tableName)

        // 1. 无覆盖（跟随系统），或覆盖语言与系统主语言一致时，直接返回系统结果
        guard let bcp47 = ExtensionLanguage.overrideBCP47 else {
            return systemResult
        }
        if bcp47 == Bundle.main.preferredLocalizations.first {
            return systemResult
        }

        // 2. 查找覆盖语言包；lproj 缺失时回退到系统结果
        guard let overrideBundle = Self.vcExtOverrideBundle(for: bcp47) else {
            return systemResult
        }

        // 在覆盖语言包上调用原始实现（避免递归）
        let localized = overrideBundle._vcExt_localizedString(forKey: key, value: value, table: tableName)

        // 3. 覆盖语言包中缺失该 key 时，回退到系统结果作为安全网
        if localized == key || localized == value {
            return systemResult
        }
        return localized
    }

    /// 获取指定 BCP-47 语言对应的 lproj Bundle，带缓存
    fileprivate static func vcExtOverrideBundle(for bcp47: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: bcp47, ofType: "lproj") else {
            return nil
        }
        if let cached = Bundle.main.overrideLanguageBundle, cached.bundlePath == path {
            return cached
        }
        let bundle = Bundle(path: path)
        Bundle.main.overrideLanguageBundle = bundle
        return bundle
    }
}

/// 按扩展生效的语言解析文案的入口（主 App `AppLocale` 的扩展侧版本）。
///
/// `String(localized:)` 由 Foundation 按进程语言解析，既不经过
/// `Bundle.localizedString(forKey:value:table:)`（swizzling 拦不到），也不看 SwiftUI `\.locale`，
/// 因此必须显式指定覆盖语言对应的 lproj Bundle 才能即时跟随主 App 的语言选择。
enum ExtensionLocale {
    /// 覆盖语言缺少自己的 lproj（即覆盖语言就是 String Catalog 的源语言 en）时使用的表名。
    /// 该表不存在，Foundation 会原样返回 key —— 正是源语言文案，且占位符替换照常进行。
    private static let sourceLanguageTable = "__ExtensionLocaleSource__"

    /// 按当前生效语言解析文案；跟随系统时与 `String(localized:)` 等价。
    static func string(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
        guard let bcp47 = ExtensionLanguage.overrideBCP47 else {
            return String(localized: key, comment: comment)
        }

        let locale = Locale(identifier: bcp47)
        if let bundle = Bundle.vcExtOverrideBundle(for: bcp47) {
            return String(localized: key, table: nil, bundle: bundle, locale: locale, comment: comment)
        }

        return String(
            localized: key, table: sourceLanguageTable, bundle: .main, locale: locale,
            comment: comment)
    }
}
