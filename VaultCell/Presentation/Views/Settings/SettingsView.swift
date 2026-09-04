/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SettingsView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import CoreData
import SwiftUI

/// 自动锁定时间间隔选项
enum AutoLockInterval: Double, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case sixtySeconds = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case never = 0

    var id: Double { rawValue }

    var localizedTitle: String {
        switch self {
        case .thirtySeconds: return String(localized: "30 Seconds")
        case .sixtySeconds: return String(localized: "60 Seconds")
        case .threeMinutes: return String(localized: "3 Minutes")
        case .fiveMinutes: return String(localized: "5 Minutes")
        case .never: return String(localized: "Never")
        }
    }
}

/// 剪贴板自动清理时间选项
enum ClipboardTimeout: Double, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case sixtySeconds = 60
    case twoMinutes = 120
    case never = 0

    var id: Double { rawValue }

    var localizedTitle: String {
        switch self {
        case .thirtySeconds: return String(localized: "30 Seconds")
        case .sixtySeconds: return String(localized: "60 Seconds")
        case .twoMinutes: return String(localized: "2 Minutes")
        case .never: return String(localized: "Never")
        }
    }
}

struct SettingsView: View {

    @AppStorage(VaultKey.biometricEnabled) private var biometricEnabled = true
    @AppStorage(VaultKey.autoLockInterval) private var autoLockInterval = 30.0
    @AppStorage(VaultKey.clipboardTimeout) private var clipboardTimeout = 60.0
    @AppStorage(VaultKey.allowSwipeDeleteInVaultList) private var allowSwipeDeleteInVaultList = true
    @State private var darkModeSelection = 0

    /// 自动锁定间隔：把 Double 存储值转换为枚举，供 Picker 使用
    private var autoLockIntervalBinding: Binding<AutoLockInterval> {
        Binding(
            get: { AutoLockInterval(rawValue: autoLockInterval) ?? .thirtySeconds },
            set: { autoLockInterval = $0.rawValue }
        )
    }

    /// 剪贴板清理时间：把 Double 存储值转换为枚举，供 Picker 使用
    private var clipboardTimeoutBinding: Binding<ClipboardTimeout> {
        Binding(
            get: { ClipboardTimeout(rawValue: clipboardTimeout) ?? .sixtySeconds },
            set: { clipboardTimeout = $0.rawValue }
        )
    }

    @State private var showingChangePassword = false
    @State private var isSeedingTestData = false
    @State private var showingLanguagePicker = false
    @State private var showingResetVerify = false
    @State private var showingTrash = false

    /// 设置页业务逻辑：导入 / 回收站计数 / 重置 / 弹窗状态
    @StateObject private var settingsVM = SettingsViewModel()

    @EnvironmentObject var viewModel: VaultListViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var safeNoteService: SafeNoteVaultService
    @EnvironmentObject var languageManager: AppLanguageManager

    private var passwordEntries: [PasswordEntry] {
        viewModel.items.compactMap {
            guard case .password(let entry) = $0 else { return nil }
            return entry
        }
    }

