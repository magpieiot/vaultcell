/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IconPreferences.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 远程图标抓取的开关与地区默认值。
///
/// 默认值只在首启落盘一次（`iconAutoFetchDefaultRegistered` 标记），之后完全尊重用户选择——
/// 否则用户手动打开开关后，下次启动又会被地区默认值覆盖回去。
///
/// 地区判定用 App Store storefront（ISO 3166-1 alpha-3，中国大陆为 `CHN`），
/// 而不是设备语言：语言是中文不代表账号在中国大陆区。storefront 取不到时同样默认关闭
/// （fail-safe：拿不准就不发请求）。

import Foundation
import StoreKit

/// 地区判定：中国大陆区默认关闭自动抓取
enum IconRegion {
    /// 当前 storefront 的三字地区码；取不到返回 nil
    static func currentCountryCode() async -> String? {
        await Storefront.current?.countryCode
    }

    /// 是否应默认关闭自动抓取
    static func shouldDefaultOff() async -> Bool {
        guard let code = await currentCountryCode()?.uppercased() else { return true }
        return code == "CHN"
    }
}

enum IconPreferences {
    /// 是否允许抓取远程网站图标
    static var isAutoFetchEnabled: Bool {
        get { UserDefaults.standard.object(forKey: VaultKey.iconAutoFetch) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: VaultKey.iconAutoFetch) }
    }

    /// 是否已看过首启的图标抓取告知（设置页之外的一次性提示）
    static var hasSeenDisclosure: Bool {
        get { UserDefaults.standard.bool(forKey: VaultKey.hasSeenIconDisclosure) }
        set { UserDefaults.standard.set(newValue, forKey: VaultKey.hasSeenIconDisclosure) }
    }

    /// 启动准备（幂等）：
    /// 1. 删除 v2 旧缓存目录（键体系已变更，旧文件不可复用）
    /// 2. 首启按地区落盘一次开关默认值
    static func prepareOnLaunch() async {
        IconStore.removeLegacyCache()

        guard !UserDefaults.standard.bool(forKey: VaultKey.iconAutoFetchDefaultRegistered) else {
            return
        }
        isAutoFetchEnabled = !(await IconRegion.shouldDefaultOff())
        UserDefaults.standard.set(true, forKey: VaultKey.iconAutoFetchDefaultRegistered)
    }

    /// 清空图标缓存与失败集合（关闭开关时**不**顺带清理，两者互不牵连）
    static func clearCache() {
        IconStore.clearAll()
    }
}
