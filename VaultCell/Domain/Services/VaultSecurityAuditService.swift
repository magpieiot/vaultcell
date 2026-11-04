import Foundation

/// 失分分类
///
/// 与“为何被扣分”里的每一张卡片一一对应。分类标识有两个用途：
/// 1. 作为卡片下钻到具体条目的查询键（见 `VaultSecurityAudit.entryIDs(for:)`）；
/// 2. 作为展示开关的判断依据（例如“已泄露”默认不展示，见 `VaultKey.showCompromisedInScoreReasons`）。
enum VaultScoreIssueKind: String, CaseIterable, Hashable, Identifiable {
    case reusedPasswords
    case compromised
    case missing2FA
    case stalePassword
    case lowScore

    var id: String { rawValue }
}

/// 安全建议
///
/// `kind` 把建议与失分分类绑定，View 可据此按展示开关过滤（如"已泄露"默认不展示），
/// 也为后续"点击建议下钻到该分类的条目列表"留出入口。没有对应分类的建议 `kind` 为 nil。
struct VaultSecuritySuggestion: Identifiable, Hashable {
    let kind: VaultScoreIssueKind?
    let text: String

    var id: String { text }
}

struct VaultSecurityAudit: Equatable {
    let vaultScore: Int
    let entryScores: [UUID: Int]
    let entryIssues: [UUID: [String]]
    let duplicateEntriesCount: Int
    let compromisedEntriesCount: Int
    let weakEntriesCount: Int
    let no2FACount: Int
    let staleEntriesCount: Int
    /// 通过 OAuth 登录、安全分继承自源账户条目的条目数
    let oauthEntriesCount: Int
    /// 各失分分类命中的条目 ID
    /// 与上面的计数在 Pass 2 的同一分支内收集，保证卡片上的数量与下钻列表条数永远一致。
    let issueEntryIDs: [VaultScoreIssueKind: [UUID]]
    let suggestions: [VaultSecuritySuggestion]

    /// 某一失分分类命中的条目 ID
    func entryIDs(for kind: VaultScoreIssueKind) -> [UUID] {
        issueEntryIDs[kind] ?? []
    }
}

struct VaultSecurityAuditService {
    /// 参与评分的最少密码条目数：
    /// 条目太少时加权平均出来的库级分数没有参考意义，此时不评分、也不展示安全分入口。
    static let minimumEntriesForScore = 5

