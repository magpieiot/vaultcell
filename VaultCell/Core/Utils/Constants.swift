/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// Constants.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation

enum AppEdition {
    case global
    case china

    static let current: AppEdition = {
        #if CN
            return .china
        #else
            return .global
        #endif
    }()

    static var isChina: Bool { current == .china }
    static var isGlobal: Bool { current == .global }

    static func fromBundleID() -> AppEdition {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.hasSuffix(".cn") ? .china : .global
    }
}

enum AppStore {
    /// App Store 应用 ID（上架后替换为真实 ID）
    static let appID = "0000000000"

    /// 打开 App Store 写评论页面。
    /// 占位 ID（0000000000）未替换时返回 nil，避免拼出 id0000000000 的坏链接。
    static var writeReviewURL: URL? {
        guard Int(appID) ?? 0 > 0, appID.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")
    }

    /// App ID 是否已是上架后的真实 ID（占位符时为 false）
    static var hasRealAppID: Bool { writeReviewURL != nil }
}

/// 法律条款与支持资源
///
/// App 内展示的始终是**本地完整内容**（`LegalContent`），离线可读；
/// 下面的线上地址只决定文档页底部是否多出一个"线上版本"入口。
/// App Store Connect 的隐私政策 URL 填 `privacyPolicyURL` 同一地址。
///
/// 官网（www.magpieai.app）尚未上线前，线上文档托管在 GitHub Pages：
/// 仓库 magpieiot/vaultcell_web（main 分支根目录），必须保持 public。
enum Legal {
    /// 隐私政策线上地址
    static let privacyPolicyURL: URL? =
        URL(string: "https://magpieiot.github.io/vaultcell_web/privacy.html")
    /// 服务条款线上地址
    static let termsOfServiceURL: URL? =
        URL(string: "https://magpieiot.github.io/vaultcell_web/terms.html")
    /// 在线帮助中心地址（官网就绪前留空，App 内帮助页已自足）
    static let helpCenterURL: URL? = nil

    /// 支持邮箱：同时用于 App 内"Email support"入口与审核备注联系人
    static let supportEmail = "magpieiot@gmail.com"

    /// 支持邮箱可点击时才有值（未配置 / 仍是占位文案时不显示任何 mailto 入口）
    static var supportEmailURL: URL? {
        let mail = supportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mail.contains("@"), !mail.hasPrefix("(") else { return nil }
        return URL(string: "mailto:\(mail)")
    }
}

