/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordStrengthTests.swift
/// 覆盖 PasswordStrength.calculate(for:) 的评分规则，防止密码强度误判
/// （过强判弱会误导用户，过弱判强会制造虚假安全感）。
/// ------------------------------------------------------------------

import Testing

@Suite("PasswordStrength.calculate")
struct PasswordStrengthTests {

    @Test("空密码 → veryWeak")
    func emptyIsVeryWeak() {
        #expect(PasswordStrength.calculate(for: "") == .veryWeak)
    }

    @Test("短纯小写 → veryWeak")
    func shortLowercaseIsVeryWeak() {
        // 3 位、仅小写：长度与字符类型都未满档
        #expect(PasswordStrength.calculate(for: "abc") == .veryWeak)
    }

    @Test("8 位纯小写 → veryWeak（仅 2 分）")
    func eightLowercaseIsVeryWeak() {
        #expect(PasswordStrength.calculate(for: "abcdefgh") == .veryWeak)
    }

    @Test("12 位纯小写 → weak（3 分）")
    func twelveLowercaseIsWeak() {
        #expect(PasswordStrength.calculate(for: "abcdefghijkl") == .weak)
    }

    @Test("16 位纯小写 → medium（4 分）")
    func sixteenLowercaseIsMedium() {
        #expect(PasswordStrength.calculate(for: "abcdefghijklmnop") == .medium)
    }

    @Test("8 位含大小写 → weak（3 分）")
    func eightMixedCaseIsWeak() {
        #expect(PasswordStrength.calculate(for: "Abcdefgh") == .weak)
    }

    @Test("含大小写 + 数字 → medium（4 分）")
    func mixedWithDigitIsMedium() {
        #expect(PasswordStrength.calculate(for: "Abcdefgh12") == .medium)
    }

    @Test("含大小写 + 数字 + 符号 → medium（5 分）")
    func mixedWithSymbolIsMedium() {
        #expect(PasswordStrength.calculate(for: "Abcdefgh1!") == .medium)
    }

    @Test("12 位 + 四类齐全 → strong（6 分）")
    func strongScore() {
        #expect(PasswordStrength.calculate(for: "Abcdefghijkl1!") == .strong)
    }

    @Test("16 位 + 四类齐全 → veryStrong（7 分，满分）")
    func veryStrongScore() {
        #expect(PasswordStrength.calculate(for: "Abcdefghijklmnop1!") == .veryStrong)
    }

    @Test("默认强度落在枚举范围内（边界：恰好 6 分 strong，7 分 veryStrong）")
    func scoreBoundaries() {
        // 6 分 → strong；7 分 → veryStrong（default 分支）
        #expect(PasswordStrength.calculate(for: "Abcdefghijkl1!") == .strong)
        #expect(PasswordStrength.calculate(for: "Abcdefghijklmnop1!") == .veryStrong)
    }

    @Test("首字符大写阈值：第二字符不影响字母类型计数")
    func onlyOneUppercaseCountsOnce() {
        // 单个大写 + 小写 + 数字 = 3 字符类型分 + 长度分
        let score = PasswordStrength.calculate(for: "Password1")
        // 9 位：len>=8 (+1)，大写 +1，小写 +1，数字 +1 = 4 → medium
        #expect(score == .medium)
    }
}