    func calculate(entries: [PasswordEntry], now: Date = Date()) -> VaultSecurityAudit {
        guard !entries.isEmpty else {
            return VaultSecurityAudit(
                vaultScore: 100,
                entryScores: [:],
                entryIssues: [:],
                duplicateEntriesCount: 0,
                compromisedEntriesCount: 0,
                weakEntriesCount: 0,
                no2FACount: 0,
                staleEntriesCount: 0,
                oauthEntriesCount: 0,
                issueEntryIDs: [:],
                suggestions: []
            )
        }

        let duplicateMap = buildDuplicateMap(entries: entries)

        // 源条目候选池：
        // - 普通条目（无 OAuth）
        // - “凭据源账户”型 OAuth 条目（boundValue 等于自身登录名，如“Google 账户”条目）
        // 两者都拥有独立凭据，可被 OAuth 衍生条目继承，避免递归继承。
        let sourceCandidates = entries.filter { $0.oAuthProvider == nil || isSelfContainedOAuthEntry($0) }

        // Pass 1：计算全部条目的四维基础分。
        // 衍生型 OAuth 条目的基础分仅用于“找不到源条目”时的降级回退。
        var baseScores: [UUID: Int] = [:]
        for entry in entries {
            baseScores[entry.id] = score(entry: entry, duplicateMap: duplicateMap, now: now)
        }

        var entryScores: [UUID: Int] = [:]
        var entryIssues: [UUID: [String]] = [:]

        var duplicateEntriesCount = 0
        var compromisedEntriesCount = 0
        var weakEntriesCount = 0
        var staleEntriesCount = 0
        var no2FACount = 0
        var oauthEntriesCount = 0
        var verifiedRecommended2FACount = 0
        var issueEntryIDs: [VaultScoreIssueKind: [UUID]] = [:]

        // Pass 2：确定最终得分与问题清单。判定顺序：
        // 1) OAuth 条目优先在库中查找源账户条目（排除自身）→ 继承其安全分；
        // 2) 找不到源且 boundValue 等于自身登录名 → “凭据源账户”型条目，按自身凭据评分；
        // 3) 其余 → 降级为自身四维分并提示源凭据未入库。
        // 衍生型 OAuth 条目不参与密码类统计；普通条目与源账户型条目参与。
        for entry in entries {
            var entryScore = baseScores[entry.id] ?? 0
            var isDerivedOAuth = false
            var inheritsFromSource = false

            if let oauth = entry.oAuthProvider {
                if let source = findOAuthSourceEntry(
                    for: oauth, in: sourceCandidates, excluding: entry.id, baseScores: baseScores
                ) {
                    isDerivedOAuth = true
                    inheritsFromSource = true
                    entryScore = baseScores[source.id] ?? entryScore
                } else if !isSelfContainedOAuthEntry(entry) {
                    isDerivedOAuth = true
                }
            }

            if isDerivedOAuth {
                oauthEntriesCount += 1
            } else {
                if duplicateMap[normalizePassword(entry.password), default: 0] > 1 {
                    duplicateEntriesCount += 1
                    issueEntryIDs[.reusedPasswords, default: []].append(entry.id)
                }
                if daysBetween(entry.passwordChangedAt ?? entry.updatedAt ?? now, now) > 365 {
                    staleEntriesCount += 1
                    issueEntryIDs[.stalePassword, default: []].append(entry.id)
                }
            }

            var entryIssueList = issues(
                entry: entry, duplicateMap: duplicateMap, now: now, inheritsScore: inheritsFromSource)
            if let oauth = entry.oAuthProvider, !inheritsFromSource, !isSelfContainedOAuthEntry(entry) {
                entryIssueList.append(
                    String(
                        format:
                            AppLocale.string("OAuth source entry for %@ (%@) was not found in the vault; scored with fallback rules."
                            ),
                        oauth.provider ?? AppLocale.string("Unknown"),
                        oauth.boundValue ?? AppLocale.string("Unknown")
                    )
                )
            }

            entryScores[entry.id] = entryScore
            entryIssues[entry.id] = entryIssueList

            if entryScore < 50 {
                weakEntriesCount += 1
                issueEntryIDs[.lowScore, default: []].append(entry.id)
            }
            if entry.breachStatus == .compromised {
                compromisedEntriesCount += 1
                issueEntryIDs[.compromised, default: []].append(entry.id)
            }
            if !entry.has2FA && !(entry.twoFactorConfigs ?? []).contains(where: { $0.isEnabled }) {
                no2FACount += 1
                issueEntryIDs[.missing2FA, default: []].append(entry.id)
            }
            if (entry.twoFactorConfigs ?? []).contains(where: { $0.isEnabled && $0.lastVerifiedAt != nil && $0.type.isRecommended }) {
                verifiedRecommended2FACount += 1
            }
        }

        let baseScore = weightedAverage(entries: entries, entryScores: entryScores)
        let finalScore = applyGlobalAdjustments(
            base: baseScore,
            entries: entries,
            duplicateEntriesCount: duplicateEntriesCount,
            compromisedEntriesCount: compromisedEntriesCount,
            staleEntriesCount: staleEntriesCount,
            verifiedRecommended2FACount: verifiedRecommended2FACount
        )

        return VaultSecurityAudit(
            vaultScore: finalScore,
            entryScores: entryScores,
            entryIssues: entryIssues,
            duplicateEntriesCount: duplicateEntriesCount,
            compromisedEntriesCount: compromisedEntriesCount,
            weakEntriesCount: weakEntriesCount,
            no2FACount: no2FACount,
            staleEntriesCount: staleEntriesCount,
            oauthEntriesCount: oauthEntriesCount,
            issueEntryIDs: issueEntryIDs,
            suggestions: buildSuggestions(
                duplicateEntriesCount: duplicateEntriesCount,
                compromisedEntriesCount: compromisedEntriesCount,
                no2FACount: no2FACount,
                staleEntriesCount: staleEntriesCount,
                weakEntriesCount: weakEntriesCount,
                oauthEntriesCount: oauthEntriesCount
            )
        )
    }
}