    var body: some View {
        NavigationStack {
            List {
                //accountHeaderSection
                securitySection
                generalSection
                dataManagementSection
                aboutSection
                developmentModeSection
                dangerSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(SettingsBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingChangePassword) {
                ChangeMasterPasswordView()
            }
            .sheet(isPresented: $showingLanguagePicker) {
                LanguagePickerView()
            }
            .sheet(isPresented: $showingResetVerify) {
                ResetVaultVerifyView { password in
                    await settingsVM.verifyAndReset(masterPassword: password)
                }
            }
            .sheet(
                isPresented: $showingTrash,
                onDismiss: {
                    // 回收站内容可能已被清空/恢复/删除，关闭后刷新数量徽标
                    Task { await settingsVM.loadTrashedCount() }
                }
            ) {
                TrashView()
            }
            .onAppear {
                // 注入共享服务并刷新回收站计数
                settingsVM.configure(
                    appState: appState,
                    vaultListViewModel: viewModel,
                    safeNoteService: safeNoteService
                )
                Task {
                    await settingsVM.loadTrashedCount()
                }
            }
        }
        // 确认/结果弹窗挂载在导航栈外层：若挂在导航栈内部，push 到
        // 数据管理等子页面后设置的 alert 会被子页面遮挡，
        // 直到回退到设置页才显示；挂外层可覆盖整个导航栈即时弹出
        .alert(
            settingsVM.alert?.title ?? "",
            isPresented: Binding(
                get: { settingsVM.alert != nil },
                set: { if !$0 { settingsVM.alert = nil } }
            ),
            presenting: settingsVM.alert
        ) { alert in
            switch alert {
            case .resetConfirm:
                Button(String(localized: "Reset"), role: .destructive) {
                    settingsVM.alert = nil
                    showingResetVerify = true
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            case .seedConfirm:
                Button(String(localized: "Generate")) {
                    Task { await seedTestPasswords() }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            case .resetFailed, .seedResult, .operationResult:
                Button(String(localized: "OK"), role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    /// 账户头部：品牌渐变图标，延续 Onboarding/认证页的品牌语言
    private var accountHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .primaryBrandColor, .secondaryBrandColor,
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: .primaryBrandColor.opacity(0.3), radius: 10, y: 6)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(String(localized: "VaultCell"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            //.padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    /// 安全设置
    private var securitySection: some View {
        Section("Security") {
            Button(action: {
                showingChangePassword = true
            }) {
                CustomLabel(
                    leadingIcon: "lock.fill", leadingIconColor: .primaryBrandColor,
                    trailingIcon: "chevron.right", text: "Change Master Password")
            }

            if BiometricService.shared.isBiometricAvailable {
                Toggle(isOn: $biometricEnabled) {
                    CustomLabel(
                        leadingIcon: BiometricService.shared.biometricType.iconName,
                        leadingIconColor: .primaryBrandColor, text: "Biometric Unlock")
                }
                .tint(.primaryBrandColor)
            }

            Picker(selection: autoLockIntervalBinding) {
                ForEach(AutoLockInterval.allCases) { interval in
                    Text(interval.localizedTitle).tag(interval)
                }
            } label: {
                CustomLabel(
                    leadingIcon: "clock.fill", leadingIconColor: .primaryBrandColor,
                    text: "Auto-Lock")
            }

            Picker(selection: clipboardTimeoutBinding) {
                ForEach(ClipboardTimeout.allCases) { timeout in
                    Text(timeout.localizedTitle).tag(timeout)
                }
            } label: {
                CustomLabel(
                    leadingIcon: "doc.on.clipboard", leadingIconColor: .primaryBrandColor,
                    text: "Clear Clipboard")
            }
        }
    }

    /// 数据管理入口：回收站、iCloud、导入/导出、测试库（子页承载）
    private var dataManagementSection: some View {
        Section {
            // 回收站入口（带数量徽标）
            Button {
                showingTrash = true
            } label: {
                HStack {
                    CustomLabel(
                        leadingIcon: "trash",
                        leadingIconColor: .errorColor,
                        text: "Trash"
                    )
                    Spacer()
                    Text("\(settingsVM.trashedCount)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(settingsVM.trashedCount > 0 ? .white : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                settingsVM.trashedCount > 0
                                    ? Color.errorColor.opacity(0.85) : Color.secondary.opacity(0.15)
                            )
                        )
                    Image(systemName: "chevron.right")
                        .foregroundColor(settingsVM.trashedCount > 0 ? .primary : Color.clear)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                }
            }
            .foregroundColor(.primary)

            NavigationLink {
                DataManagementView(settingsVM: settingsVM)
            } label: {
                CustomLabel(
                    leadingIcon: "externaldrive.fill", leadingIconColor: .secondaryBrandColor,
                    text: "Data Management")
            }
        }
    }

    /// 通用：外观、语言、字体与分类管理
    private var generalSection: some View {
        Section("General") {
            /*
            Toggle(isOn: $allowSwipeDeleteInVaultList) {
                CustomLabel(
                    leadingIcon: "hand.draw", leadingIconColor: .secondary,
                    text: "Swipe to Delete in Vault List")
            }
            .tint(.primaryBrandColor)
            */

            Picker(selection: $darkModeSelection) {
                Text("Light").tag(0)
                Text("Dark").tag(1)
                Text("Follow System").tag(2)
            } label: {
                CustomLabel(
                    leadingIcon: "moon.fill", leadingIconColor: .secondary, text: "Dark Mode")
            }

            Button {
                showingLanguagePicker = true
            } label: {
                HStack(spacing: 8) {
                    LanguageBadge(language: languageManager.current, size: 30)
                    Text("Language")
                        .font(.body)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(languageManager.current.nativeDisplayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: Text(String(localized: "Font Size"))) {
                CustomLabel(
                    leadingIcon: "textformat.size", leadingIconColor: .secondary, text: "Font Size")
            }

            NavigationLink(destination: CategoryManagementView(viewModel: viewModel)) {
                CustomLabel(
                    leadingIcon: "tag.fill", leadingIconColor: .secondaryBrandColor,
                    text: "Password Categories")
            }
        }
    }

    /// 关于入口：评分、帮助、隐私条款与版本信息（子页承载）
    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                CustomLabel(
                    leadingIcon: "info.circle", leadingIconColor: .secondary,
                    text: "About")
            }
        }
    }

    private var dangerSection: some View {
        Section {
            /*
            Button(action: {
                appState.logout()
            }) {
                CustomLabel(
                    leadingIcon: "person.crop.circle.badge.xmark", leadingIconColor: .errorColor,
                    trailingIcon: "chevron.right", text: "Sign Out"
                )
                .foregroundColor(.errorColor)
            }
            */

            Button(
                role: .destructive,
                action: {
                    settingsVM.alert = .resetConfirm
                }
            ) {
                CustomLabel(
                    leadingIcon: "trash", leadingIconColor: .errorColor,
                    trailingIcon: "chevron.right", text: "Reset Vault / Clear Keychain"
                )
                .foregroundColor(.errorColor)
            }
        } header: {
            Text("Danger Zone")
                .foregroundColor(.errorColor)
        } footer: {
            Text(
                String(
                    localized:
                        "Resetting will clear Keychain and local data. This action cannot be undone."
                )
            )
            .padding(.bottom, 80)
        }
    }

    private var developmentModeSection: some View {
        Section("Development Mode") {
            Toggle(isOn: $allowSwipeDeleteInVaultList) {
                CustomLabel(
                    leadingIcon: "hand.draw", leadingIconColor: .secondary,
                    text: "Swipe to Delete in Vault List")
            }
            .tint(.primaryBrandColor)
        }
    }

    private func seedTestPasswords() async {
        guard !isSeedingTestData else { return }

        if Self.hasSeededTestVault(passwords: passwordEntries) {
            settingsVM.alert = .seedResult(
                "The test vault already exists. No need to generate it again.")
            return
        }

        isSeedingTestData = true
        defer { isSeedingTestData = false }

        let repository: PasswordRepositoryProtocol = PasswordRepository()
        let tagRepository: TagRepositoryProtocol = TagRepository()

        // 确保系统预置标签存在
        try? await tagRepository.ensureDefaults()

        let seedEntries = Self.makeSeedEntries()

        // 收集所有唯一标签名，提前创建 CDTag 实体（分配差异化颜色）
        let allTagNames = Set(seedEntries.flatMap { $0.tags ?? [] })
        var tagSortOrder: Int32 = Int32(viewModel.tags.count)
        for name in allTagNames.sorted() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let existing = try? await tagRepository.fetchByName(trimmed)
            if existing == nil {
                let color = tagColor(for: trimmed)
                try? await tagRepository.create(
                    Tag(name: trimmed, hexColor: color, sortOrder: tagSortOrder)
                )
                tagSortOrder += 1
            }
        }

        let existingKeys = Set(
            passwordEntries.map { entry in
                SettingsViewModel.seedIdentity(siteName: entry.siteName, username: entry.username)
            }
        )

        var insertedCount = 0
        var skippedCount = 0
        var seenKeys = existingKeys

        for entry in seedEntries {
            let key = SettingsViewModel.seedIdentity(
                siteName: entry.siteName, username: entry.username)
            if seenKeys.contains(key) {
                skippedCount += 1
                continue
            }

            do {
                try await repository.save(entry)
                seenKeys.insert(key)
                insertedCount += 1
            } catch {
                await viewModel.loadItems()
                settingsVM.alert = .seedResult(
                    "Failed to generate test data: \(error.localizedDescription)")
                return
            }
        }

        await viewModel.loadItems()
        await viewModel.referenceData.loadTags()
        SettingsViewModel.setSeedTestVaultGenerated(true)

        // Seed pincodes
        let pincodeRepository = PincodeRepository()
        let seedPincodes = Self.makeSeedPincodes()
        var insertedPincodeCount = 0
        for entry in seedPincodes {
            do {
                try await pincodeRepository.save(entry)
                insertedPincodeCount += 1
            } catch {
                settingsVM.alert = .seedResult(
                    "Failed to generate pincode test data: \(error.localizedDescription)")
                return
            }
        }

        // Seed bankcards
        let bankcardRepository = BankcardRepository()
        let seedBankcards = Self.makeSeedBankcards()
        var insertedBankcardCount = 0
        for entry in seedBankcards {
            do {
                try await bankcardRepository.save(entry)
                insertedBankcardCount += 1
            } catch {
                settingsVM.alert = .seedResult(
                    "Failed to generate bankcard test data: \(error.localizedDescription)")
                return
            }
        }

        let request: NSFetchRequest<CDPasswordEntry> = CDPasswordEntry.fetchRequest()
        let storedCount = (try? CoreDataStack.shared.viewContext.count(for: request)) ?? 0

        settingsVM.alert = .seedResult(
            "Test vault generated: \(insertedCount) passwords, \(insertedPincodeCount) pincodes, \(insertedBankcardCount) bankcards added, \(skippedCount) duplicates skipped. \(storedCount) total passwords stored locally."
        )
    }

    private static let seedNotesMarker = "[VaultCell Seed]"

    private static func hasSeededTestVault(passwords: [PasswordEntry]) -> Bool {
        if SettingsViewModel.isSeedTestVaultGenerated() {
            return true
        }
        return passwords.contains { entry in
            (entry.notes?.contains(seedNotesMarker) ?? false)
                || (entry.tags?.contains("seed") ?? false)
        }
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
            return PasswordCategory.systemDefaults[2].id  // Work
        case "netflix", "disney", "spotify", "youtube", "douyin", "抖音", "豆瓣":
            return PasswordCategory.systemDefaults[4].id  // Media
        case "alipay", "支付宝":
            return PasswordCategory.systemDefaults[1].id  // Finance
        default:
            return PasswordCategory.systemDefaults[3].id  // Life（兜底）
        }
    }

    private static func makeFamousAppSeedEntry(_ app: AppTitle, usernameIndex: Int) -> PasswordEntry
    {
        let slug = seedSlug(app.title)
        let suffix = usernameIndex == 0 ? "" : ".\(usernameIndex)"
        let username = "seed+\(slug)\(suffix)@vaultcell.test"
        let password = "VaultCell@2026#\(slug.prefix(4).uppercased())\(usernameIndex)"
        let isOAuth = oauthProviders.contains {
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
            has2FA: isOAuth,
            twoFactorConfigs: isOAuth
                ? [TwoFactorConfig(type: .totp, issuer: app.title, boundValue: username)] : [],
            oAuthProvider: isOAuth ? OAuthProviderConfig(provider: slug, boundValue: username) : nil
        )
    }

    private static func augmentSeedEntries(_ base: [PasswordEntry], minimumCount: Int, now: Date)
        -> [PasswordEntry]
    {
        var entries = base
        var keys = Set(
            entries.map {
                SettingsViewModel.seedIdentity(siteName: $0.siteName, username: $0.username)
            })

        for app in famousApps {
            let hasAny = entries.contains {
                $0.siteName.caseInsensitiveCompare(app.title) == .orderedSame
            }
            if hasAny { continue }

            let entry = makeFamousAppSeedEntry(app, usernameIndex: 0)
            let key = SettingsViewModel.seedIdentity(
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
                let key = SettingsViewModel.seedIdentity(
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

    private static func makeSeedEntries() -> [PasswordEntry] {
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
                username: "apple.user@example.com",
                password: "Apple@2026#Secure!",
                bundleEmailAddress: "apple.user@example.com",
                notes: "Apple ID 主账号，用于 App Store、iCloud、iMessage",
                categoryID: PasswordCategory.systemDefaults[0].id,  // Primary
                tags: ["apple", "id", "icloud"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Apple", boundValue: "apple.user@example.com"),
                    TwoFactorConfig(type: .push, issuer: "Apple", boundValue: "iPhone 15 Pro"),
                ],
                oAuthProvider: OAuthProviderConfig(
                    provider: "apple", boundValue: "apple.user@example.com"),
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
                username: "gmail.user@example.com",
                password: "Google!2026@Complex",
                bundlePhoneNumber: "+8613800001111",
                bundleEmailAddress: "gmail.user@example.com",
                notes: "个人主邮箱，已开启高级保护计划，禁止第三方应用访问",
                categoryID: PasswordCategory.systemDefaults[0].id,  // Primary
                tags: ["google", "mail", "advanced-protection"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Google", boundValue: "gmail.user@example.com"),
                    TwoFactorConfig(type: .hardware, issuer: "YubiKey", boundValue: "YubiKey 5C"),
                ],
                oAuthProvider: OAuthProviderConfig(
                    provider: "google", boundValue: "gmail.user@example.com"),
                passwordHistory: [
                    PasswordHistoryEntry(password: "Google2025!Pass", changedAt: threeMonthsAgo)
                ],
                passwordChangedAt: threeMonthsAgo,
                customFields: [
                    CustomField(name: "恢复邮箱", value: "backup.user@example.com", isSensitive: true)
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
                username: "octocat@example.com",
                password: "GitHub#2026!DevPass",
                bundleEmailAddress: "octocat@example.com",
                notes: "公司代码托管，已配置 SSH Key 和 GPG 签名",
                categoryID: PasswordCategory.systemDefaults[2].id,  // Work
                tags: ["dev", "code", "git"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "GitHub", boundValue: "octocat@example.com")
                ],
                oAuthProvider: OAuthProviderConfig(
                    provider: "github", boundValue: "octocat@example.com"),
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
                username: "ms.user@example.com",
                password: "Microsoft@2026!Work",
                bundleEmailAddress: "ms.user@example.com",
                notes: "企业 Office 365 账号，包含 Outlook、Teams、SharePoint",
                categoryID: PasswordCategory.systemDefaults[0].id,  // Primary
                tags: ["work", "office", "microsoft"],
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Microsoft", boundValue: "ms.user@example.com")
                ],
                oAuthProvider: OAuthProviderConfig(
                    provider: "microsoft", boundValue: "ms.user@example.com"),
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
                username: "+8613800009999",
                password: "WeChat@2026#Secure",
                bundlePhoneNumber: "+8613800009999",
                notes: "已实名认证，绑定银行卡、零钱通、微信支付",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["message", "payment", "wechat"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800009999")],
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
                username: "+8613800008888",
                password: "Alipay@2026#Money",
                bundlePhoneNumber: "+8613800008888",
                bundleEmailAddress: "alipay.user@example.com",
                notes: "余额宝 + 基金定投 + 蚂蚁花呗，需定期修改支付密码",
                categoryID: PasswordCategory.systemDefaults[1].id,  // Finance
                tags: ["payment", "bank", "alipay"],
                isFavorite: true,
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(type: .sms, boundValue: "+8613800008888"),
                    TwoFactorConfig(
                        type: .totp, issuer: "Alipay", boundValue: "alipay.user@example.com"),
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
                username: "shopper@example.com",
                password: "Amazon#2026!Shop",
                bundlePhoneNumber: "+8613800002222",
                notes: "Prime 会员，绑定招行 Visa 卡，自动续费",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["shopping", "prime", "amazon"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800002222")],
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
                username: "movie.night@example.com",
                password: "Netflix@2026!TV",
                bundleEmailAddress: "movie.night@example.com",
                notes: "4K 高级套餐，5 人共享，家庭计划",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Media
                tags: ["streaming", "movie", "netflix"],
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(type: .email, boundValue: "movie.night@example.com")
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
                username: "weibo.user@example.com",
                password: "Weibo@2026!Hot",
                bundlePhoneNumber: "+8613800006666",
                notes: "实名认证账号，粉丝数 1.2 万",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["social", "weibo", "china"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800006666")],
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
                username: "zhihu.user@example.com",
                password: "Zhihu@2026!Q&A",
                bundleEmailAddress: "zhihu.user@example.com",
                notes: "盐选会员，累计回答 50+，获赞 2 万",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["qa", "knowledge", "zhihu"],
                has2FA: true,
                twoFactorConfigs: [
                    TwoFactorConfig(
                        type: .totp, issuer: "Zhihu", boundValue: "zhihu.user@example.com")
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
                username: "douban.user@example.com",
                password: "Douban@2026!Book",
                bundleEmailAddress: "douban.user@example.com",
                notes: "书影音爱好者，已标记 500+ 书籍",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Media
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
                username: "ctrip.user@example.com",
                password: "Ctrip@2026!Trip",
                bundlePhoneNumber: "+8613800007777",
                notes: "黄金会员，积分 5 万，绑定企业差旅",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["travel", "hotel", "flight"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800007777")],
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
                username: "railway.user@example.com",
                password: "12306@2026!Train",
                bundlePhoneNumber: "+8613800008888",
                notes: "已实名认证，常用联系人 5 人",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["train", "china", "travel"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800008888")],
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
                bundlePhoneNumber: "+8613800001234",
                notes: "注册多年的老账号，已绑定微信",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["message", "qq", "tencent"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800001234")],
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
                username: "dingtalk.user@example.com",
                password: "DingTalk@2026!Work",
                bundleEmailAddress: "dingtalk.user@example.com",
                notes: "公司内部沟通工具，已加入 3 个企业",
                categoryID: PasswordCategory.systemDefaults[2].id,  // Work
                tags: ["work", "team", "dingtalk"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800009999")],
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
                username: "work.user@example.com",
                password: "WorkWeChat@2026!",
                bundlePhoneNumber: "+8613800005555",
                notes: "企业内部账号，用于审批、会议、文档协作",
                categoryID: PasswordCategory.systemDefaults[2].id,  // Work
                tags: ["work", "enterprise", "wechat"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800005555")],
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
                username: "jd.user@example.com",
                password: "JD@2026!Shop",
                bundlePhoneNumber: "+8613800003333",
                notes: "Plus 会员，绑定京东白条",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["shopping", "jd", "china"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800003333")],
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
                username: "taobao.user@example.com",
                password: "Taobao@2026!Buy",
                bundlePhoneNumber: "+8613800004444",
                notes: "淘宝达人，淘气值 2000+，绑定花呗",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["shopping", "taobao", "alipay"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800004444")],
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
                username: "douyin.user@example.com",
                password: "Douyin@2026!Video",
                bundlePhoneNumber: "+8613800006666",
                notes: "创作者账号，粉丝 5 万，开通直播权限",
                categoryID: PasswordCategory.systemDefaults[4].id,  // Media
                tags: ["video", "shortvideo", "douyin"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800006666")],
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
                username: "xiaohongshu.user@example.com",
                password: "XiaoHongShu@2026!",
                bundleEmailAddress: "xiaohongshu.user@example.com",
                notes: "美妆博主，粉丝 3 万，笔记获赞 10 万",
                categoryID: PasswordCategory.systemDefaults[3].id,  // Life
                tags: ["social", "beauty", "china"],
                has2FA: true,
                twoFactorConfigs: [TwoFactorConfig(type: .sms, boundValue: "+8613800007777")],
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
                username: "workspace.user@example.com",
                password: "Slack@2026!Team",
                bundleEmailAddress: "workspace.user@example.com",
                notes: "团队协作工具，已加入 5 个频道，每日活跃。通过 Google 账户登录",
                categoryID: PasswordCategory.systemDefaults[2].id,  // Work
                tags: ["team", "work", "slack"],
                oAuthProvider: OAuthProviderConfig(
                    provider: "google", boundValue: "gmail.user@example.com"),
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
                username: "notes.user@example.com",
                password: "Notion@2026!Docs",
                bundleEmailAddress: "notes.user@example.com",
                notes: "个人知识库，包含 100+ 页面，多个数据库。通过 Apple 账户登录",
                categoryID: PasswordCategory.systemDefaults[2].id,  // Work
                tags: ["notes", "docs", "productivity"],
                oAuthProvider: OAuthProviderConfig(
                    provider: "apple", boundValue: "apple.user@example.com"),
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
        ]

        return augmentSeedEntries(entries, minimumCount: 40, now: now)
    }

    // MARK: - Pincode Seeds

    private static func makeSeedPincodes() -> [PincodeEntry] {
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
                categoryID: PasswordCategory.systemDefaults[1].id,
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
                categoryID: PasswordCategory.systemDefaults[3].id,
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
                categoryID: PasswordCategory.systemDefaults[1].id,
                tags: ["security", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            PincodeEntry(
                title: "Office Door PIN",
                pincode: "5588",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 公司门禁 PIN",
                categoryID: PasswordCategory.systemDefaults[2].id,
                tags: ["work", "office", "seed"],
                createdAt: oneYearAgo,
                updatedAt: now.addingTimeInterval(-90 * 24 * 60 * 60)
            ),
            PincodeEntry(
                title: "Bike Lock PIN",
                pincode: "4096",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 自行车锁密码",
                categoryID: PasswordCategory.systemDefaults[3].id,
                tags: ["bike", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
            PincodeEntry(
                title: "Luggage Lock PIN",
                pincode: "1122",
                isNumericOnly: true,
                notes: "\(seedNotesMarker) 行李箱密码锁",
                categoryID: PasswordCategory.systemDefaults[3].id,
                tags: ["travel", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
        ]
    }

    // MARK: - Bankcard Seeds

    private static func makeSeedBankcards() -> [BankcardEntry] {
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
                categoryID: PasswordCategory.systemDefaults[1].id,
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
                categoryID: PasswordCategory.systemDefaults[1].id,
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
                categoryID: PasswordCategory.systemDefaults[1].id,
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
                categoryID: PasswordCategory.systemDefaults[1].id,
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
                categoryID: PasswordCategory.systemDefaults[1].id,
                tags: ["bank", "finance", "seed"],
                createdAt: oneYearAgo,
                updatedAt: oneYearAgo
            ),
        ]
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

    /// 把种子数据中的 TOTP 配置补全为“真实”配置：
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

// MARK: - 浅色柔和背景

/// 二级分类统计项
private struct StatItem: Identifiable {
    let id: String
    let icon: String
    let iconColor: Color
    let label: LocalizedStringKey
    let count: Int?
}

/// 一级分类统计卡片（标题 + 总数 + 可选的二级分类胶囊网格）
private struct CategoryStatCard: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let total: Int
    let items: [StatItem]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 一级分类标题行
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(iconColor.opacity(0.12)))

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(total)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(iconColor)
                    .monospacedDigit()
            }

            // 二级分类胶囊网格（叶子分类无此项）
            if !items.isEmpty {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        StatCapsule(
                            icon: item.icon, iconColor: item.iconColor, label: item.label,
                            count: item.count)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

/// 单个统计胶囊
private struct StatCapsule: View {
    let icon: String
    let iconColor: Color
    let label: LocalizedStringKey
    let count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(iconColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(count.map { "\($0)" } ?? "—")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color.secondary.opacity(0.08))
        )
    }
}

/// 与 Onboarding/认证页共享语言的浅色背景
struct SettingsBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.99, green: 0.995, blue: 1.0),
                Color.primaryBrandColor.opacity(0.10),
                Color.secondaryBrandColor.opacity(0.06),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview {
    @Previewable @StateObject var viewModel = VaultListViewModel(
        referenceData: ReferenceDataService())
    @Previewable @StateObject var safeNoteService = SafeNoteVaultService()
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(viewModel)
        .environmentObject(safeNoteService)
        .environmentObject(AppLanguageManager.shared)
}
