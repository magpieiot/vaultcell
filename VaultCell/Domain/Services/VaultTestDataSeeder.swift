/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultTestDataSeeder.swift
/// created on: 23/09/2026
/// ------------------------------------------------------------------

import Foundation

#if DEBUG
/// 测试库种子数据构造
///
/// 原本写在设置页里，随工具中心改造抽出来：这一块有三百多行纯数据构造，
/// 混在页面代码里会让页面无法阅读。
/// 上架包不包含该功能：整个文件以 `#if DEBUG` 隔离，Release / Release-CN 不编译，
/// 包内也就没有测试数据入口（避免审核判定为半成品，也避免污染用户密码库）。
enum VaultTestDataSeeder {

    /// 种子条目标记：写入备注，用于判断测试库是否已经生成过
    static let seedNotesMarker = "[VaultCell Seed]"

    // MARK: - 手机号

    /// 测试库固定使用的 3 个手机号
    ///
    /// 真实用户不会给每个账号各绑一个号。之前种子数据里铺了十个不同的号码，
    /// "身份复用"报告看起来像人工造的。现在只留主号 / 备用号 / 旧号三个，
    /// 交叉分配给不同分类的条目：既贴近真实，也保留"同一号码被多个站点复用"的可测场景。
    private enum SeedPhone {
        /// 主号：微信、微博、京东等日常账号
        static let primary = "+8613800009999"
        /// 备用号：支付宝、12306、企业微信、淘宝等
        static let backup = "+8613800008888"
        /// 旧号：Google、Amazon、携程、QQ 等早期注册的老账号
        static let legacy = "+8613800001234"
    }

    // MARK: - 邮箱

    /// 测试库固定使用的 3 个邮箱：工作邮箱 / 生活邮箱 / 备用邮箱
    ///
    /// 和手机号同理：真实用户注册几十个站点也只会用两三个邮箱。
    /// 之前几乎每条一个邮箱，身份复用报告里每个邮箱都只出现一次，测不出东西。
    private enum SeedEmail {
        /// 工作邮箱：企业账号、办公协作、差旅
        static let work = "gavan.work@example.com"
        /// 生活邮箱：Apple ID、Google 主账号等个人主邮箱
        static let life = "gavan.life@example.com"
        /// 备用邮箱：购物、论坛、娱乐和早期注册的老账号
        static let backup = "gavan.backup@example.com"
    }

    // MARK: - 是否已生成

    /// 是否已经生成过测试库
    ///
    /// `alreadyGenerated` 由调用方传入（`SettingsViewModel.isSeedTestVaultGenerated()`）：
    /// 那个标记读写 UserDefaults，属于主线程状态，放在本文件的非隔离静态方法里调用不了。
    static func hasSeededTestVault(passwords: [PasswordEntry], alreadyGenerated: Bool) -> Bool {
        if alreadyGenerated {
            return true
        }
        return passwords.contains { entry in
            (entry.notes?.contains(seedNotesMarker) ?? false)
                || (entry.tags?.contains("seed") ?? false)
        }
    }

    // MARK: - 密码条目

    static func makeSeedEntries() -> [PasswordEntry] {
        let now = Date()
        //let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        let ninetyDaysInterval: TimeInterval = 90 * 24 * 60 * 60
        let ninetyDaysAgo = now.addingTimeInterval(-ninetyDaysInterval)
        let oneYearAgo = now.addingTimeInterval(-365 * 24 * 60 * 60)
        let threeMonthsAgo = ninetyDaysAgo

        let entries: [PasswordEntry] = [
            seedEntry(
                siteName: "Apple",
                siteURL: "https://appleid.apple.com",
                username: SeedEmail.life,
                password: "Apple@2026#Secure!",
                bundleEmailAddress: SeedEmail.life,
                notes: "Apple ID 主账号，用于 App Store、iCloud、iMessage",
                categoryID: PasswordCategory.systemDefaults[0].id,  // Primary
                tags: ["apple", "id", "icloud"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Apple", boundValue: SeedEmail.life),
                    TwoFactorConfig(type: .push, issuer: "Apple", boundValue: "iPhone 15 Pro"),
                ],
                passwordHistory: [
                    PasswordHistoryEntry(password: "Apple@2025#Pass", changedAt: threeMonthsAgo),
                    PasswordHistoryEntry(password: "Apple@2024#Old", changedAt: oneYearAgo),
                ],
                passwordChangedAt: threeMonthsAgo,
                customFields: [
                    CustomField(name: "安全问题答案", value: "我的第一只宠物叫旺财", isSensitive: true),
                    CustomField(name: "注册时间", value: "2018-06-15", isSensitive: false),
                ],
                version: 3,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-365 * 24 * 60 * 60),
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-24 * 60 * 60)
            ),