private extension VaultSecurityAuditService {
    func score(entry: PasswordEntry, duplicateMap: [String: Int], now: Date) -> Int {
        let intrinsic = intrinsicScore(entry: entry)
        let exposure = exposureScore(entry: entry, duplicateMap: duplicateMap)
        let protection = protectionScore(entry: entry)
        let freshness = freshnessScore(entry: entry, now: now)

        var score = intrinsic + exposure + protection + freshness

        // 短密码即使其他维度得分高，也不应超过安全及格线
        if entry.password.count < 8 {
            score = min(score, 40)
        }

        // 泄露检测功能尚未完成，暂不参与评分：不设泄露封顶
        // if entry.breachStatus == .compromised { score = min(score, 25) }

        // 多处复用（≥3 条）时的封顶值从 55 放宽到 70，避免长随机密码因复用被一次性打成不及格
        let dupCount = duplicateMap[normalizePassword(entry.password), default: 0]
        if dupCount >= 3 {
            score = min(score, 70)
        }

        return clamp(score, 0, 100)
    }

    func issues(
        entry: PasswordEntry,
        duplicateMap: [String: Int],
        now: Date,
        inheritsScore: Bool = false
    ) -> [String] {
        var items: [String] = []

        // OAuth 衍生条目（已继承源账户分数）没有独立密码，跳过密码类检查。
        if inheritsScore {
            if let oauth = entry.oAuthProvider {
                items.append(
                    String(
                        format:
                            AppLocale.string("This account signs in via OAuth (%@ / %@); its security score is inherited from the source entry."
                            ),
                        oauth.provider ?? AppLocale.string("Unknown"),
                        oauth.boundValue ?? AppLocale.string("Unknown")
                    )
                )
            }
            return items
        }

        let dupCount = duplicateMap[normalizePassword(entry.password), default: 0]
        if dupCount > 1 {
            items.append(String(format: AppLocale.string("Password is reused across %lld entries."), dupCount))
        }

        // 泄露检测功能尚未完成，暂不输出泄露类问题
        //（原 "Password is marked as compromised." / "Breach status is unknown."）

        let enabledConfigs = (entry.twoFactorConfigs ?? []).filter { $0.isEnabled }
        if !entry.has2FA && enabledConfigs.isEmpty {
            items.append(AppLocale.string("2FA is not enabled."))
        } else if let best = bestTwoFactorConfig(enabledConfigs) {
            if best.type == .sms {
                items.append(AppLocale.string("2FA uses SMS, consider switching to an authenticator app."))
            }
            if best.lastVerifiedAt == nil {
                items.append(AppLocale.string("2FA is not verified yet."))
            }
        }

        let changedAt = entry.passwordChangedAt ?? entry.updatedAt ?? now
        let ageDays = daysBetween(changedAt, now)
        if ageDays > 365 {
            items.append(AppLocale.string("Password has not been changed for over a year."))
        }

        if entry.password.count < 12 {
            items.append(AppLocale.string("Password is shorter than 12 characters."))
        }

        let charset = charsetFlags(entry.password)
        if !(charset.hasLower && charset.hasUpper && charset.hasDigit && charset.hasSymbol) {
            items.append(AppLocale.string("Password does not use all character types (upper/lower/digit/symbol)."))
        }

        return items
    }

    func intrinsicScore(entry: PasswordEntry) -> Int {
        let password = entry.password
        let lengthScore = scoreForLength(password.count)
        let charsetScore = scoreForCharset(password)
        let uniqueRatioScore = scoreForUniqueRatio(password)
        let patternPenalty = penaltyForPatterns(password: password, entry: entry)

        return clamp(lengthScore + charsetScore + uniqueRatioScore + patternPenalty, 0, 45)
    }

    func exposureScore(entry: PasswordEntry, duplicateMap: [String: Int]) -> Int {
        let normalized = normalizePassword(entry.password)
        let count = duplicateMap[normalized, default: 1]

        // 重复密码扣分已放宽：仅复用一次影响很小，多处复用也不再扣光该维度
        let duplicateScore: Int
        switch count {
        case 1: duplicateScore = 8
        case 2: duplicateScore = 5
        default: duplicateScore = 2
        }

        // 泄露检测功能尚未完成：该维度暂按满分计入，不随 breachStatus 变化，
        // 待泄露检测上线后恢复下面的分级逻辑。
        // let breachScore: Int
        // switch entry.breachStatus ?? .unknown {
        // case .safe: breachScore = 12
        // case .unknown: breachScore = 4
        // case .compromised: breachScore = 0
        // }
        let breachScore = 12

        return duplicateScore + breachScore
    }

