/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordStrengthAnalyzer.swift
/// created on: 23/09/2026
/// ------------------------------------------------------------------

import Foundation

/// 密码校验规则：每一项对应校验页清单里的一行
enum PasswordCheckRule: String, CaseIterable, Identifiable {
    /// 长度是否达标
    case length
    /// 字符类型是否够杂（大小写 / 数字 / 符号）
    case characterVariety
    /// 是否不是常见弱口令
    case commonPassword
    /// 是否不含连续序列（abcd / 4321 / qwerty）
    case sequentialPattern
    /// 是否不含重复片段（aaaa / 1111）
    case repeatedPattern
    /// 是否没有被库内其他条目重复使用
    case vaultUniqueness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .length:
            return String(localized: "At least 12 characters")
        case .characterVariety:
            return String(localized: "Uses at least three of: upper, lower, digit, symbol")
        case .commonPassword:
            return String(localized: "Not a commonly used password")
        case .sequentialPattern:
            return String(localized: "No keyboard or alphabetic runs (abcd, 1234, qwerty)")
        case .repeatedPattern:
            return String(localized: "No long repeated runs (aaaa, 1111)")
        case .vaultUniqueness:
            return String(localized: "Not already used by another saved entry")
        }
    }

    /// 未通过时的修复建议（清单行下方的小字）
    var guidance: String {
        switch self {
        case .length:
            return String(localized: "Longer passwords take far more effort to crack. Aim for 16 or more.")
        case .characterVariety:
            return String(localized: "Add a mix of capital letters, digits, and symbols.")
        case .commonPassword:
            return String(localized: "This appears on public breach word lists. Pick something less predictable.")
        case .sequentialPattern:
            return String(localized: "Runs of neighbouring keys are guessed early by attackers.")
        case .repeatedPattern:
            return String(localized: "Repeated characters add length without adding strength.")
        case .vaultUniqueness:
            return String(localized: "Reusing a password lets one breach unlock every account that shares it.")
        }
    }
}

struct PasswordCheckFinding: Identifiable, Hashable {
    let rule: PasswordCheckRule
    let passed: Bool

    var id: String { rule.rawValue }
}

struct PasswordCheckReport {
    /// 输入为空：此时不展示清单，只展示空态
    let isEmpty: Bool
    /// 最终强度：以 `PasswordStrength.calculate` 为基础，被弱口令 / 模式化规则向下修正
    let strength: PasswordStrength
    let findings: [PasswordCheckFinding]
    /// 与输入相同的已保存条目标题（只回显标题，不回显密码）
    let reusedEntryTitles: [String]

    var passedCount: Int {
        findings.filter(\.passed).count
    }

    /// 是否所有规则都通过
    var isAllPassed: Bool {
        !isEmpty && findings.allSatisfy(\.passed)
    }

    /// 最该优先修的一条：返回第一条未通过的规则
    var firstFailed: PasswordCheckRule? {
        findings.first { !$0.passed }?.rule
    }
}

/// 密码校验：纯本地判定，不联网、不落盘
///
/// 与 `PasswordStrength.calculate` 的关系：
/// - `calculate` 只看长度与字符类型，服务于全库评分（改动会影响存量分数，因此不动它）；
/// - 本分析器在它的基础上补上弱口令、模式化、库内重复三类判定，
///   并把命中弱口令 / 模式化的结果向下修正强度，避免 "Password123!" 这类
///   字符类型齐全但极弱的密码被评成 Strong。
enum PasswordStrengthAnalyzer {

    // MARK: - 对外入口

    /// 对一条密码做完整校验
    /// - Parameters:
    ///   - password: 待校验的明文密码（调用方负责不保存、不上传）
    ///   - entries: 库内已保存的密码条目，用于重复检测
    static func check(_ password: String, entries: [PasswordEntry]) -> PasswordCheckReport {
        guard !password.isEmpty else {
            return PasswordCheckReport(
                isEmpty: true,
                strength: .veryWeak,
                findings: [],
                reusedEntryTitles: []
            )
        }

        let lengthPassed = password.count >= Self.minimumLength
        let varietyPassed = characterClassCount(password) >= Self.minimumCharacterClasses
        let commonFailed = isCommonPassword(password)
        let sequentialFailed = hasSequentialRun(password) || hasKeyboardRun(password)
        let repeatedFailed = hasRepeatedRun(password)

        let reused = reusedEntryTitles(for: password, in: entries)
        let uniquePassed = reused.isEmpty

        // 强度修正：弱口令直接压到最低档，模式化最多 medium
        var strength = PasswordStrength.calculate(for: password)
        if commonFailed {
            strength = .veryWeak
        } else if sequentialFailed || repeatedFailed {
            strength = capped(strength, at: .medium)
        }

        let findings: [PasswordCheckFinding] = [
            PasswordCheckFinding(rule: .length, passed: lengthPassed),
            PasswordCheckFinding(rule: .characterVariety, passed: varietyPassed),
            PasswordCheckFinding(rule: .commonPassword, passed: !commonFailed),
            PasswordCheckFinding(rule: .sequentialPattern, passed: !sequentialFailed),
            PasswordCheckFinding(rule: .repeatedPattern, passed: !repeatedFailed),
            PasswordCheckFinding(rule: .vaultUniqueness, passed: uniquePassed),
        ]

        return PasswordCheckReport(
            isEmpty: false,
            strength: strength,
            findings: findings,
            reusedEntryTitles: reused
        )
    }

