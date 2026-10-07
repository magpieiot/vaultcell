/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IdentityUsageAuditServiceTests.swift
/// 覆盖 IdentityUsageAuditService 的核心规则，防止换号风险评估回归。
/// ------------------------------------------------------------------

import Testing
import Foundation

// MARK: - 归一化：normalizedEmail

@Suite("normalizedEmail")
struct NormalizedEmailTests {
    @Test("整体小写")
    func lowercasesWholeAddress() {
        #expect(IdentityUsageAuditService.normalizedEmail("Test@Example.COM") == "test@example.com")
    }

    @Test("去除 +tag")
    func stripsPlusTag() {
        #expect(IdentityUsageAuditService.normalizedEmail("foo+tag@gmail.com") == "foo@gmail.com")
    }

    @Test("gmail 去掉 local 部分的点号")
    func stripsDotsInGmailLocal() {
        #expect(IdentityUsageAuditService.normalizedEmail("f.o.o@gmail.com") == "foo@gmail.com")
    }

    @Test("googlemail 同样去掉点号")
    func stripsDotsInGooglemailLocal() {
        #expect(IdentityUsageAuditService.normalizedEmail("f.o.o@googlemail.com") == "foo@googlemail.com")
    }

    @Test("非邮箱返回 nil")
    func returnsNilForNonEmail() {
        #expect(IdentityUsageAuditService.normalizedEmail("notanemail") == nil)
    }

    @Test("空 local 返回 nil")
    func returnsNilForEmptyLocal() {
        #expect(IdentityUsageAuditService.normalizedEmail("@gmail.com") == nil)
    }

    @Test("空 domain 返回 nil")
    func returnsNilForEmptyDomain() {
        #expect(IdentityUsageAuditService.normalizedEmail("foo@") == nil)
    }

    @Test("+tag 后 local 为空返回 nil")
    func returnsNilWhenTagLeavesLocalEmpty() {
        #expect(IdentityUsageAuditService.normalizedEmail("+tag@gmail.com") == nil)
    }
}

// MARK: - 归一化：normalizedPhone（.explicit 明确字段）

@Suite("normalizedPhone（.explicit）")
struct NormalizedPhoneTests {
    @Test("纯数字返回原值")
    func keepsPureDigits() {
        #expect(IdentityUsageAuditService.normalizedPhone("13800138000", evidence: .explicit) == "13800138000")
    }

    @Test("带 + 空格 连字符归一化为纯数字")
    func stripsPlusSpaceHyphen() {
        #expect(IdentityUsageAuditService.normalizedPhone("+86 138-0013-8000", evidence: .explicit) == "8613800138000")
    }

    @Test("长度小于 7 返回 nil")
    func returnsNilWhenTooShort() {
        #expect(IdentityUsageAuditService.normalizedPhone("123456", evidence: .explicit) == nil)
    }

    @Test("长度大于 15 返回 nil")
    func returnsNilWhenTooLong() {
        #expect(IdentityUsageAuditService.normalizedPhone("12345678901234567890", evidence: .explicit) == nil)
    }

    @Test("含 @ 返回 nil（避免与邮箱冲突）")
    func returnsNilWhenContainsAt() {
        #expect(IdentityUsageAuditService.normalizedPhone("abc@def", evidence: .explicit) == nil)
    }

    @Test("夹杂字母的串返回 nil")
    func returnsNilWhenContainsLetters() {
        #expect(IdentityUsageAuditService.normalizedPhone("SN13800138000", evidence: .explicit) == nil)
    }
}

// MARK: - 归一化：normalizedPhone（.inferred 推断字段）

@Suite("normalizedPhone（.inferred）")
struct InferredNormalizedPhoneTests {
    @Test("本国手机号形态通过")
    func acceptsMainlandMobile() {
        #expect(IdentityUsageAuditService.normalizedPhone("13800138000", evidence: .inferred) == "13800138000")
    }

    @Test("带国际前缀的写法通过")
    func acceptsInternationalPrefix() {
        #expect(IdentityUsageAuditService.normalizedPhone("+86 138 0013 8000", evidence: .inferred) == "8613800138000")
        #expect(IdentityUsageAuditService.normalizedPhone("0044 20 7946 0958", evidence: .inferred) == "00442079460958")
    }