    /// 未启用 2FA 时的基础分。
    /// 之前直接归零（满分 20 全扣），惩罚过重；现在保留一部分，
    /// 使“未启用 2FA”相对“已验证 TOTP”的差距从 20 分收敛到 14 分。
    private static let noTwoFactorBasePoints = 6

    func protectionScore(entry: PasswordEntry) -> Int {
        let enabledConfigs = (entry.twoFactorConfigs ?? []).filter { $0.isEnabled }
        guard !enabledConfigs.isEmpty || entry.has2FA else { return Self.noTwoFactorBasePoints }

        var base = 8

        if let best = bestTwoFactorConfig(enabledConfigs) {
            base += pointsForTwoFactorType(best.type)
            if best.lastVerifiedAt == nil { base -= 3 }
        } else {
            base += 3
        }

        return clamp(base, 0, 20)
    }

    func freshnessScore(entry: PasswordEntry, now: Date) -> Int {
        let changedAt = entry.passwordChangedAt ?? entry.updatedAt ?? now
        let days = daysBetween(changedAt, now)
        let changedScore: Int
        switch days {
        case ..<0: changedScore = 6
        case 0...90: changedScore = 10
        case 91...180: changedScore = 8
        case 181...365: changedScore = 5
        default: changedScore = 1
        }

        let expireScore: Int
        if let expiresAt = entry.expiresAt {
            let daysToExpire = daysBetween(now, expiresAt)
            switch daysToExpire {
            case ..<0: expireScore = 0
            case 0...30: expireScore = 2
            default: expireScore = 5
            }
        } else {
            expireScore = 5
        }

        return changedScore + expireScore
    }

    func weightedAverage(entries: [PasswordEntry], entryScores: [UUID: Int]) -> Double {
        var numerator: Double = 0
        var denominator: Double = 0

        for entry in entries {
            guard let score = entryScores[entry.id] else { continue }
            let w = weight(entry: entry)
            numerator += Double(score) * w
            denominator += w
        }

        guard denominator > 0 else { return 100 }
        return numerator / denominator
    }

    func applyGlobalAdjustments(
        base: Double,
        entries: [PasswordEntry],
        duplicateEntriesCount: Int,
        compromisedEntriesCount: Int,
        staleEntriesCount: Int,
        verifiedRecommended2FACount: Int
    ) -> Int {
        let total = Double(entries.count)
        guard total > 0 else { return 100 }

        let duplicateEntryRatio = Double(duplicateEntriesCount) / total
        let staleEntryRatio = Double(staleEntriesCount) / total
        let verifiedRecommended2FARatio = Double(verifiedRecommended2FACount) / total

        // 库级重复惩罚同样放宽：系数 20→14，上限 12→8
        let duplicatePenalty = min(8.0, duplicateEntryRatio * 14.0)
        // 泄露检测功能尚未完成：库级泄露惩罚暂置 0
        // let compromisedPenalty = min(20.0, Double(compromisedEntriesCount) / total * 35.0)
        let compromisedPenalty = 0.0
        let stalePenalty = min(8.0, staleEntryRatio * 12.0)
        let good2FABonus = min(5.0, verifiedRecommended2FARatio * 5.0)

        let adjusted = base - duplicatePenalty - compromisedPenalty - stalePenalty + good2FABonus
        return clamp(Int(adjusted.rounded()), 0, 100)
    }

