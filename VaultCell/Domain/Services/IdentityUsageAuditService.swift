/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IdentityUsageAuditService.swift
/// created on: 08/09/2026
/// ------------------------------------------------------------------

import Foundation

/// 联系方式类型：手机号 / 邮箱
enum IdentityKind: String, CaseIterable, Identifiable {
    case phone
    case email

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phone: return String(localized: "Phone Number")
        case .email: return String(localized: "Email Address")
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .phone: return String(localized: "Phone Numbers")
        case .email: return String(localized: "Email Addresses")
        }
    }

    var iconName: String {
        switch self {
        case .phone: return "phone.fill"
        case .email: return "envelope.fill"
        }
    }
}

/// 注销 / 换号风险等级
/// 用于回答“剪断这条联系链，会掉几个账户”
enum IdentityRiskLevel: Int, CaseIterable, Comparable, Hashable {
    /// 仅文本提及，或关联账户已停用
    case low = 0
    /// 作为登录名或绑定联系方式，但账户还有其他找回途径
    case medium = 1
    /// 启用中的短信 / 邮件 2FA、OAuth 主绑定，或有备用通道的密码重置方式
    case high = 2
    /// 唯一的密码重置 / 找回通道，失去它就无法再登录
    case critical = 3

    static func < (lhs: IdentityRiskLevel, rhs: IdentityRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .critical: return String(localized: "Critical")
        }
    }

    /// 图标与文字、颜色共同构成风险提示，避免仅靠颜色表意
    var iconName: String {
        switch self {
        case .low: return "text.magnifyingglass"
        case .medium: return "link.badge.plus"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }


}

/// 某个联系方式在单条密码条目中承担的用途
enum IdentityRole: Int, CaseIterable, Comparable, Hashable {
    /// 只在备注或自定义字段中被提到
    case mention = 0
    /// 绑定的联系方式
    case contact = 1
    /// 登录名
    case login = 2
    /// 短信 / 邮件 2FA 的接收端
    case twoFactor = 3
    /// 第三方登录（OAuth）的绑定账号
    case oauth = 4
    /// 密码重置 / 找回通道
    case recovery = 5

    static func < (lhs: IdentityRole, rhs: IdentityRole) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .mention: return String(localized: "Mentioned")
        case .contact: return String(localized: "Bound contact")
        case .login: return String(localized: "Login name")
        case .twoFactor: return String(localized: "2FA")
        case .oauth: return String(localized: "OAuth")
        case .recovery: return String(localized: "Password reset")
        }
    }

    var iconName: String {
        switch self {
        case .mention: return "text.quote"
        case .contact: return "person.text.rectangle"
        case .login: return "person.crop.circle"
        case .twoFactor: return "lock.shield"
        case .oauth: return "arrow.triangle.branch"
        case .recovery: return "key.fill"
        }
    }
}

/// 单个密码条目对某个联系方式的依赖
struct IdentityUsage: Identifiable, Hashable {
    var id: UUID { entryID }

    let entryID: UUID
    let siteName: String
    let username: String
    let roles: Set<IdentityRole>
    /// 命中的短信 / 邮件 2FA 类型（用于说明“收验证码的号码”）
    let twoFactorTypes: [TwoFactorType]
    let risk: IdentityRiskLevel

    /// 用途从重到轻排列，用于生成说明文案
    var sortedRoles: [IdentityRole] {
        roles.sorted { $0 > $1 }
    }
}

/// 某个手机号 / 邮箱在密码库中的使用报告
struct IdentityReport: Identifiable, Hashable {
    /// 归一化后的联系方式（手机号=纯数字；邮箱=小写去标签）
    let id: String
    let kind: IdentityKind
    /// 库中记录的原始写法（展示用，脱敏在视图层完成）
    let value: String
    let usages: [IdentityUsage]

    var risk: IdentityRiskLevel { usages.map(\.risk).max() ?? .low }

    /// 换号前必须处理的条目（critical + high）
    var blockingUsages: [IdentityUsage] {
        usages.filter { $0.risk >= .high }
    }

