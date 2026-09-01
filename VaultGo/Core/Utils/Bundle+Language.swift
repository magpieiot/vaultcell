/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// Bundle+Language.swift
/// created on: 22/08/2026
/// ------------------------------------------------------------------

import Foundation
import ObjectiveC

private var _languageBundleKey: UInt8 = 0

private extension Bundle {
    /// 当前覆盖语言对应的 lproj Bundle（缓存，语言变化时自动重建）。
    var languageBundle: Bundle? {
        get { objc_getAssociatedObject(self, &_languageBundleKey) as? Bundle }
        set { objc_setAssociatedObject(self, &_languageBundleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

extension Bundle {
    /// 只安装一次的 swizzling 标记。首次访问时交换
    /// `localizedString(forKey:value:table:)` 与 `_vg_localizedString(forKey:value:table:)` 的实现。
    static let _swizzleOnce: Void = {
        let cls: AnyClass = Bundle.self
        let original = class_getInstanceMethod(cls, #selector(localizedString(forKey:value:table:)))
        let swizzled = class_getInstanceMethod(cls, #selector(_vg_localizedString(forKey:value:table:)))
        if let o = original, let s = swizzled {
            method_exchangeImplementations(o, s)
        }
    }()

    /// 交换后的本地化入口。交换完成后，调用本方法实际执行的是原始实现。
    @objc func _vg_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // 原始系统结果（交换后本方法即原始实现）
        let systemResult = _vg_localizedString(forKey: key, value: value, table: tableName)

        // 1. 跟随系统，或所选语言与系统主语言一致时，直接返回系统结果
        guard let bcp47 = AppLanguage.current.bcp47 else {
            return systemResult
        }
        if bcp47 == Bundle.main.preferredLocalizations.first {
            return systemResult
        }

        // 2. 查找覆盖语言包；lproj 缺失时回退到系统结果
        guard let overrideBundle = overrideBundle(for: bcp47) else {
            return systemResult
        }

        // 在覆盖语言包上调用原始实现（避免递归）
        let localized = overrideBundle._vg_localizedString(forKey: key, value: value, table: tableName)

        // 3. 覆盖语言包中缺失该 key 时，回退到系统结果作为安全网
        if localized == key || localized == value {
            return systemResult
        }
        return localized
    }

    /// 获取指定 BCP-47 语言对应的 lproj Bundle，带缓存。
    private func overrideBundle(for bcp47: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: bcp47, ofType: "lproj") else {
            return nil
        }
        if let cached = languageBundle, cached.bundlePath == path {
            return cached
        }
        let bundle = Bundle(path: path)
        languageBundle = bundle
        return bundle
    }
}