enum VaultKey {
    static let salt = "vaultcell.salt"
    static let encryptedMasterKey = "vaultcell.encryptedMasterKey"
    static let biometricDek = "vaultcell.biometricDek"
    static let hasVault = "vaultcell.hasVault"
    static let vaultInstalledMarker = "vaultcell.vaultInstalledMarker"
    static let vaultID = "vaultcell.vaultID"
    static let cloudKeyRevision = "vaultcell.cloudKeyRevision"
    static let iCloudSyncEnabled = "vaultcell.iCloudSyncEnabled"
    static let pendingCloudRestoreDownload = "vaultcell.pendingCloudRestoreDownload"
    /// 主密码解锁失败限流状态（存 Keychain，keychainService 的 account 名）
    static let unlockThrottle = "vaultcell.unlockThrottle"
    static let settings = "vaultcell.settings"
    static let biometricEnabled = "vaultcell.biometricEnabled"
    static let autoLockInterval = "vaultcell.autoLockInterval"
    static let clipboardTimeout = "vaultcell.clipboardTimeout"
    /// 是否允许在 VaultList 页面左滑条目显示 Delete 按钮（默认开启）
    static let allowSwipeDeleteInVaultList = "vaultcell.allowSwipeDeleteInVaultList"
    static let recentEmails = "vaultcell.recentEmails"
    static let recentPhoneNumbers = "vaultcell.recentPhoneNumbers"
    static let recentTags = "vaultcell.recentTags"
    static let searchHistory = "vaultcell.searchHistory"
    static let hasCompletedOnboarding = "vaultcell.hasCompletedOnboarding"
    /// 是否已展示过首次运行的欢迎启动屏（1#），仅展示一次
    static let hasSeenWelcomeSplash = "vaultcell.hasSeenWelcomeSplash"
    /// 是否已看过"密码库就绪"首次填充引导页（一次性决策点标记）
    static let hasSeenVaultSetupGuide = "vaultcell.hasSeenVaultSetupGuide"
    static let appLanguage = "vaultcell.appLanguage"
    /// 主 App 已消费过的「扩展保存密码」时间戳（对应 App Group 中的 AutoFillSharedKeys.savedCredentialAt）
    static let consumedAutoFillSaveAt = "vaultcell.consumedAutoFillSaveAt"
    /// 是否允许抓取远程网站图标（默认值按 App Store 地区决定，首启落盘一次）
    static let iconAutoFetch = "vaultcell.iconAutoFetch"
    /// 地区默认值是否已落盘（只写一次，之后完全尊重用户在设置页的选择）
    static let iconAutoFetchDefaultRegistered = "vaultcell.iconAutoFetchDefaultRegistered"
    /// 是否已看过首启的"网站图标抓取"告知
    static let hasSeenIconDisclosure = "vaultcell.hasSeenIconDisclosure"
    /// 是否在安全评分的"为何被扣分"中展示"已泄露的条目"分类（默认关闭）
    /// 泄露检测尚未上线，该类条目不影响评分，默认不占用扣分清单的位置。
    static let showCompromisedInScoreReasons = "vaultcell.showCompromisedInScoreReasons"
    /// 外观模式：AppAppearance 的 rawValue（0 浅色 / 1 深色 / 2 跟随系统）
    static let appearanceMode = "vaultcell.appearanceMode"
    /// 收藏条目是否置顶显示（默认开启，用户关闭后以落盘值为准）
    static let pinFavoritesToTop = "vaultcell.pinFavoritesToTop"
}

struct AppTitle {
    let icon: String
    let title: String
    let url: String
    let categoryID: UUID?
}