    /// 失去该联系方式后完全无法找回的条目数
    var criticalCount: Int {
        usages.filter { $0.risk == .critical }.count
    }
}

/// 手机号的识别严格度
///
/// 同一串数字出现在不同字段里，含义完全不同：手机号字段里的 11 位数字就是手机号，
/// 而用户名里的纯数字更可能是 QQ 号 / 学号 / 工号，备注与自定义字段里的数字
/// 则常见为序列号、订单号或日期。因此按“字段语义是否本身就是手机号”分两档：
/// 语义明确的字段保持宽松（宁可不漏），只能靠内容推断的地方收紧（宁可不错）。
enum PhoneEvidence {
    /// 字段语义上就是手机号：手机号字段、短信 2FA 绑定值、用户手动输入的号码
    case explicit
    /// 只能靠内容推断：用户名、邮箱字段、OAuth 绑定值、备注与自定义字段
    case inferred
}

/// 手机号 / 邮箱使用情况的审计服务
///
/// 扫描密码条目，找出每个手机号或邮箱被哪些账户依赖，并按“注销 / 换号”的后果分级。
/// 只做纯内存计算，不接触存储层，便于单独推理与复用。
struct IdentityUsageAuditService {

    // MARK: - 对外接口

    /// 扫描整个密码库，返回每个手机号 / 邮箱的使用报告（风险从高到低）
    func scan(entries: [PasswordEntry]) -> [IdentityReport] {
        let indexes = entries.map(Self.buildIndex)

        // 候选池：所有被条目“正式使用”的联系方式（不含文本提及）。
        // 手机号按近似规则合并，保证 +86 138… 与 138… 只出现一行。
        var candidates: [String: (kind: IdentityKind, raw: String)] = [:]
        for index in indexes {
            for key in index.rolesByKey.keys {
                guard Self.resolvedKey(for: key, in: candidates) == nil else { continue }
                candidates[key] = (Self.detectKind(of: key), index.rawByKey[key] ?? key)
            }
        }

        var reports: [IdentityReport] = []
        reports.reserveCapacity(candidates.count)

        for (key, candidate) in candidates {
            let usages = Self.collectUsages(in: indexes, key: key, kind: candidate.kind)
            guard !usages.isEmpty else { continue }
            reports.append(
                IdentityReport(
                    id: key,
                    kind: candidate.kind,
                    value: candidate.raw,
                    usages: usages
                )
            )
        }

        return Self.sorted(reports)
    }

    /// 评估任意输入（可能尚未入库）的号码 / 邮箱
    /// 命中返回报告（usages 可能为空），输入不是合法手机号或邮箱时返回 nil
    ///
    /// 输入框本身就是“手机号 / 邮箱”，用户明确表达了意图，因此手机号按 `.explicit` 判定
    /// （只挡掉带字母等明显不是号码的输入）。
    func evaluate(_ input: String, in entries: [PasswordEntry]) -> IdentityReport? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (kind, key) = Self.detect(trimmed, phoneEvidence: .explicit) else { return nil }