    // MARK: - 阈值

    /// 长度达标线
    private static let minimumLength = 12
    /// 字符类型达标线（大写 / 小写 / 数字 / 符号共四类）
    private static let minimumCharacterClasses = 3
    /// 连续 / 重复片段的判定长度
    private static let runLength = 4

    // MARK: - 规则判定

    /// 命中的字符类型数量（0...4）
    private static func characterClassCount(_ password: String) -> Int {
        var count = 0
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { count += 1 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { count += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { count += 1 }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { count += 1 }
        return count
    }

    /// 常见弱口令：命中即视为极弱
    ///
    /// 匹配时先归一化为「小写 + 字母数字」，再逐级剥掉尾部的数字与符号，
    /// 这样 password、Password123、123456! 都能命中，而 ApplePie2026 这类
    /// 恰好包含常见词的长密码不会被误判。
    private static func isCommonPassword(_ password: String) -> Bool {
        let normalized = password.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.isEmpty else { return false }
        guard !commonPasswords.contains(normalized) else { return true }

        let tail = CharacterSet.decimalDigits.union(CharacterSet.punctuationCharacters)
        var trimmed = normalized
        while let last = trimmed.last,
            let scalar = Unicode.Scalar(String(last)),
            tail.contains(scalar)
        {
            trimmed.removeLast()
            if commonPasswords.contains(trimmed) { return true }
        }
        return false
    }

    /// 连续序列：abcd、4321 这类相邻码位递增 / 递减片段
    private static func hasSequentialRun(_ password: String) -> Bool {
        let scalars = Array(password.lowercased().unicodeScalars)
        guard scalars.count >= runLength else { return false }

        var ascending = 1
        var descending = 1
        for index in 1..<scalars.count {
            let previous = scalars[index - 1].value
            let current = scalars[index].value

            ascending = (current == previous + 1) ? ascending + 1 : 1
            descending = (current + 1 == previous) ? descending + 1 : 1

            if ascending >= runLength || descending >= runLength { return true }
        }
        return false
    }

    /// 键盘相邻序列：qwerty、asdf、zxcvbn 这类按键盘布局走出来的片段
    private static func hasKeyboardRun(_ password: String) -> Bool {
        let lowered = password.lowercased()
        return keyboardRuns.contains { lowered.contains($0) }
    }

    /// 重复片段：aaaa、1111
    private static func hasRepeatedRun(_ password: String) -> Bool {
        let chars = Array(password)
        guard chars.count >= runLength else { return false }

        var run = 1
        for index in 1..<chars.count {
            run = (chars[index] == chars[index - 1]) ? run + 1 : 1
            if run >= runLength { return true }
        }
        return false
    }

    /// 库内重复：只返回标题，避免把其他条目的密码回显到界面上
    private static func reusedEntryTitles(for password: String, in entries: [PasswordEntry]) -> [String] {
        entries.filter { $0.password == password }.map(\.siteName)
    }

    /// 把强度压到指定上限之下（取 rawValue 较小者）
    private static func capped(_ strength: PasswordStrength, at ceiling: PasswordStrength) -> PasswordStrength {
        PasswordStrength(rawValue: min(strength.rawValue, ceiling.rawValue)) ?? strength
    }

    // MARK: - 词表

    /// 常见弱口令词表：取自公开泄露统计里出现频率最高的一批
    private static let commonPasswords: Set<String> = [
        "password", "passw0rd", "password1", "p@ssword",
        "123456", "1234567", "12345678", "123456789", "1234567890",
        "111111", "000000", "123123", "1234", "12345", "654321",
        "qwerty", "qwertyuiop", "qwerty123", "1q2w3e4r",
        "abc123", "abcd1234", "admin", "admin123", "administrator",
        "iloveyou", "letmein", "welcome", "welcome1", "changeme", "secret",
        "monkey", "dragon", "sunshine", "princess", "football", "baseball",
        "master", "login", "starwars", "whatever", "trustno1", "test", "test123",
        "apple", "google", "michael", "jennifer", "shadow", "superman",
    ]

    /// 键盘相邻序列片段
    private static let keyboardRuns: Set<String> = [
        "qwerty", "asdf", "zxcvbn", "qazwsx", "wasd", "1qaz",
    ]
}