    @Test("分组书写的固话 / 国际号码通过")
    func acceptsGroupedNumbers() {
        #expect(IdentityUsageAuditService.normalizedPhone("010 8888 8888", evidence: .inferred) == "01088888888")
        #expect(IdentityUsageAuditService.normalizedPhone("415-555-2671", evidence: .inferred) == "4155552671")
    }

    @Test("QQ 号这类纯数字被拒绝")
    func rejectsBareDigits() {
        #expect(IdentityUsageAuditService.normalizedPhone("123456789", evidence: .inferred) == nil)
        #expect(IdentityUsageAuditService.normalizedPhone("1234567890", evidence: .inferred) == nil)
        #expect(IdentityUsageAuditService.normalizedPhone("1234567890123", evidence: .inferred) == nil)
    }

    @Test("日期写法被拒绝")
    func rejectsDate() {
        #expect(IdentityUsageAuditService.normalizedPhone("2026-09-30", evidence: .inferred) == nil)
    }

    @Test("0 开头的短编号被拒绝（不够国际号码长度）")
    func rejectsShortLeadingZero() {
        #expect(IdentityUsageAuditService.normalizedPhone("00138000", evidence: .inferred) == nil)
    }

    @Test("IP 地址被拒绝")
    func rejectsIPAddress() {
        #expect(IdentityUsageAuditService.normalizedPhone("192.168.1.1", evidence: .inferred) == nil)
    }

    @Test("与字母 / 下划线粘连的数字串被拒绝")
    func rejectsIdentifiersWithLetters() {
        #expect(IdentityUsageAuditService.normalizedPhone("wx_12345678", evidence: .inferred) == nil)
    }
}

// MARK: - 归一化：phoneKeyMatches

@Suite("phoneKeyMatches")
struct PhoneKeyMatchesTests {
    @Test("完全相等为 true")
    func exactMatch() {
        #expect(IdentityUsageAuditService.phoneKeyMatches("13800138000", "13800138000") == true)
    }

    @Test("一方是另一方后缀为 true")
    func suffixMatch() {
        #expect(IdentityUsageAuditService.phoneKeyMatches("8613800138000", "13800138000") == true)
    }

    @Test("长度差大于 3 为 false")
    func lengthDiffTooLarge() {
        #expect(IdentityUsageAuditService.phoneKeyMatches("12345678901234567890", "1234567890123") == false)
    }

    @Test("长度小于 7 为 false")
    func tooShort() {
        #expect(IdentityUsageAuditService.phoneKeyMatches("1234", "1234") == false)
    }
}

// MARK: - 风险判定

@Suite("风险判定 risk(for:)")
struct RiskTests {

    private let service = IdentityUsageAuditService()

    /// 构造最小 PasswordEntry fixture。
    private func makeEntry(
        siteName: String = "Example",
        username: String? = nil,
        bundleEmailAddress: String? = nil,
        bundlePhoneNumber: String? = nil,
        isPasswordResetEmail: Bool = false,
        isPasswordResetPhone: Bool = false,
        twoFactorConfigs: [TwoFactorConfig] = [],
        has2FA: Bool = false,
        oAuthProvider: OAuthProviderConfig? = nil,
        notes: String? = nil
    ) -> PasswordEntry {
        PasswordEntry(
            siteName: siteName,
            username: username ?? "",
            password: "pw",
            oAuthProvider: oAuthProvider,
            bundlePhoneNumber: bundlePhoneNumber,
            bundleEmailAddress: bundleEmailAddress,
            notes: notes,
            isPasswordResetEmail: isPasswordResetEmail,
            isPasswordResetPhone: isPasswordResetPhone,
            has2FA: has2FA,
            twoFactorConfigs: twoFactorConfigs
        )
    }

    /// 取出某条 entry 中 key 对应的第一个 IdentityUsage（用于断言 risk）。
    private func usage(for entry: PasswordEntry, key: String) -> IdentityUsage? {
        service.scan(entries: [entry])
            .first { $0.id == key }?
            .usages
            .first
    }