            seedEntry(
                siteName: "Google",
                siteURL: "https://accounts.google.com",
                username: SeedEmail.life,
                password: "Google!2026@Complex",
                bundlePhoneNumber: SeedPhone.legacy,
                bundleEmailAddress: SeedEmail.life,
                notes: "个人主邮箱，已开启高级保护计划，禁止第三方应用访问",
                categoryID: PasswordCategory.systemDefaults[0].id,  // Primary
                tags: ["google", "mail", "advanced-protection"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Google", boundValue: SeedEmail.life),
                    TwoFactorConfig(type: .hardware, issuer: "YubiKey", boundValue: "YubiKey 5C"),
                ],
                passwordHistory: [
                    PasswordHistoryEntry(password: "Google2025!Pass", changedAt: threeMonthsAgo)
                ],
                passwordChangedAt: threeMonthsAgo,
                customFields: [
                    CustomField(name: "恢复邮箱", value: SeedEmail.backup, isSensitive: true)
                ],
                version: 2,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-730 * 24 * 60 * 60),
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-12 * 60 * 60)
            ),

            seedEntry(
                siteName: "GitHub",
                siteURL: "https://github.com",
                username: SeedEmail.work,
                password: "GitHub#2026!DevPass",
                bundleEmailAddress: SeedEmail.work,
                notes: "公司代码托管，已配置 SSH Key 和 GPG 签名",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Work
                tags: ["dev", "code", "git"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "GitHub", boundValue: SeedEmail.work)
                ],
                passwordHistory: [
                    PasswordHistoryEntry(password: "GitHub2025#Old", changedAt: oneYearAgo),
                    PasswordHistoryEntry(
                        password: "GitHub2024#VeryOld",
                        changedAt: oneYearAgo.addingTimeInterval(-365 * 24 * 60 * 60)),
                ],
                passwordChangedAt: oneYearAgo,
                customFields: [
                    CustomField(name: "SSH Key 指纹", value: "SHA256:abc123...", isSensitive: false),
                    CustomField(name: "GPG Key ID", value: "0x1234ABCD", isSensitive: false),
                ],
                version: 3,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-1095 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-6 * 60 * 60)
            ),

            seedEntry(
                siteName: "Microsoft",
                siteURL: "https://login.microsoftonline.com",
                username: SeedEmail.work,
                password: "Microsoft@2026!Work",
                bundleEmailAddress: SeedEmail.work,
                notes: "企业 Office 365 账号，包含 Outlook、Teams、SharePoint",
                categoryID: PasswordCategory.systemDefaults[0].id,  // Primary
                tags: ["work", "office", "microsoft"],
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Microsoft", boundValue: SeedEmail.work)
                ],
                customFields: [CustomField(name: "部门", value: "研发部", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: threeMonthsAgo,
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-2 * 60 * 60)
            ),

            seedEntry(
                siteName: "微信",
                siteURL: "https://weixin.qq.com",
                username: SeedPhone.primary,
                password: "WeChat@2026#Secure",
                bundlePhoneNumber: SeedPhone.primary,
                notes: "已实名认证，绑定银行卡、零钱通、微信支付",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["message", "payment", "wechat"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.primary)],
                passwordHistory: [
                    PasswordHistoryEntry(password: "WeChat2025#Old", changedAt: ninetyDaysAgo)
                ],
                passwordChangedAt: ninetyDaysAgo,
                customFields: [
                    CustomField(name: "微信号", value: "wx_12345678", isSensitive: false),
                    CustomField(name: "绑定银行卡尾号", value: "****1234", isSensitive: true),
                ],
                version: 2,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-730 * 24 * 60 * 60),
                updatedAt: ninetyDaysAgo,
                lastUsedAt: now.addingTimeInterval(-30 * 60)
            ),

            seedEntry(
                siteName: "支付宝",
                siteURL: "https://alipay.com",
                username: SeedPhone.backup,
                password: "Alipay@2026#Money",
                bundlePhoneNumber: SeedPhone.backup,
                bundleEmailAddress: SeedEmail.life,
                notes: "余额宝 + 基金定投 + 蚂蚁花呗，需定期修改支付密码",
                categoryID: PasswordCategory.systemDefaults[2].id,  // Finance
                tags: ["payment", "bank", "alipay"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(type: .sms, boundValue: SeedPhone.backup),
                    TwoFactorConfig(
                        type: .totp, issuer: "Alipay", boundValue: SeedEmail.life),
                ],
                passwordHistory: [
                    PasswordHistoryEntry(password: "Alipay2025#Old", changedAt: ninetyDaysAgo)
                ],
                passwordChangedAt: ninetyDaysAgo,
                customFields: [
                    CustomField(name: "余额宝余额", value: "¥12,345.67", isSensitive: true),
                    CustomField(name: "花呗额度", value: "¥20,000", isSensitive: true),
                ],
                version: 2,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                //expiresAt: now.addingTimeInterval(ninetyDaysInterval),
                createdAt: oneYearAgo.addingTimeInterval(-365 * 24 * 60 * 60),
                updatedAt: ninetyDaysAgo,
                lastUsedAt: now.addingTimeInterval(-1 * 60 * 60)
            ),

            seedEntry(
                siteName: "Amazon",
                siteURL: "https://amazon.com",
                username: SeedEmail.backup,
                password: "Amazon#2026!Shop",
                bundlePhoneNumber: SeedPhone.legacy,
                notes: "Prime 会员，绑定招行 Visa 卡，自动续费",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["shopping", "prime", "amazon"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.legacy)],
                customFields: [
                    CustomField(name: "会员到期时间", value: "2027-06-17", isSensitive: false)
                ],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo,
                //expiresAt: now.addingTimeInterval(thirtyDaysInterval),
                lastUsedAt: now.addingTimeInterval(-48 * 60 * 60)
            ),

            seedEntry(
                siteName: "Netflix",
                siteURL: "https://netflix.com",
                username: SeedEmail.life,
                password: "Netflix@2026!TV",
                bundleEmailAddress: SeedEmail.life,
                notes: "4K 高级套餐，5 人共享，家庭计划",
                categoryID: PasswordCategory.systemDefaults[5].id,  // Media
                tags: ["streaming", "movie", "netflix"],
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(type: .email, boundValue: SeedEmail.life)
                ],
                customFields: [CustomField(name: "共享人数", value: "5人", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                //expiresAt: now.addingTimeInterval(ninetyDaysInterval),
                createdAt: threeMonthsAgo,
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-8 * 60 * 60)
            ),

            seedEntry(
                siteName: "微博",
                siteURL: "https://weibo.com",
                username: SeedEmail.life,
                password: "Weibo@2026!Hot",
                bundlePhoneNumber: SeedPhone.primary,
                notes: "实名认证账号，粉丝数 1.2 万",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["social", "weibo", "china"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.primary)],
                customFields: [CustomField(name: "粉丝数", value: "12,000", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: true,
                breachStatus: .compromised,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-730 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-24 * 60 * 60)
            ),

            seedEntry(
                siteName: "知乎",
                siteURL: "https://zhihu.com",
                username: SeedEmail.backup,
                password: "Zhihu@2026!Q&A",
                bundleEmailAddress: SeedEmail.backup,
                notes: "盐选会员，累计回答 50+，获赞 2 万",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["qa", "knowledge", "zhihu"],
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Zhihu", boundValue: SeedEmail.backup)
                ],
                customFields: [CustomField(name: "获赞数", value: "20,000", isSensitive: false)],
                version: 1,
                isSynced: false,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                createdAt: oneYearAgo,
                updatedAt: now,
                lastUsedAt: now.addingTimeInterval(-2 * 60 * 60)
            ),

            seedEntry(
                siteName: "豆瓣",
                siteURL: "https://douban.com",
                username: SeedEmail.backup,
                password: "Douban@2026!Book",
                bundleEmailAddress: SeedEmail.backup,
                notes: "书影音爱好者，已标记 500+ 书籍",
                categoryID: PasswordCategory.systemDefaults[5].id,  // Media
                tags: ["book", "movie", "music", "douban"],
                customFields: [CustomField(name: "读过书籍", value: "520本", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .inactive,
                createdAt: oneYearAgo.addingTimeInterval(-1095 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-30 * 24 * 60 * 60)
            ),

            seedEntry(
                siteName: "携程",
                siteURL: "https://ctrip.com",
                username: SeedEmail.work,
                password: "Ctrip@2026!Trip",
                bundlePhoneNumber: SeedPhone.legacy,
                notes: "黄金会员，积分 5 万，绑定企业差旅",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["travel", "hotel", "flight"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.legacy)],
                customFields: [CustomField(name: "积分", value: "50,000", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-7 * 24 * 60 * 60)
            ),

            seedEntry(
                siteName: "12306",
                siteURL: "https://12306.cn",
                username: SeedEmail.life,
                password: "12306@2026!Train",
                bundlePhoneNumber: SeedPhone.backup,
                notes: "已实名认证，常用联系人 5 人",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["train", "china", "travel"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.backup)],
                customFields: [CustomField(name: "常用联系人", value: "5人", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-365 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-14 * 24 * 60 * 60)
            ),

            seedEntry(
                siteName: "QQ",
                siteURL: "https://im.qq.com",
                username: "123456789",
                password: "QQ@2026!Old",
                bundlePhoneNumber: SeedPhone.legacy,
                notes: "注册多年的老账号，已绑定微信",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["message", "qq", "tencent"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.legacy)],
                customFields: [CustomField(name: "QQ等级", value: "48级", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .inactive,
                createdAt: oneYearAgo.addingTimeInterval(-2190 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-90 * 24 * 60 * 60)
            ),

            seedEntry(
                siteName: "钉钉",
                siteURL: "https://dingtalk.com",
                username: SeedEmail.work,
                password: "DingTalk@2026!Work",
                bundleEmailAddress: SeedEmail.work,
                notes: "公司内部沟通工具，已加入 3 个企业",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Work
                tags: ["work", "team", "dingtalk"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.primary)],
                customFields: [CustomField(name: "所属企业", value: "科技有限公司", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: threeMonthsAgo,
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-30 * 60)
            ),

            seedEntry(
                siteName: "企业微信",
                siteURL: "https://work.weixin.qq.com",
                username: SeedEmail.work,
                password: "WorkWeChat@2026!",
                bundlePhoneNumber: SeedPhone.backup,
                notes: "企业内部账号，用于审批、会议、文档协作",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Work
                tags: ["work", "enterprise", "wechat"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.backup)],
                customFields: [CustomField(name: "部门", value: "技术部", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: threeMonthsAgo,
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-1 * 60 * 60)
            ),

            seedEntry(
                siteName: "京东",
                siteURL: "https://jd.com",
                username: SeedEmail.backup,
                password: "JD@2026!Shop",
                bundlePhoneNumber: SeedPhone.primary,
                notes: "Plus 会员，绑定京东白条",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["shopping", "jd", "china"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.primary)],
                customFields: [CustomField(name: "白条额度", value: "¥10,000", isSensitive: true)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                //expiresAt: now.addingTimeInterval(thirtyDays),
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-24 * 60 * 60)
            ),

            seedEntry(
                siteName: "淘宝",
                siteURL: "https://taobao.com",
                username: SeedEmail.life,
                password: "Taobao@2026!Buy",
                bundlePhoneNumber: SeedPhone.backup,
                notes: "淘宝达人，淘气值 2000+，绑定花呗",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["shopping", "taobao", "alipay"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.backup)],
                customFields: [CustomField(name: "淘气值", value: "2150", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-365 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-12 * 60 * 60)
            ),

            seedEntry(
                siteName: "抖音",
                siteURL: "https://douyin.com",
                username: SeedEmail.backup,
                password: "Douyin@2026!Video",
                bundlePhoneNumber: SeedPhone.primary,
                notes: "创作者账号，粉丝 5 万，开通直播权限",
                categoryID: PasswordCategory.systemDefaults[5].id,  // Media
                tags: ["video", "shortvideo", "douyin"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.primary)],
                customFields: [CustomField(name: "粉丝数", value: "50,000", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                createdAt: threeMonthsAgo,
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-6 * 60)
            ),

            seedEntry(
                siteName: "小红书",
                siteURL: "https://xiaohongshu.com",
                username: SeedEmail.backup,
                password: "XiaoHongShu@2026!",
                bundleEmailAddress: SeedEmail.backup,
                notes: "美妆博主，粉丝 3 万，笔记获赞 10 万",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["social", "beauty", "china"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: SeedPhone.legacy)],
                customFields: [CustomField(name: "粉丝数", value: "30,000", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .unknown,
                accountStatus: .active,
                createdAt: threeMonthsAgo,
                updatedAt: threeMonthsAgo,
                lastUsedAt: now.addingTimeInterval(-4 * 60 * 60)
            ),

            seedEntry(
                siteName: "Slack",
                siteURL: "https://slack.com",
                username: SeedEmail.work,
                password: "Slack@2026!Team",
                bundleEmailAddress: SeedEmail.work,
                notes: "团队协作工具，已加入 5 个频道，每日活跃。通过 Google 账户登录",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Work
                tags: ["team", "work", "slack"],
                oAuthProvider: OAuthProviderConfig(
                    provider: "google", boundValue: SeedEmail.life),
                customFields: [CustomField(name: "所属团队", value: "VaultCell", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-30 * 60)
            ),

            seedEntry(
                siteName: "Notion",
                siteURL: "https://notion.so",
                username: SeedEmail.work,
                password: "Notion@2026!Docs",
                bundleEmailAddress: SeedEmail.work,
                notes: "个人知识库，包含 100+ 页面，多个数据库。通过 Apple 账户登录",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Work
                tags: ["notes", "docs", "productivity"],
                oAuthProvider: OAuthProviderConfig(
                    provider: "apple", boundValue: SeedEmail.life),
                customFields: [CustomField(name: "页面数", value: "127", isSensitive: false)],
                version: 1,
                isSynced: true,
                isDuplicatePassword: false,
                breachStatus: .safe,
                accountStatus: .active,
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-3 * 60 * 60)
            ),

            // MARK: 简单密码条目
            // 下面几条故意使用简单密码，覆盖弱密码提示、密码复用（「123456」出现两次）、
            // 未开 2FA、已停用账号等场景。不要为了好看把它们改成强密码——
            // 那正是这几条的测试价值所在。
            seedEntry(
                siteName: "旅行论坛",
                siteURL: "https://bbs.travel-example.com",
                username: SeedEmail.backup,
                password: "123456",
                bundleEmailAddress: SeedEmail.backup,
                notes: "简单密码：注册时图省事设的纯数字密码，用于验证弱密码提示",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["forum", "travel", "seed"],
                isDuplicatePassword: true,
                breachStatus: .compromised,
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-365 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-20 * 24 * 60 * 60)
            ),

            seedEntry(
                siteName: "健身房约课",
                siteURL: "https://gym.example.com",
                username: SeedEmail.life,
                password: "123456",
                bundlePhoneNumber: SeedPhone.legacy,
                notes: "简单密码：和「旅行论坛」同一个密码，用于验证密码复用检测",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["gym", "life", "seed"],
                isDuplicatePassword: true,
                accountStatus: .active,
                createdAt: threeMonthsAgo,
                updatedAt: now,
                lastUsedAt: now.addingTimeInterval(-3 * 24 * 60 * 60)
            ),

            seedEntry(
                siteName: "家用路由器",
                siteURL: "http://192.168.1.1",
                username: "admin",
                password: "admin123",
                notes: "简单密码：后台默认口令一直没改，用于验证弱密码 + 未开 2FA 的扣分",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["router", "home", "seed"],
                accountStatus: .active,
                createdAt: oneYearAgo.addingTimeInterval(-1095 * 24 * 60 * 60),
                updatedAt: oneYearAgo
            ),

            seedEntry(
                siteName: "旧版论坛",
                siteURL: "https://old-forum.example.com",
                username: SeedEmail.backup,
                password: "qwerty123",
                bundleEmailAddress: SeedEmail.backup,
                notes: "简单密码：已停用的老账号，密码是键盘顺序，用于验证停用账号的弱密码评分",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Life
                tags: ["forum", "legacy", "seed"],
                breachStatus: .compromised,
                accountStatus: .inactive,
                createdAt: oneYearAgo.addingTimeInterval(-2190 * 24 * 60 * 60),
                updatedAt: oneYearAgo,
                lastUsedAt: now.addingTimeInterval(-400 * 24 * 60 * 60)
            ),
        ]

        return augmentSeedEntries(entries, minimumCount: 40, now: now)
    }

    // MARK: - PIN 种子

    static func makeSeedPincodes() -> [PincodeEntry] {
        let now = Date()
        let oneYearAgo = now.addingTimeInterval(-365 * 24 * 60 * 60)

        return [
            PincodeEntry(
                title: "Phone Lock PIN",
                pincode: "1234",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 手机锁屏 PIN",
                categoryID: PasswordCategory.systemDefaults[0].id,
                tags: ["device", "seed"],
                isFavorite: true,
                createdAt: oneYearAgo,
                updatedAt: now.addingTimeInterval(-7 * 24 * 60 * 60)
            ),
            PincodeEntry(
                title: "ATM PIN - ICBC",
                pincode: "918273",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 工商银行 ATM 取款密码",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["bank", "finance", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            PincodeEntry(
                title: "SIM Card PIN",
                pincode: "4567",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) SIM 卡 PIN 码",
                categoryID: PasswordCategory.systemDefaults[0].id,
                tags: ["device", "sim", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            PincodeEntry(
                title: "Door Lock PIN",
                pincode: "2891",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 家门密码锁",
                categoryID: PasswordCategory.systemDefaults[4].id,
                tags: ["home", "seed"],
                isFavorite: true,
                createdAt: oneYearAgo,
                updatedAt: now.addingTimeInterval(-30 * 24 * 60 * 60)
            ),
            PincodeEntry(
                title: "Safe Box PIN",
                pincode: "736105",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 保险柜密码",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["security", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            PincodeEntry(
                title: "Office Door PIN",
                pincode: "5588",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 公司门禁 PIN",
                categoryID: PasswordCategory.systemDefaults[3].id,
                tags: ["work", "office", "seed"],
                createdAt: oneYearAgo,
                updatedAt: now.addingTimeInterval(-90 * 24 * 60 * 60)
            ),
            PincodeEntry(
                title: "Bike Lock PIN",
                pincode: "4096",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 自行车锁密码",
                categoryID: PasswordCategory.systemDefaults[4].id,
                tags: ["bike", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            PincodeEntry(
                title: "Luggage Lock PIN",
                pincode: "1122",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 行李箱密码锁",
                categoryID: PasswordCategory.systemDefaults[4].id,
                tags: ["travel", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
        ]
    }

    // MARK: - 银行卡种子

    static func makeSeedBankcards() -> [BankcardEntry] {
        let now = Date()
        let oneYearAgo = now.addingTimeInterval(-365 * 24 * 60 * 60)

        return [
            BankcardEntry(
                bankName: "ICBC",
                cardNumber: "6222021234567890123",
                cvv: "123",
                cardholder: "WANG GAVAN",
                expiryDate: "08/28",
                pin: "918273",
                issuingChannel: "Branch",
                onlineBankingPassword: "ICBC@2026!Secure",
                cardType: .debit,
                cardNetworks: ["UnionPay"],
                notes: "\(seedNotesMarker) 工商银行储蓄卡",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["bank", "finance", "seed"],
                isFavorite: true,
                createdAt: oneYearAgo,
                updatedAt: now.addingTimeInterval(-14 * 24 * 60 * 60)
            ),
            BankcardEntry(
                bankName: "China Merchants Bank",
                cardNumber: "6225887766554433",
                cvv: "456",
                cardholder: "WANG GAVAN",
                expiryDate: "11/27",
                pin: "102938",
                issuingChannel: "Mobile App",
                onlineBankingPassword: "CMB@2026!Banking",
                cardType: .credit,
                cardNetworks: ["Visa", "UnionPay"],
                notes: "\(seedNotesMarker) 招商银行信用卡",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["bank", "credit", "seed"],
                isFavorite: false,
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            BankcardEntry(
                bankName: "Bank of China",
                cardNumber: "6217001234567890",
                cvv: "789",
                cardholder: "WANG GAVAN",
                expiryDate: "03/29",
                pin: "564738",
                issuingChannel: "Branch",
                onlineBankingPassword: "BOC@2026!Online",
                cardType: .debit,
                cardNetworks: ["UnionPay"],
                notes: "\(seedNotesMarker) 中国银行借记卡",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["bank", "finance", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            BankcardEntry(
                bankName: "Ping An Bank",
                cardNumber: "6229500099887766",
                cvv: "234",
                cardholder: "WANG GAVAN",
                expiryDate: "06/28",
                pin: "382910",
                issuingChannel: "Mobile App",
                onlineBankingPassword: "PA@2026!Banking",
                cardType: .credit,
                cardNetworks: ["Mastercard", "UnionPay"],
                notes: "\(seedNotesMarker) 平安银行信用卡",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["bank", "credit", "seed"],
                isFavorite: true,
                createdAt: oneYearAgo,
                updatedAt: now.addingTimeInterval(-60 * 24 * 60 * 60)
            ),
            BankcardEntry(
                bankName: "Agricultural Bank",
                cardNumber: "6228480012345678",
                cvv: "567",
                cardholder: "WANG GAVAN",
                expiryDate: "01/30",
                pin: "928103",
                issuingChannel: "Branch",
                onlineBankingPassword: "ABC@2026!Secure",
                cardType: .debit,
                cardNetworks: ["UnionPay"],
                notes: "\(seedNotesMarker) 农业银行储蓄卡",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["bank", "finance", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
        ]
    }

    // MARK: - 构造细节

    /// 种子条目去重标识（站点名 + 用户名，忽略大小写）
    ///
    /// 与 `SettingsViewModel.seedIdentity` 逻辑相同：那份挂在 @MainActor 类上，
    /// 本文件的非隔离静态方法里调不到，因此在这里留一份。
    private static func identity(siteName: String, username: String) -> String {
        "\(siteName.lowercased())|\(username.lowercased())"
    }

    private static func seedSlug(_ value: String) -> String {
        let slug = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return slug.isEmpty ? "app" : slug
    }

    private static func seedCategoryID(for appTitle: String) -> UUID {
        switch appTitle.lowercased() {
        case "apple", "google", "microsoft":
            return PasswordCategory.systemDefaults[0].id  // Primary
        case "github", "linkedin", "slack", "webex", "zoom", "notion", "chatgpt", "claude",
            "dingtalk", "企业微信", "钉钉":
            return PasswordCategory.systemDefaults[3].id  // Work
        case "netflix", "disney", "spotify", "youtube", "douyin", "抖音", "豆瓣":
            return PasswordCategory.systemDefaults[5].id  // Media
        case "alipay", "支付宝":
            return PasswordCategory.systemDefaults[2].id  // Finance
        default:
            return PasswordCategory.systemDefaults[4].id  // Life（兜底）
        }
    }

    /// 按分类挑选登录邮箱：办公类用工作邮箱，主账号用生活邮箱，其余用备用邮箱
    private static func seedEmail(for appTitle: String) -> String {
        let categoryID = seedCategoryID(for: appTitle)
        if categoryID == PasswordCategory.systemDefaults[3].id {
            return SeedEmail.work
        }
        if categoryID == PasswordCategory.systemDefaults[0].id
            || categoryID == PasswordCategory.systemDefaults[2].id
        {
            return SeedEmail.life
        }
        return SeedEmail.backup
    }

    private static func makeFamousAppSeedEntry(_ app: AppTitle, usernameIndex: Int) -> PasswordEntry
    {
        let slug = seedSlug(app.title)
        let username = seedEmail(for: app.title)
        let password = "VaultCell@2026#\(slug.prefix(4).uppercased())\(usernameIndex)"
        // 支持 OAuth 登录的那批应用，这里改成"已开启验证器 App"，不再挂 OAuth 配置：
        // 邮箱收敛成 3 个后，自引用 OAuth（provider 就是站点自己）会被审计的源账户匹配
        // 当成"从同邮箱的别的条目继承"，分数会串到不相干的站点上。
        // OAuth 继承的演示交给 Slack → Google、Notion → Apple 这两条真实场景。
        let usesAuthenticator = oauthProviders.contains {
            $0.caseInsensitiveCompare(app.title) == .orderedSame
        }

        return seedEntry(
            siteName: app.title,
            siteURL: app.url,
            username: username,
            password: password,
            notes: "\(seedNotesMarker) \(app.title)",
            categoryID: seedCategoryID(for: app.title),
            tags: [slug, "seed"],
            has2FA: usesAuthenticator,
            twoFactorConfigs: usesAuthenticator
                ? [TwoFactorConfig(type: .totp, issuer: app.title, boundValue: username)] : []
        )
    }

    private static func augmentSeedEntries(_ base: [PasswordEntry], minimumCount: Int, now: Date)
        -> [PasswordEntry]
    {
        var entries = base
        var keys = Set(
            entries.map {
                identity(siteName: $0.siteName, username: $0.username)
            })

        for app in famousApps {
            let hasAny = entries.contains {
                $0.siteName.caseInsensitiveCompare(app.title) == .orderedSame
            }
            if hasAny { continue }

            let entry = makeFamousAppSeedEntry(app, usernameIndex: 0)
            let key = identity(
                siteName: entry.siteName, username: entry.username)
            if keys.contains(key) { continue }
            entries.append(entry)
            keys.insert(key)
        }

        var extraIndex = 1
        while entries.count < max(minimumCount, 40) {
            var didAppend = false
            for app in famousApps {
                if entries.count >= max(minimumCount, 40) { break }
                let entry = makeFamousAppSeedEntry(app, usernameIndex: extraIndex)
                let key = identity(
                    siteName: entry.siteName, username: entry.username)
                if keys.contains(key) { continue }
                entries.append(entry)
                keys.insert(key)
                didAppend = true
            }
            if !didAppend { break }
            extraIndex += 1
        }

        return entries
    }

    /// 为测试库生成确定性的 TOTP Base32 密钥
    /// 同一站点 + 账号生成的密钥稳定，能生成真实的 6 位验证码
    private static func seedTOTPSecret(for seed: String) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let source = "VaultCell-\(seed)-SEED"

        var buffer = 0
        var bitCount = 0
        var result = ""

        for byte in source.utf8 {
            buffer = (buffer << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                let index = (buffer >> (bitCount - 5)) & 0x1F
                result.append(alphabet[index])
                bitCount -= 5
            }
        }

        if bitCount > 0 {
            buffer <<= (5 - bitCount)
            result.append(alphabet[buffer & 0x1F])
        }

        return result
    }

    /// 把种子数据中的 TOTP 配置补全为"真实"配置：
    /// 1. 为缺少 secret 的 TOTP 配置注入可用的 Base32 密钥（能生成验证码）
    /// 2. 补全创建时间 / 最后验证时间，让 2FA 审计更接近真实
    private static func enrichTOTPConfigs(
        _ configs: [TwoFactorConfig],
        siteName: String,
        username: String
    ) -> [TwoFactorConfig] {
        let now = Date()
        return configs.map { config in
            var updated = config
            if config.type == .totp && (config.secret ?? "").isEmpty {
                let seed = "\(config.issuer ?? siteName)|\(config.boundValue ?? username)"
                updated.secret = Self.seedTOTPSecret(for: seed)
            }
            if updated.createdAt == nil {
                updated.createdAt = now.addingTimeInterval(-90 * 24 * 60 * 60)
            }
            if updated.lastVerifiedAt == nil {
                updated.lastVerifiedAt = now.addingTimeInterval(-24 * 60 * 60)
            }
            return updated
        }
    }

    private static func seedEntry(
        siteName: String,
        siteURL: String,
        username: String,
        password: String,
        bundlePhoneNumber: String? = nil,
        bundleEmailAddress: String? = nil,
        notes: String? = nil,
        categoryID: UUID,
        tags: [String],
        isFavorite: Bool = false,
        isPasswordResetEmail: Bool? = nil,
        isPasswordResetPhone: Bool? = nil,
        has2FA: Bool = false,
        twoFactorConfigs: [TwoFactorConfig] = [],
        oAuthProvider: OAuthProviderConfig? = nil,
        expiresAt: Date? = nil,
        passwordHistory: [PasswordHistoryEntry] = [],
        passwordChangedAt: Date? = nil,
        customFields: [CustomField] = [],
        version: Int64 = 1,
        isSynced: Bool = true,
        isDuplicatePassword: Bool = false,
        breachStatus: BreachStatus = .unknown,
        accountStatus: AccountStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) -> PasswordEntry {
        PasswordEntry(
            siteName: siteName,
            siteURL: siteURL,
            username: username,
            password: password,
            oAuthProvider: oAuthProvider,
            bundlePhoneNumber: bundlePhoneNumber,
            bundleEmailAddress: bundleEmailAddress,
            notes: notes ?? "测试数据：用于快速生成演示密码库",
            categoryID: categoryID,
            tags: tags,
            isFavorite: isFavorite,
            isPasswordResetEmail: isPasswordResetEmail ?? (bundleEmailAddress != nil),
            isPasswordResetPhone: isPasswordResetPhone ?? (bundlePhoneNumber != nil),
            has2FA: has2FA,
            passwordStrength: PasswordStrength.calculate(for: password),
            passwordHistory: passwordHistory,
            passwordChangedAt: passwordChangedAt,
            customFields: customFields,
            version: version,
            isSynced: isSynced,
            isDuplicatePassword: isDuplicatePassword,
            breachStatus: breachStatus,
            accountStatus: accountStatus,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt,
            expiresAt: expiresAt,
            icon: nil,
            twoFactorConfigs: enrichTOTPConfigs(
                twoFactorConfigs, siteName: siteName, username: username),
            dataSource: .testSeed
        )
    }
}

#endif