    func buildSuggestions(
        duplicateEntriesCount: Int,
        compromisedEntriesCount: Int,
        no2FACount: Int,
        staleEntriesCount: Int,
        weakEntriesCount: Int,
        oauthEntriesCount: Int
    ) -> [VaultSecuritySuggestion] {
        var suggestions: [VaultSecuritySuggestion] = []

        if duplicateEntriesCount > 0 {
            suggestions.append(
                VaultSecuritySuggestion(
                    kind: .reusedPasswords,
                    text: String(
                        format: AppLocale.string("%lld entries reuse a password. Change them to unique passwords."),
                        duplicateEntriesCount
                    )
                )
            )
        }

        if compromisedEntriesCount > 0 {
            suggestions.append(
                VaultSecuritySuggestion(
                    kind: .compromised,
                    text: String(
                        format: AppLocale.string("%lld entries are marked as compromised. Change passwords immediately."),
                        compromisedEntriesCount
                    )
                )
            )
        }

        if no2FACount > 0 {
            suggestions.append(
                VaultSecuritySuggestion(
                    kind: .missing2FA,
                    text: String(
                        format: AppLocale.string("Enable 2FA on %lld entries to reduce takeover risk."),
                        no2FACount
                    )
                )
            )
        }

        if staleEntriesCount > 0 {
            suggestions.append(
                VaultSecuritySuggestion(
                    kind: .stalePassword,
                    text: String(
                        format: AppLocale.string("%lld entries have not changed passwords for over a year."),
                        staleEntriesCount
                    )
                )
            )
        }

        if weakEntriesCount > 0 {
            suggestions.append(
                VaultSecuritySuggestion(
                    kind: .lowScore,
                    text: String(
                        format: AppLocale.string("%lld entries have low scores. Consider upgrading them first."),
                        weakEntriesCount
                    )
                )
            )
        }

        if oauthEntriesCount > 0 {
            suggestions.append(
                VaultSecuritySuggestion(
                    kind: nil,
                    text: String(
                        format: AppLocale.string("%lld entries sign in via OAuth. Their security relies on the source accounts in the vault."),
                        oauthEntriesCount
                    )
                )
            )
        }

        return suggestions
    }
}