    @Test("[.recovery] 无替代通道 → critical")
    func recoveryWithoutAlternativeIsCritical() {
        let entry = makeEntry(bundleEmailAddress: "alice@example.com", isPasswordResetEmail: true)
        #expect(usage(for: entry, key: "alice@example.com")?.risk == .critical)
    }

    @Test("[.recovery] + has2FA → high")
    func recoveryWith2FAIsHigh() {
        let entry = makeEntry(bundleEmailAddress: "alice@example.com", isPasswordResetEmail: true, has2FA: true)
        #expect(usage(for: entry, key: "alice@example.com")?.risk == .high)
    }

    @Test("[.recovery] + 另一种联系方式（不同 kind）→ high")
    func recoveryWithOtherContactKindIsHigh() {
        let entry = makeEntry(
            bundleEmailAddress: "alice@example.com",
            bundlePhoneNumber: "13800138000",
            isPasswordResetEmail: true
        )
        #expect(usage(for: entry, key: "alice@example.com")?.risk == .high)
    }

    @Test("[.twoFactor] → high")
    func twoFactorIsHigh() {
        let entry = makeEntry(
            twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "13800138000", isEnabled: true)]
        )
        #expect(usage(for: entry, key: "13800138000")?.risk == .high)
    }

    @Test("[.oauth] → high")
    func oauthIsHigh() {
        let entry = makeEntry(oAuthProvider: OAuthProviderConfig(boundValue: "alice@example.com"))
        #expect(usage(for: entry, key: "alice@example.com")?.risk == .high)
    }

    @Test("[.login] → medium")
    func loginIsMedium() {
        let entry = makeEntry(username: "alice@example.com")
        #expect(usage(for: entry, key: "alice@example.com")?.risk == .medium)
    }

    @Test("[.contact] → medium")
    func contactIsMedium() {
        let entry = makeEntry(bundleEmailAddress: "alice@example.com")
        #expect(usage(for: entry, key: "alice@example.com")?.risk == .medium)
    }

    @Test("[.mention]（备注中提及）→ low")
    func mentionIsLow() {
        let entry = makeEntry(notes: "请通过 alice@example.com 联系我")
        let report = service.evaluate("alice@example.com", in: [entry])
        #expect(report?.usages.first?.roles.contains(.mention) == true)
        #expect(report?.usages.first?.risk == .low)
    }
}

// MARK: - 综合扫描 scan(entries:)

@Suite("综合扫描 scan(entries:)")
struct ScanTests {

    private let service = IdentityUsageAuditService()

    private func makeEntry(
        siteName: String = "Example",
        username: String? = nil,
        bundleEmailAddress: String? = nil,
        bundlePhoneNumber: String? = nil
    ) -> PasswordEntry {
        PasswordEntry(
            siteName: siteName,
            username: username ?? "",
            password: "pw",
            bundlePhoneNumber: bundlePhoneNumber,
            bundleEmailAddress: bundleEmailAddress
        )
    }

    @Test("空 entries → 空数组")
    func emptyEntries() {
        #expect(service.scan(entries: []).isEmpty)
    }

    @Test("一条 entry 一个邮箱 → 一个 report，usages = 1")
    func singleEmail() {
        let reports = service.scan(entries: [makeEntry(bundleEmailAddress: "alice@example.com")])
        #expect(reports.count == 1)
        #expect(reports[0].kind == .email)
        #expect(reports[0].usages.count == 1)
    }

    @Test("同一 key 多个用法 → 仍一个 report")
    func sameKeyMultipleRoles() {
        let entry = makeEntry(username: "alice@example.com", bundleEmailAddress: "alice@example.com")
        let reports = service.scan(entries: [entry])
        #expect(reports.count == 1)
        #expect(reports[0].usages.count == 1)
    }

    @Test("国家码不同的两种写法合并为一个 report")
    func countryCodeVariantsMerge() {
        let e1 = makeEntry(bundlePhoneNumber: "+86 13800138000")
        let e2 = makeEntry(bundlePhoneNumber: "13800138000")
        let reports = service.scan(entries: [e1, e2])
        #expect(reports.count == 1)
        #expect(reports[0].kind == .phone)
        #expect(reports[0].usages.count == 2)
    }
}