let famousApps: [AppTitle] = [
    // Primary：主账号
    AppTitle(
        icon: "Apple", title: "Apple", url: "https://www.apple.com/",
        categoryID: PasswordCategory.systemDefaults[0].id),
    AppTitle(
        icon: "Google", title: "Google", url: "https://www.google.com/",
        categoryID: PasswordCategory.systemDefaults[0].id),
    AppTitle(
        icon: "Microsoft", title: "Microsoft", url: "https://www.microsoft.com/",
        categoryID: PasswordCategory.systemDefaults[0].id),
    // Work：办公协作
    AppTitle(
        icon: "Chatgpt", title: "Chatgpt", url: "https://www.chatgpt.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "Claude", title: "Claude", url: "https://www.claudeai.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "GitHub", title: "GitHub", url: "https://www.github.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "LinkedIn", title: "LinkedIn", url: "https://www.linkedin.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "Notion", title: "Notion", url: "https://www.notionapp.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "Slack", title: "Slack", url: "https://www.slack.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "Webex", title: "Webex", url: "https://www.webex.com/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    AppTitle(
        icon: "Zoom", title: "Zoom", url: "https://www.zoom.us/",
        categoryID: PasswordCategory.systemDefaults[3].id),
    // Life：生活社交
    AppTitle(
        icon: "Airbnb", title: "Airbnb", url: "https://www.airbnb.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Amazon", title: "Amazon", url: "https://www.amazon.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Discord", title: "Discord", url: "https://www.discord.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Duolingo", title: "Duolingo", url: "https://www.duolingo.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Facebook", title: "Facebook", url: "https://www.facebook.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Instagram", title: "Instagram", url: "https://www.instagram.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Line", title: "Line", url: "https://www.line.me/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Pinterest", title: "Pinterest", url: "https://www.pinterest.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Reddit", title: "Reddit", url: "https://www.reddit.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Telegram", title: "Telegram", url: "https://www.telegram.org/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "TikTok", title: "TikTok", url: "https://www.tiktok.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "WhatsApp", title: "WhatsApp", url: "https://www.whatsapp.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Wikipedia", title: "Wikipedia", url: "https://www.wikipedia.org/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "X", title: "X", url: "https://www.x.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Yelp", title: "Yelp", url: "https://www.yelp.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    // Media：影音娱乐
    AppTitle(
        icon: "Disney", title: "Disney", url: "https://www.disneyplus.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
    AppTitle(
        icon: "Netflix", title: "Netflix", url: "https://www.netflix.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
    AppTitle(
        icon: "Spotify", title: "Spotify", url: "https://www.spotify.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
    AppTitle(
        icon: "YouTube", title: "YouTube", url: "https://www.youtube.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
]

/// 中国版常用应用（图标来自 Assets.xcassets/ChinaAppIcon）
let famousAppsCn: [AppTitle] = [
    // Primary：主账号
    AppTitle(
        icon: "Xiaomi", title: "小米", url: "https://www.mi.com/",
        categoryID: PasswordCategory.systemDefaults[0].id),
    AppTitle(
        icon: "Baidu", title: "百度", url: "https://www.baidu.com/",
        categoryID: PasswordCategory.systemDefaults[0].id),
    // Finance：金融财务
    AppTitle(
        icon: "Alipay", title: "支付宝", url: "https://www.alipay.com/",
        categoryID: PasswordCategory.systemDefaults[2].id),
    // Life：生活社交
    AppTitle(
        icon: "Wechat", title: "微信", url: "https://weixin.qq.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Weibo", title: "微博", url: "https://www.weibo.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Taobao", title: "淘宝", url: "https://www.taobao.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Tmall", title: "天猫", url: "https://www.tmall.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Jd", title: "京东", url: "https://www.jd.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Meituan", title: "美团", url: "https://www.meituan.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Ctrip", title: "携程", url: "https://www.ctrip.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Xiaohongshu", title: "小红书", url: "https://www.xiaohongshu.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    AppTitle(
        icon: "Zhihu", title: "知乎", url: "https://www.zhihu.com/",
        categoryID: PasswordCategory.systemDefaults[4].id),
    // Media：影音娱乐
    AppTitle(
        icon: "Bilibili", title: "哔哩哔哩", url: "https://www.bilibili.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
    AppTitle(
        icon: "Iqiyi", title: "爱奇艺", url: "https://www.iqiyi.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
    AppTitle(
        icon: "Kuaishou", title: "快手", url: "https://www.kuaishou.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
    AppTitle(
        icon: "Neteasecloud", title: "网易云音乐", url: "https://music.163.com/",
        categoryID: PasswordCategory.systemDefaults[5].id),
]

let oauthProviders: [String] = [
    "Amazon",
    "Apple",
    "Box",
    "Discord",
    "Facebook",
    "Github",
    "Google",
    "Instagram",
    "LinkedIn",
    "Microsoft",
    "PayPal",
    "Reddit",
    "Salesforce",
    "Spotify",
    "TikTok",
    "Twitch",
    "X",
    "Yelp",
]

extension UserDefaults {
    static var autoLockInterval: Double {
        get {
            if let value = standard.object(forKey: VaultKey.autoLockInterval) as? Double {
                return value
            }
            if let value = standard.object(forKey: "autoLockInterval") as? Double {
                return value
            }
            return 30
        }
        set {
            standard.set(newValue, forKey: VaultKey.autoLockInterval)
            standard.set(newValue, forKey: "autoLockInterval")
        }
    }

    static var clipboardTimeout: Double {
        get {
            if let value = standard.object(forKey: VaultKey.clipboardTimeout) as? Double {
                return value
            }
            if let value = standard.object(forKey: "clipboardTimeout") as? Double {
                return value
            }
            return 60
        }
        set {
            standard.set(newValue, forKey: VaultKey.clipboardTimeout)
            standard.set(newValue, forKey: "clipboardTimeout")
        }
    }

    static var isBiometricEnabled: Bool {
        get {
            if let value = standard.object(forKey: VaultKey.biometricEnabled) as? Bool {
                return value
            }
            if let value = standard.object(forKey: "biometricEnabled") as? Bool {
                return value
            }
            return true
        }
        set {
            standard.set(newValue, forKey: VaultKey.biometricEnabled)
            standard.set(newValue, forKey: "biometricEnabled")
        }
    }

    /// 是否允许在 VaultList 页面左滑条目显示 Delete 按钮（默认开启）
    static var isSwipeDeleteInVaultListEnabled: Bool {
        get {
            if let value = standard.object(forKey: VaultKey.allowSwipeDeleteInVaultList) as? Bool {
                return value
            }
            return true
        }
        set {
            standard.set(newValue, forKey: VaultKey.allowSwipeDeleteInVaultList)
        }
    }

    /// 是否已完成 Onboarding 引导（首次启动后置为 true）
    static var hasCompletedOnboarding: Bool {
        get {
            standard.bool(forKey: VaultKey.hasCompletedOnboarding)
        }
        set {
            standard.set(newValue, forKey: VaultKey.hasCompletedOnboarding)
        }
    }

    /// 是否已看过"密码库就绪"引导页（跳过 / 首个条目保存 / 导入完成后置为 true）
    static var hasSeenVaultSetupGuide: Bool {
        get {
            standard.bool(forKey: VaultKey.hasSeenVaultSetupGuide)
        }
        set {
            standard.set(newValue, forKey: VaultKey.hasSeenVaultSetupGuide)
        }
    }

    /// 是否已展示过首次运行的欢迎启动屏（1#），淡出完成后置为 true
    static var hasSeenWelcomeSplash: Bool {
        get {
            standard.bool(forKey: VaultKey.hasSeenWelcomeSplash)
        }
        set {
            standard.set(newValue, forKey: VaultKey.hasSeenWelcomeSplash)
        }
    }
}

/// 用户联系存储
struct UserContactStore {
    static let maxItems = 8

    static func recentEmails() -> [String] {
        UserDefaults.standard.stringArray(forKey: VaultKey.recentEmails) ?? []
    }

    static func recentPhoneNumbers() -> [String] {
        UserDefaults.standard.stringArray(forKey: VaultKey.recentPhoneNumbers) ?? []
    }

    static func addEmail(_ value: String?) {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list = recentEmails()
        list.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }
        UserDefaults.standard.set(list, forKey: VaultKey.recentEmails)
    }

    static func addPhoneNumber(_ value: String?) {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list = recentPhoneNumbers()
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }
        UserDefaults.standard.set(list, forKey: VaultKey.recentPhoneNumbers)
    }

    /// 从密码库条目中同步邮箱和手机号到最近联系列表
    /// 每次加载密码库时调用，确保最近联系列表反映当前密码库中的联络信息
    static func syncFromPasswordEntries(_ entries: [PasswordEntry]) {
        for entry in entries {
            addEmail(entry.bundleEmailAddress)
            addPhoneNumber(entry.bundlePhoneNumber)
        }
    }
}

/// 标签存储：持久化用户最近使用过的标签，供录入时选择
struct TagStore {
    static let maxItems = 20

    static func recentTags() -> [String] {
        UserDefaults.standard.stringArray(forKey: VaultKey.recentTags) ?? []
    }

    /// 批量添加标签（去重、按最近使用排序）
    static func addTags(_ tags: [String]) {
        let cleaned =
            tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }

        var list = recentTags()
        for tag in cleaned {
            list.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
            list.insert(tag, at: 0)
        }
        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }
        UserDefaults.standard.set(list, forKey: VaultKey.recentTags)
    }
}