        let indexes = entries.map(Self.buildIndex)
        let usages = Self.collectUsages(in: indexes, key: key, kind: kind)
        return IdentityReport(id: key, kind: kind, value: trimmed, usages: usages)
    }

    /// 识别一段文本是手机号还是邮箱，并给出归一化键
    /// - Parameter phoneEvidence: 手机号的识别严格度，由调用方按字段语义决定
    /// - Returns: nil 表示既不是手机号也不是邮箱（如普通用户名）
    static func detect(
        _ raw: String,
        phoneEvidence: PhoneEvidence
    ) -> (kind: IdentityKind, key: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("@"), let key = normalizedEmail(trimmed) {
            return (.email, key)
        }
        if let key = normalizedPhone(trimmed, evidence: phoneEvidence) {
            return (.phone, key)
        }
        return nil
    }

    // MARK: - 归一化

    /// 邮箱归一化：整体小写；去掉 +tag；gmail 系列额外去掉 local 部分中的点号
    static func normalizedEmail(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = trimmed.lastIndex(of: "@") else { return nil }

        let local = String(trimmed[trimmed.startIndex..<atIndex])
        let domain = String(trimmed[trimmed.index(after: atIndex)...])
        guard !local.isEmpty, !domain.isEmpty, domain.contains(".") else { return nil }
        guard trimmed.allSatisfy({ !$0.isWhitespace }) else { return nil }

        var normalizedLocal = local
        if let plusIndex = normalizedLocal.firstIndex(of: "+") {
            normalizedLocal = String(normalizedLocal[normalizedLocal.startIndex..<plusIndex])
        }
        if domain == "gmail.com" || domain == "googlemail.com" {
            normalizedLocal = normalizedLocal.replacingOccurrences(of: ".", with: "")
        }
        guard !normalizedLocal.isEmpty else { return nil }
        return normalizedLocal + "@" + domain
    }

    /// 手机号归一化：仅保留数字，长度需在 7...15 之间
    ///
    /// - Parameter evidence: 识别严格度。
    ///   - `.explicit`：字段本身就是手机号，只校验字符集与长度；
    ///   - `.inferred`：额外要求数字串自身具备电话特征（见 `looksLikePhoneNumber`），
    ///     以免把序列号、QQ 号、订单号这类纯数字串当成手机号。
    ///
    /// 两种模式返回的键都是纯数字，因此同一号码的不同写法仍能合并。
    static func normalizedPhone(_ raw: String, evidence: PhoneEvidence) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("@") else { return nil }
        guard let digits = phoneDigits(in: trimmed) else { return nil }
        guard (7...15).contains(digits.count) else { return nil }

        switch evidence {
        case .explicit:
            return digits
        case .inferred:
            return looksLikePhoneNumber(trimmed, digits: digits) ? digits : nil
        }
    }

    /// 号码里允许出现的非数字字符：国际前缀、分组分隔符、电话键盘上的 `*` `#`，
    /// 以及中文输入法容易带出的全角空格 / 括号 / 加减号
    private static let phonePunctuation = CharacterSet(
        charactersIn: "+-().*#\u{00A0} \u{3000}（）＋－")

    /// 取出号码中的数字；出现号码之外的字符（字母、货币符号、下划线等）时返回 nil，
    /// 挡住 `SN-1234567890`、`ID12345678`、`wx_12345678` 这类被粘连的数字串
    private static func phoneDigits(in raw: String) -> String? {
        var digits = ""
        for ch in raw {
            if ch.isNumber {
                digits.append(ch)
            } else if !isPhonePunctuation(ch) {
                return nil
            }
        }
        return digits.isEmpty ? nil : digits
    }

    private static func isPhonePunctuation(_ ch: Character) -> Bool {
        let scalars = ch.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        return phonePunctuation.contains(scalar)
    }

    /// 仅凭内容判断数字串是否像手机号（`.inferred` 模式用）
    ///
    /// 满足任一条件才算数：
    /// 1. 带国际前缀（`+` / `00`），位数在 10...15（国家码 + 本地号码不会更短，
    ///    否则 `00138000` 这类 0 开头的短编号会被误判）；
    /// 2. 符合本国手机号形态：11 位 `1[3-9]xxxxxxxxx`，或带 86 前缀的同形态 13 位；
    /// 3. 用空格 / 连字符分组书写（如 `010 8888 8888`、`415-555-2671`）。
    ///
    /// 反例（都该被挡下）：`123456789`（QQ 号）、`1234567890123`（序列号）、
    /// `2026-09-30`（日期）、`192.168.1.1`（IP）。
    private static func looksLikePhoneNumber(_ raw: String, digits: String) -> Bool {
        if hasInternationalPrefix(raw), (10...15).contains(digits.count) { return true }
        if isMainlandMobile(digits) { return true }
        if digits.count == 13, digits.hasPrefix("86"),
           isMainlandMobile(String(digits.dropFirst(2))) {
            return true
        }

        // 分组写法：必须有空格或连字符；点号留给 IP 与小数，不参与判定
        guard raw.contains(" ") || raw.contains("-") || raw.contains("\u{00A0}"),
              !raw.contains("."),
              (8...13).contains(digits.count) else { return false }
        return !isISODate(raw)
    }

    private static func hasInternationalPrefix(_ raw: String) -> Bool {
        raw.hasPrefix("+") || raw.hasPrefix("00")
    }

    /// 中国大陆手机号：11 位且以 `1[3-9]` 开头
    private static func isMainlandMobile(_ digits: String) -> Bool {
        guard digits.count == 11, digits.hasPrefix("1") else { return false }
        guard let second = digits.dropFirst().first?.wholeNumberValue else { return false }
        return (3...9).contains(second)
    }

    /// `2026-09-30` 这类日期写法，备注里很常见，不能当号码
    private static func isISODate(_ raw: String) -> Bool {
        let parts = raw.split(separator: "-")
        guard parts.count == 3 else { return false }
        return parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
    }

    /// 手机号匹配：完全相等，或一方是另一方的后缀（覆盖 +86 与 11 位本地写法）
    ///
    /// 长度差限制在国家码长度以内（最长 3 位），避免把两个本不相同的短号码合并。
    /// 宁可宽松：在“换号风险评估”场景里，漏报一条依赖比多报一条更危险。
    static func phoneKeyMatches(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count >= 7, rhs.count >= 7 else { return false }
        guard abs(lhs.count - rhs.count) <= 3 else { return false }
        return lhs == rhs || lhs.hasSuffix(rhs) || rhs.hasSuffix(lhs)
    }

    // MARK: - 内部索引

    /// 单条条目的联系方式指纹：一次构建，供所有候选复用
    private struct EntryIdentityIndex {
        let entry: PasswordEntry
        /// 归一化键 → 用途集合（不含文本提及）
        var rolesByKey: [String: Set<IdentityRole>] = [:]
        /// 归一化键 → 原始写法
        var rawByKey: [String: String] = [:]
        /// 归一化键 → 命中的 2FA 类型
        var twoFactorTypesByKey: [String: Set<TwoFactorType>] = [:]
        /// 本条目出现过的手机号键，用于国家码写法不同时的近似匹配
        var phoneKeys: Set<String> = []
        /// 备注 / 自定义字段中提到的手机号
        var mentionPhoneKeys: Set<String> = []
        /// 备注 / 自定义字段中提到的邮箱
        var mentionEmailKeys: Set<String> = []
    }

    private static func buildIndex(for entry: PasswordEntry) -> EntryIdentityIndex {
        var index = EntryIdentityIndex(entry: entry)

        func registerKey(_ key: String, kind: IdentityKind, role: IdentityRole, raw: String, twoFactorType: TwoFactorType? = nil) {
            index.rolesByKey[key, default: []].insert(role)
            if kind == .phone { index.phoneKeys.insert(key) }
            if let twoFactorType {
                index.twoFactorTypesByKey[key, default: []].insert(twoFactorType)
            }
            if index.rawByKey[key] == nil {
                index.rawByKey[key] = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        func register(_ raw: String?, _ role: IdentityRole, phoneEvidence: PhoneEvidence) {
            guard let raw, let (kind, key) = detect(raw, phoneEvidence: phoneEvidence) else { return }
            registerKey(key, kind: kind, role: role, raw: raw)
        }

        // 登录名：很多站点直接用邮箱或手机号登录。
        // 但用户名里的纯数字更可能是 QQ 号 / 学号 / 工号，只有“像手机号”时才认。
        register(entry.username, .login, phoneEvidence: .inferred)
        // 邮箱字段本该只放邮箱，出现纯数字属于填错字段，同样按推断处理
        register(entry.bundleEmailAddress, .contact, phoneEvidence: .inferred)
        // 手机号字段语义明确，宽松判定
        register(entry.bundlePhoneNumber, .contact, phoneEvidence: .explicit)

        // 明确的密码重置 / 找回通道
        if entry.isPasswordResetEmail {
            register(entry.bundleEmailAddress, .recovery, phoneEvidence: .inferred)
        }
        if entry.isPasswordResetPhone {
            register(entry.bundlePhoneNumber, .recovery, phoneEvidence: .explicit)
        }

        // 短信 / 邮件验证码的接收端
        for config in entry.twoFactorConfigs ?? [] where config.isEnabled {
            guard config.type == .sms || config.type == .email,
                  let bound = config.boundValue,
                  let (kind, key) = detect(bound, phoneEvidence: phoneEvidence(for: config.type))
            else { continue }
            guard kind == (config.type == .sms ? .phone : .email) else { continue }
            registerKey(key, kind: kind, role: .twoFactor, raw: bound, twoFactorType: config.type)
        }

        // 第三方登录绑定的账号：可能是昵称 / openid，只能按内容推断
        if let bound = entry.oAuthProvider?.boundValue,
           let (kind, key) = detect(bound, phoneEvidence: .inferred) {
            registerKey(key, kind: kind, role: .oauth, raw: bound)
        }

        // 备注与自定义字段中的文本提及
        var freeText = entry.notes ?? ""
        for field in entry.customFields ?? [] {
            freeText += " " + field.name + " " + field.value
        }
        if !freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let (phones, emails) = extractMentions(from: freeText)
            index.mentionPhoneKeys = phones
            index.mentionEmailKeys = emails
        }

        return index
    }

    /// 自由文本切词用的分隔符（邮箱抽取用）
    private static let mentionSeparators = CharacterSet(
        charactersIn: " \n\r\t,;:()[]{}<>\"'|/\\，；：（）")

    /// 自由文本中“像号码”的片段：以数字或 `+` 开头，中间允许号码常见的分隔符，
    /// 前后不允许与字母 / 数字粘连，避免把 `SN13800138000` 里的数字算成一个号码
    private static let phoneCandidateRegex = try? NSRegularExpression(
        pattern: "(?<![0-9A-Za-z])\\+?[0-9][0-9\\s\\-().*\u{00A0}]{5,22}[0-9](?![0-9A-Za-z])")

    /// 从自由文本中抽取可能的手机号与邮箱（尽力而为，用于低风险的“文本提及”提示）
    ///
    /// 手机号必须在整段文本里先找出“像号码”的片段再校验：按分隔符切词会把
    /// `+86 138 0013 8000` 切成三段；判定一律走 `.inferred` 严格度，
    /// 让序列号、QQ 号、订单号、日期这些纯数字串不要变成“提到过的手机号”。
    private static func extractMentions(from text: String) -> (phones: Set<String>, emails: Set<String>) {
        var phones: Set<String> = []
        var emails: Set<String> = []

        if let regex = phoneCandidateRegex {
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: text) else { continue }
                if let key = normalizedPhone(String(text[range]), evidence: .inferred) {
                    phones.insert(key)
                }
            }
        }

        for token in text.components(separatedBy: mentionSeparators) {
            guard let key = normalizedEmail(token) else { continue }
            emails.insert(key)
        }

        return (phones, emails)
    }

    /// 2FA 绑定值的识别严格度：短信接收端就是手机号字段的延伸，邮件同理
    private static func phoneEvidence(for type: TwoFactorType) -> PhoneEvidence {
        type == .sms ? .explicit : .inferred
    }

    // MARK: - 汇总

    private static func collectUsages(
        in indexes: [EntryIdentityIndex],
        key: String,
        kind: IdentityKind
    ) -> [IdentityUsage] {
        var usages: [IdentityUsage] = []

        for index in indexes {
            var roles = index.rolesByKey[key] ?? []
            var types = index.twoFactorTypesByKey[key] ?? []

            // 手机号写法差异（是否带国家码）时退化为近似匹配，避免漏掉依赖
            if roles.isEmpty, kind == .phone {
                for candidate in index.phoneKeys where Self.phoneKeyMatches(candidate, key) {
                    roles.formUnion(index.rolesByKey[candidate] ?? [])
                    types.formUnion(index.twoFactorTypesByKey[candidate] ?? [])
                }
            }

            let mentioned: Bool
            switch kind {
            case .phone:
                mentioned = index.mentionPhoneKeys.contains { phoneKeyMatches($0, key) }
            case .email:
                mentioned = index.mentionEmailKeys.contains(key)
            }
            if mentioned {
                roles.insert(.mention)
            }
            guard !roles.isEmpty else { continue }

            let sortedTypes = types.sorted { $0.rawValue < $1.rawValue }
            usages.append(
                IdentityUsage(
                    entryID: index.entry.id,
                    siteName: index.entry.siteName,
                    username: index.entry.username,
                    roles: roles,
                    twoFactorTypes: sortedTypes,
                    risk: risk(for: roles, entry: index.entry, key: key, kind: kind)
                )
            )
        }

        return usages.sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk > rhs.risk }
            return lhs.siteName.localizedCaseInsensitiveCompare(rhs.siteName) == .orderedAscending
        }
    }

    /// 风险判定：以“失去该联系方式后还能不能找回账户”为核心
    ///
    /// 历史说明：早期版本对 `entry.accountStatus == .closed || .inactive` 的 login/contact
    /// 用途降级为 low，但该字段没有对应的 UI 编辑入口（仅在数据层透传），
    /// 导致这条降级路径永远走不到，反而误导用户相信账户停用就安全。
    /// 待后续补上"标记账户已停用"入口后，再恢复此分支。
    private static func risk(
        for roles: Set<IdentityRole>,
        entry: PasswordEntry,
        key: String,
        kind: IdentityKind
    ) -> IdentityRiskLevel {
        if roles.contains(.recovery) {
            return hasAlternativeRecovery(entry: entry, key: key, kind: kind) ? .high : .critical
        }
        if roles.contains(.twoFactor) || roles.contains(.oauth) {
            return .high
        }
        if roles.contains(.login) || roles.contains(.contact) {
            return .medium
        }
        return .low
    }

    /// 是否存在“除本标识符以外”的找回通道
    /// 只有明确的替代方式才算，无法确认的一律按“没有”处理，避免把致命依赖降级
    private static func hasAlternativeRecovery(
        entry: PasswordEntry,
        key: String,
        kind: IdentityKind
    ) -> Bool {
        // 用户明确标记了已开启 2FA（即使没有具体配置，也说明存在额外因素）
        if entry.has2FA { return true }
        if entry.oAuthProvider != nil { return true }

        for config in entry.twoFactorConfigs ?? [] where config.isEnabled {
            // 与手机号 / 邮箱无关的 2FA（TOTP、推送、硬件密钥）天然不受换号影响
            if config.type != .sms && config.type != .email { return true }
            // 短信 / 邮件 2FA：绑定值必须不是本标识符，才算另一条通道
            if let bound = config.boundValue,
               let (_, boundKey) = detect(bound, phoneEvidence: phoneEvidence(for: config.type)),
               boundKey != key {
                return true
            }
        }

        // 另一种联系方式仍可用
        switch kind {
        case .phone:
            if let other = entry.bundleEmailAddress,
               let (_, otherKey) = detect(other, phoneEvidence: .inferred),
               otherKey != key {
                return true
            }
        case .email:
            if let other = entry.bundlePhoneNumber,
               let (_, otherKey) = detect(other, phoneEvidence: .explicit),
               otherKey != key {
                return true
            }
        }
        return false
    }

    private static func detectKind(of key: String) -> IdentityKind {
        key.contains("@") ? .email : .phone
    }

    /// 在已有候选中找出与 key 等价的键（手机号允许国家码差异）
    /// - Returns: 已存在的代表键；nil 表示这是一个新的联系方式
    private static func resolvedKey(
        for key: String,
        in candidates: [String: (kind: IdentityKind, raw: String)]
    ) -> String? {
        if candidates[key] != nil { return key }
        guard detectKind(of: key) == .phone else { return nil }
        for existing in candidates.keys where detectKind(of: existing) == .phone {
            if phoneKeyMatches(existing, key) { return existing }
        }
        return nil
    }

    private static func sorted(_ reports: [IdentityReport]) -> [IdentityReport] {
        reports.sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk > rhs.risk }
            if lhs.usages.count != rhs.usages.count { return lhs.usages.count > rhs.usages.count }
            return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
        }
    }
}
