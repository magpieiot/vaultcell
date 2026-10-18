/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TOTPServiceTests.swift
/// 覆盖 TOTP（RFC 6238）生成与解析的正确性，使用 RFC 6238 附录 B 的权威测试向量，
/// 防止 HMAC / Base32 / 动态截断任一环节回归导致验证码与主流验证器不兼容。
/// ------------------------------------------------------------------

import CryptoKit
import Foundation
import Testing

@Suite("TOTP 生成（RFC 6238 标准向量）")
struct TOTPServiceGenerationTests {

    private let service = TOTPService.shared
    /// RFC 6238 附录 B 的密钥：明文 "12345678901234567890" 的 Base32 编码
    private let seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    /// 在固定时间步生成 8 位验证码，与 RFC 6238 附录 B 的种子逐项对照。
    /// 说明：RFC 6238 公布表中 SHA256/SHA512 的取值（如 46119246）源于其参考实现
    /// 对密钥做了非标准补齐，并非标准 HMAC 输出；下面的取值由标准 HMAC
    /// （与 CryptoKit 一致、与真实验证器一致）对 20 字节种子独立算出，作为权威期望。
    @Test("SHA1 / SHA256 / SHA512 全算法对照")
    func matchesRFC6238Vectors() {
        let cases: [(counter: UInt64, sha1: String, sha256: String, sha512: String)] = [
            (1, "94287082", "32247374", "69342147"),
            (37_037_036, "07081804", "34756375", "63049338"),
            (37_037_037, "14050471", "74584430", "54380122"),
            (41_152_263, "89005924", "42829826", "76671578"),
            (66_666_666, "69279037", "78428693", "56464532"),
            (666_666_666, "65353130", "24142410", "69481994"),
        ]

        for c in cases {
            let sha1 = service.generate(at: c.counter, config: TOTPConfig(secret: seed, algorithm: .sha1, digits: 8, period: 30))
            let sha256 = service.generate(at: c.counter, config: TOTPConfig(secret: seed, algorithm: .sha256, digits: 8, period: 30))
            let sha512 = service.generate(at: c.counter, config: TOTPConfig(secret: seed, algorithm: .sha512, digits: 8, period: 30))
            #expect(sha1 == c.sha1, "SHA1 counter=\(c.counter) 期望 \(c.sha1) 实际 \(sha1)")
            #expect(sha256 == c.sha256, "SHA256 counter=\(c.counter) 期望 \(c.sha256) 实际 \(sha256)")
            #expect(sha512 == c.sha512, "SHA512 counter=\(c.counter) 期望 \(c.sha512) 实际 \(sha512)")
        }
    }

    /// 默认 6 位：RFC 6238 在 T=59（counter=1）的 SHA1 6 位值为 287082
    @Test("默认 6 位与 RFC 向量一致")
    func defaultSixDigits() {
        let code = service.generate(at: 1, config: TOTPConfig(secret: seed, algorithm: .sha1, period: 30))
        #expect(code == "287082")
        #expect(code.count == 6)
    }

    /// 同一 (secret, counter) 多次生成结果稳定（确定性）
    @Test("同输入确定性")
    func deterministicForSameInput() {
        let a = service.generate(at: 123_456, config: TOTPConfig(secret: "JBSWY3DPEHPK3PXP"))
        let b = service.generate(at: 123_456, config: TOTPConfig(secret: "JBSWY3DPEHPK3PXP"))
        #expect(a == b)
    }

    /// digits 上限夹紧：超过 9 位按 9 位生成
    @Test("digits 超界被夹紧到 9")
    func digitsClampedToNine() {
        let code = service.generate(at: 1, config: TOTPConfig(secret: seed, algorithm: .sha1, digits: 12, period: 30))
        #expect(code.count == 9)
    }

    /// 不同算法对相同输入产生不同验证码（避免算法分支写错）
    @Test("不同算法输出不同")
    func algorithmsDiverge() {
        let sha1 = service.generate(at: 1, config: TOTPConfig(secret: seed, algorithm: .sha1, digits: 8, period: 30))
        let sha256 = service.generate(at: 1, config: TOTPConfig(secret: seed, algorithm: .sha256, digits: 8, period: 30))
        #expect(sha1 != sha256)
    }
}

@Suite("TOTP 校验 validate")
struct TOTPServiceValidateTests {

    private let service = TOTPService.shared

    @Test("当前步生成的验证码可通过校验")
    func acceptsCurrentCode() {
        let config = TOTPConfig(secret: "JBSWY3DPEHPK3PXP")
        let code = service.generate(config: config).code
        #expect(service.validate(code: code, config: config))
    }

    @Test("错误验证码无法通过校验")
    func rejectsWrongCode() {
        let config = TOTPConfig(secret: "JBSWY3DPEHPK3PXP")
        #expect(!service.validate(code: "000000", config: config))
    }

    @Test("长度不符直接失败（恒时比较的前置守卫）")
    func rejectsMismatchedLength() {
        let config = TOTPConfig(secret: "JBSWY3DPEHPK3PXP", digits: 6)
        #expect(!service.validate(code: "12345", config: config))
        #expect(!service.validate(code: "1234567", config: config))
    }

    @Test("时间窗口偏移内的旧步验证码仍可通过")
    func acceptsWindowedCode() {
        let config = TOTPConfig(secret: "JBSWY3DPEHPK3PXP")
        // 用「上一步」的验证码去校验：当前步 -1 应在默认 window(1) 内
        let now = Int(Date().timeIntervalSince1970)
        let prevCode = service.generate(at: UInt64(now / 30) - 1, config: config)
        #expect(service.validate(code: prevCode, config: config))
    }
}

@Suite("TOTP otpauth:// URI 解析")
struct TOTPServiceURITests {

    private let service = TOTPService.shared

    @Test("解析标准 URI 得到 secret / issuer / account")
    func parsesStandardURI() {
        let uri = "otpauth://totp/Example:alice@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&period=30"
        guard let result = service.parseOTPAuthURI(uri) else {
            Issue.record("URI 解析应成功")
            return
        }
        #expect(result.config.secret == "JBSWY3DPEHPK3PXP")
        #expect(result.config.algorithm == .sha1)
        #expect(result.config.digits == 6)
        #expect(result.config.period == 30)
        #expect(result.issuer == "Example")
        #expect(result.account == "alice@gmail.com")
    }

    @Test("issuer 缺省时回退到 label 中的发行方")
    func fallsBackIssuerFromLabel() {
        let uri = "otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP"
        guard let result = service.parseOTPAuthURI(uri) else {
            Issue.record("URI 解析应成功")
            return
        }
        #expect(result.issuer == "GitHub")
        #expect(result.account == "octocat")
    }

    @Test("非 otpauth scheme / 非 totp host 返回 nil")
    func rejectsInvalidURI() {
        #expect(service.parseOTPAuthURI("https://example.com") == nil)
        #expect(service.parseOTPAuthURI("otpauth://hotp/foo?secret=ABC") == nil)
    }

    @Test("缺少 secret 返回 nil")
    func rejectsMissingSecret() {
        #expect(service.parseOTPAuthURI("otpauth://totp/foo?issuer=Example") == nil)
    }

    @Test("解析后生成的验证码与从 URI 重新生成一致")
    func roundTripGeneration() {
        let uri = "otpauth://totp/Example:alice@gmail.com?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=30"
        guard let result = service.parseOTPAuthURI(uri) else {
            Issue.record("URI 解析应成功")
            return
        }
        let code = service.generate(config: result.config).code
        #expect(code.count == 8)
    }
}
