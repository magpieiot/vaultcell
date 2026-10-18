/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TwoFactorTypeTests.swift
/// 覆盖 TwoFactorType 的安全等级与推荐标记，这两个属性驱动 2FA 设置页的
/// 引导与风险提示，回归会导致「把弱 2FA 说成强」或「推荐项错位」。
/// ------------------------------------------------------------------

import Testing

@Suite("TwoFactorType.securityLevel")
struct TwoFactorTypeSecurityLevelTests {

    @Test("硬件密钥为最高等级")
    func hardwareIsVeryHigh() {
        #expect(TwoFactorType.hardware.securityLevel == .veryHigh)
    }

    @Test("TOTP 与推送为高")
    func totpAndPushAreHigh() {
        #expect(TwoFactorType.totp.securityLevel == .high)
        #expect(TwoFactorType.push.securityLevel == .high)
    }

    @Test("短信与邮件为中")
    func smsAndEmailAreMedium() {
        #expect(TwoFactorType.sms.securityLevel == .medium)
        #expect(TwoFactorType.email.securityLevel == .medium)
    }
}

@Suite("TwoFactorType.isRecommended")
struct TwoFactorTypeRecommendedTests {

    @Test("TOTP 与硬件密钥被推荐")
    func recommendedTypes() {
        #expect(TwoFactorType.totp.isRecommended)
        #expect(TwoFactorType.hardware.isRecommended)
    }

    @Test("短信 / 邮件 / 推送不被推荐")
    func notRecommendedTypes() {
        #expect(!TwoFactorType.sms.isRecommended)
        #expect(!TwoFactorType.email.isRecommended)
        #expect(!TwoFactorType.push.isRecommended)
    }
}
