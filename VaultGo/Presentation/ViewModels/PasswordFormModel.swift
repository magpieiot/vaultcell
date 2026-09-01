//
//  PasswordFormModel.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/28.
//

import SwiftUI

@MainActor
final class PasswordFormModel: ObservableObject {
    @Published var siteName = ""
    @Published var siteURL: String?
    @Published var username = ""
    @Published var password = ""
    @Published var bundlePhoneNumber: String?
    @Published var bundleEmailAddress: String?
    @Published var notes : String?
    @Published var categoryID: UUID = PasswordCategory.systemDefaults[0].id
    @Published var isFavorite = false
    @Published var isPasswordResetEmail = false
    @Published var isPasswordResetPhone = false
    @Published var has2FA = false
    @Published var twoFactorConfigs: [TwoFactorConfig]?
    @Published var oAuthProvider: OAuthProviderConfig?
    @Published var customFields: [CustomField]?
    @Published var tagSelection: [String]?
    // 图标远程地址（来自建议列表的 App Store 应用图标），保存后写入 PasswordEntry.icon
    @Published var icon: String?
    @Published var isEnabledNextButton = false

    var onSave: ((PasswordEntry) -> Void)?

    func updateNextButton() {
        let trimmedSiteName = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        isEnabledNextButton = !trimmedSiteName.isEmpty
            && !trimmedUsername.isEmpty
            && !trimmedPassword.isEmpty
    }

    func triggerSave() {
        onSave?(buildDraftEntry())
    }

    func buildDraftEntry() -> PasswordEntry {
        let trimmedSiteURL = (siteURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = (bundlePhoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = (bundleEmailAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return PasswordEntry(
            siteName: siteName.trimmingCharacters(in: .whitespacesAndNewlines),
            siteURL: trimmedSiteURL.isEmpty ? nil : trimmedSiteURL,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.trimmingCharacters(in: .whitespacesAndNewlines),
            oAuthProvider: oAuthProvider,
            bundlePhoneNumber: trimmedPhone.isEmpty ? nil : trimmedPhone,
            bundleEmailAddress: trimmedEmail.isEmpty ? nil : trimmedEmail,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            categoryID: categoryID,
            tags: tagSelection ?? [],
            isFavorite: isFavorite,
            isPasswordResetEmail: isPasswordResetEmail,
            isPasswordResetPhone: isPasswordResetPhone,
            has2FA: has2FA,
            customFields: (customFields?.isEmpty ?? true) ? nil : customFields,
            isSynced: false,
            icon: icon,
            twoFactorConfigs: twoFactorConfigs
        )
    }
}