private extension VaultSecurityAuditService {
    /// 判断条目是否为“OAuth 凭据源账户”型：
    /// 其 OAuth 绑定值等于自身登录名（username / bundleEmailAddress），
    /// 说明该条目自己持有该凭据（如“Google 账户”条目），而非通过他人账户登录。
    /// 这类条目有独立密码与 2FA，按自身凭据评分，并可被 OAuth 衍生条目继承。
    func isSelfContainedOAuthEntry(_ entry: PasswordEntry) -> Bool {
        guard let oauth = entry.oAuthProvider,
              let bound = oauth.boundValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !bound.isEmpty else { return false }
        let ownValues = [entry.username, entry.bundleEmailAddress ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return ownValues.contains(bound)
    }

    /// 在候选条目中查找 OAuth 凭据对应的源账户条目。
    /// 匹配优先级：
    /// 1. 强匹配：站点与 provider 相关（siteName/siteURL 包含 provider）且绑定值匹配；
    /// 2. 弱匹配：仅绑定值匹配（username / bundleEmailAddress 等于 boundValue）。
    /// 多个命中时保守取基础分最低者（按最差情况估计）。
    /// `excluding` 用于排除条目自身，避免“自己继承自己”。
    func findOAuthSourceEntry(
        for oauth: OAuthProviderConfig,
        in candidates: [PasswordEntry],
        excluding selfID: UUID,
        baseScores: [UUID: Int]
    ) -> PasswordEntry? {
        let provider = (oauth.provider ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bound = oauth.boundValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !provider.isEmpty, let bound, !bound.isEmpty else { return nil }

        let boundMatches: (PasswordEntry) -> Bool = { entry in
            let values = [entry.username, entry.bundleEmailAddress ?? ""]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return values.contains(bound)
        }

        let providerMatches: (PasswordEntry) -> Bool = { entry in
            [entry.siteName, entry.siteURL ?? ""]
                .joined(separator: " ")
                .lowercased()
                .contains(provider)
        }

        let eligible = candidates.filter { $0.id != selfID }
        let strongMatches = eligible.filter { providerMatches($0) && boundMatches($0) }
        let pool = strongMatches.isEmpty ? eligible.filter(boundMatches) : strongMatches

        return pool.min { (baseScores[$0.id] ?? 0) < (baseScores[$1.id] ?? 0) }
    }

    func scoreForLength(_ length: Int) -> Int {
        switch length {
        case ..<8: return 0
        case 8...11: return 8
        case 12...15: return 14
        case 16...19: return 18
        default: return 20
        }
    }

    func scoreForCharset(_ password: String) -> Int {
        var score = 0
        let flags = charsetFlags(password)

        if flags.hasLower { score += 3 }
        if flags.hasUpper { score += 3 }
        if flags.hasDigit { score += 3 }
        if flags.hasSymbol { score += 3 }

        return min(score, 12)
    }

    /// 明确符号集合，避免空格、emoji、控制字符被错误计入 symbol。
    private static let symbolCharacterSet = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?/\\:`~\"")

    func charsetFlags(_ password: String) -> (hasLower: Bool, hasUpper: Bool, hasDigit: Bool, hasSymbol: Bool) {
        var hasLower = false
        var hasUpper = false
        var hasDigit = false
        var hasSymbol = false

        for ch in password.unicodeScalars {
            if CharacterSet.lowercaseLetters.contains(ch) { hasLower = true }
            else if CharacterSet.uppercaseLetters.contains(ch) { hasUpper = true }
            else if CharacterSet.decimalDigits.contains(ch) { hasDigit = true }
            else if Self.symbolCharacterSet.contains(ch) { hasSymbol = true }
        }

        return (hasLower, hasUpper, hasDigit, hasSymbol)
    }

    func scoreForUniqueRatio(_ password: String) -> Int {
        guard !password.isEmpty else { return 0 }
        let uniqueCount = Set(password).count
        let ratio = Double(uniqueCount) / Double(password.count)
        return clamp(Int((ratio * 8.0).rounded()), 0, 8)
    }

    func penaltyForPatterns(password: String, entry: PasswordEntry) -> Int {
        let lower = password.lowercased()

        var penalty = 0

        let tokens = (tokensFrom(entry.siteName) + tokensFrom(entry.username)).filter { $0.count >= 3 }
        if tokens.contains(where: { lower.contains($0) }) {
            penalty -= 4
        }

        if containsSequence(lower, minLength: 3) || containsQwertySequence(lower, minLength: 4) {
            penalty -= 4
        }

        if hasTripleRepeat(password) || hasRepeatedBigram(lower) {
            penalty -= 4
        }

        return max(penalty, -12)
    }

    func tokensFrom(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var tokens: [String] = []
        var current = ""

        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    func containsSequence(_ text: String, minLength: Int) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= minLength else { return false }

        var run = 1
        for i in 1..<scalars.count {
            let a = scalars[i - 1].value
            let b = scalars[i].value
            if b == a + 1 {
                run += 1
                if run >= minLength { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    func containsQwertySequence(_ text: String, minLength: Int) -> Bool {
        let keyboard = "qwertyuiopasdfghjklzxcvbnm"
        guard minLength <= keyboard.count else { return false }

        for i in 0...(keyboard.count - minLength) {
            let start = keyboard.index(keyboard.startIndex, offsetBy: i)
            let end = keyboard.index(start, offsetBy: minLength)
            let slice = String(keyboard[start..<end])
            if text.contains(slice) || text.contains(String(slice.reversed())) { return true }
        }

        return false
    }

    func hasTripleRepeat(_ password: String) -> Bool {
        let chars = Array(password)
        guard chars.count >= 3 else { return false }

        var run = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1] {
                run += 1
                if run >= 3 { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    func hasRepeatedBigram(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count >= 6 else { return false }

        for i in 0...(chars.count - 6) {
            let a0 = chars[i]
            let a1 = chars[i + 1]
            if chars[i + 2] == a0, chars[i + 3] == a1,
               chars[i + 4] == a0, chars[i + 5] == a1 {
                return true
            }
        }
        return false
    }

    func bestTwoFactorConfig(_ configs: [TwoFactorConfig]) -> TwoFactorConfig? {
        configs.max { a, b in
            a.type.securityLevel.rawValue < b.type.securityLevel.rawValue
        }
    }

    func pointsForTwoFactorType(_ type: TwoFactorType) -> Int {
        switch type.securityLevel {
        case .veryHigh: return 12
        case .high: return 10
        case .medium: return 6
        case .low: return 2
        }
    }

    func weight(entry: PasswordEntry) -> Double {
        var w: Double
        switch entry.accountStatus ?? .active {
        case .active: w = 1.0
        case .inactive: w = 0.7
        case .suspended: w = 0.5
        case .closed: w = 0.3
        }
        if entry.isFavorite { w += 0.15 }
        return w
    }

    func buildDuplicateMap(entries: [PasswordEntry]) -> [String: Int] {
        var map: [String: Int] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries {
            let key = normalizePassword(entry.password)
            map[key, default: 0] += 1
        }
        return map
    }

    func normalizePassword(_ password: String) -> String {
        password
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    func daysBetween(_ from: Date, _ to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }

    func clamp(_ value: Int, _ minValue: Int, _ maxValue: Int) -> Int {
        min(max(value, minValue), maxValue)
    }
}
