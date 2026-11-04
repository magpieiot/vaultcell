import Foundation

@MainActor
final class TwoFactorService: ObservableObject {
    init() {}

    func calculateAudit(for entries: [PasswordEntry]) -> TwoFactorAudit {
        let configs = entries.flatMap { entry in
            (entry.twoFactorConfigs ?? []).map { (entry.id, $0) }
        }

        guard !configs.isEmpty else {
            return TwoFactorAudit(
                id: UUID(),
                total2FA: 0,
                verified2FA: 0,
                unverified2FA: 0,
                securityScore: 0,
                typeDistribution: [:],
                risks: [],
                suggestions: [AppLocale.string("No 2FA configuration found. Enable TOTP or hardware keys on important accounts first.")]
            )
        }

        let total2FA = configs.count
        let verified2FA = configs.filter { $0.1.lastVerifiedAt != nil }.count
        let unverified2FA = total2FA - verified2FA
        let enabledConfigs = configs.filter { $0.1.isEnabled }
        let recommendedConfigs = enabledConfigs.filter { $0.1.type.isRecommended }

        let typeDistribution = Dictionary(grouping: configs.map(\.1.type), by: { $0 })
            .mapValues(\.count)

        let verificationScore = Int((Double(verified2FA) / Double(total2FA)) * 45.0)
        let recommendationScore = Int((Double(recommendedConfigs.count) / Double(total2FA)) * 35.0)
        let enabledScore = Int((Double(enabledConfigs.count) / Double(total2FA)) * 20.0)
        let securityScore = min(100, verificationScore + recommendationScore + enabledScore)

        var risks: [SecurityRisk] = []
        for (entryID, config) in configs where !config.isEnabled {
            risks.append(
                SecurityRisk(
                    id: UUID(),
                    severity: .medium,
                    description: AppLocale.string("\(config.type.rawValue) is configured but disabled."),
                    affectedEntryId: entryID,
                    recommendation: AppLocale.string("Enable it again or remove the stale configuration.")
                )
            )
        }

        for (entryID, config) in enabledConfigs where config.lastVerifiedAt == nil {
            risks.append(
                SecurityRisk(
                    id: UUID(),
                    severity: .high,
                    description: AppLocale.string("\(config.type.rawValue) has never been verified."),
                    affectedEntryId: entryID,
                    recommendation: AppLocale.string("Complete one verification cycle and record the verified time.")
                )
            )
        }

        for (entryID, config) in enabledConfigs where !config.type.isRecommended {
            risks.append(
                SecurityRisk(
                    id: UUID(),
                    severity: .medium,
                    description: AppLocale.string("\(config.type.rawValue) is weaker than TOTP or hardware keys."),
                    affectedEntryId: entryID,
                    recommendation: AppLocale.string("Prefer TOTP or hardware-based 2FA for stronger protection.")
                )
            )
        }

        var suggestions: [String] = []
        if verified2FA < total2FA {
            suggestions.append(AppLocale.string("Verify all enabled 2FA methods so recovery and rotation remain reliable."))
        }
        if recommendedConfigs.count < total2FA {
            suggestions.append(AppLocale.string("Migrate SMS and email codes to TOTP or hardware keys where possible."))
        }
        if enabledConfigs.count < total2FA {
            suggestions.append(AppLocale.string("Remove disabled 2FA entries or re-enable the ones still in use."))
        }

        return TwoFactorAudit(
            id: UUID(),
            total2FA: total2FA,
            verified2FA: verified2FA,
            unverified2FA: unverified2FA,
            securityScore: securityScore,
            typeDistribution: typeDistribution,
            risks: risks,
            suggestions: suggestions
        )
    }
}