// MARK: - 非电话号码的纯数字串

/// 序列号、QQ 号、订单号这类纯数字串不应被误报成手机号
@Suite("纯数字标识符不误报为手机号")
struct NonPhoneDigitsTests {

    private let service = IdentityUsageAuditService()

    private func makeEntry(
        username: String = "u",
        bundleEmailAddress: String? = nil,
        bundlePhoneNumber: String? = nil,
        oAuthProvider: OAuthProviderConfig? = nil,
        notes: String? = nil,
        customFields: [CustomField] = []
    ) -> PasswordEntry {
        PasswordEntry(
            siteName: "Example",
            username: username,
            password: "pw",
            oAuthProvider: oAuthProvider,
            bundlePhoneNumber: bundlePhoneNumber,
            bundleEmailAddress: bundleEmailAddress,
            notes: notes,
            customFields: customFields
        )
    }

    @Test("用户名为 QQ 号 → 不产生手机号报告")
    func qqUsernameIsNotPhone() {
        let reports = service.scan(entries: [makeEntry(username: "123456789")])
        #expect(reports.filter { $0.kind == .phone }.isEmpty)
    }

    @Test("自定义字段里的序列号 → 不产生手机号报告")
    func serialNumberCustomFieldIsNotPhone() {
        let entry = makeEntry(
            customFields: [CustomField(name: "序列号", value: "1234567890123")]
        )
        let reports = service.scan(entries: [entry])
        #expect(reports.filter { $0.kind == .phone }.isEmpty)
    }

    @Test("备注里的序列号 / 日期不会给号码加上“提及”用法")
    func serialAndDateInNotesAreNotMentioned() {
        // 序列号 00138000 恰好是手机号后缀：交给提取逻辑时曾被当成“提到过这个号码”
        let entry = makeEntry(
            bundlePhoneNumber: "13800138000",
            notes: "序列号 00138000，订单号 9876543210，注册时间 2026-09-30"
        )
        let report = service.scan(entries: [entry]).first { $0.id == "13800138000" }
        #expect(report?.usages.first?.roles == [.contact])
    }

    @Test("备注里带国家码的号码仍会被识别为提及")
    func internationalNumberInNotesIsMentioned() {
        let entry = makeEntry(notes: "备用联系号码 +86 138 0013 8000")
        let report = service.evaluate("13800138000", in: [entry])
        #expect(report?.usages.first?.roles.contains(.mention) == true)
    }

    @Test("用户名就是手机号 → 仍按登录名记录")
    func mobileUsernameIsStillLogin() {
        let reports = service.scan(entries: [makeEntry(username: "+8613800138000")])
        #expect(reports.count == 1)
        #expect(reports[0].kind == .phone)
        #expect(reports[0].usages.first?.roles.contains(.login) == true)
    }
}

// MARK: - 评估 evaluate(_:in:)

@Suite("评估 evaluate(_:in:)")
struct EvaluateTests {

    private let service = IdentityUsageAuditService()

    private func makeEntry(bundleEmailAddress: String? = nil) -> PasswordEntry {
        PasswordEntry(siteName: "Example", username: "u", password: "pw", bundleEmailAddress: bundleEmailAddress)
    }

    @Test("输入合法但不在库中 → report with empty usages")
    func validButNotInLibrary() {
        let report = service.evaluate("foo@example.com", in: [])
        #expect(report != nil)
        #expect(report?.kind == .email)
        #expect(report?.usages.isEmpty == true)
    }

    @Test("输入既不是手机号也不是邮箱 → nil")
    func neitherPhoneNorEmail() {
        #expect(service.evaluate("justaname", in: []) == nil)
    }

    @Test("输入合法且匹配库内 entry → report with usages")
    func validAndMatchesEntry() {
        let entry = makeEntry(bundleEmailAddress: "alice@example.com")
        let report = service.evaluate("alice@example.com", in: [entry])
        #expect(report != nil)
        #expect(report?.usages.count == 1)
    }
}
