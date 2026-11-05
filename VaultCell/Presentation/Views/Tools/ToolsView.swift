/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ToolsView.swift
/// created on: 23/09/2026
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
        case .thirtySeconds: return AppLocale.string("30 Seconds")
        case .sixtySeconds: return AppLocale.string("60 Seconds")
        case .threeMinutes: return AppLocale.string("3 Minutes")
        case .fiveMinutes: return AppLocale.string("5 Minutes")
        case .never: return AppLocale.string("Never")
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
        case .thirtySeconds: return AppLocale.string("30 Seconds")
        case .sixtySeconds: return AppLocale.string("60 Seconds")
        case .twoMinutes: return AppLocale.string("2 Minutes")
        case .never: return AppLocale.string("Never")
        }
    }
}

/// 工具中心
///
/// 上半部分是四个工具入口（卡片网格），下半部分是原来的设置项。
/// 数据管理页已被取消：导入 / 导出 / 清除类操作收进「数据中心」子页，
/// 备份 / 恢复与 iCloud 同步收进「同步与备份」子页，这里只留两个入口。
struct ToolsView: View {

    @AppStorage(VaultKey.biometricEnabled) private var biometricEnabled = true
    @AppStorage(VaultKey.autoLockInterval) private var autoLockInterval = 30.0
    @AppStorage(VaultKey.clipboardTimeout) private var clipboardTimeout = 60.0
    #if DEBUG
    /// 仅开发模式提供：Release 包不暴露"列表滑动删除"开关
    @AppStorage(VaultKey.allowSwipeDeleteInVaultList) private var allowSwipeDeleteInVaultList = true
    #endif
    /// 远程网站图标抓取开关：与 IconPreferences 读写同一个 key，默认值由地区在首启落盘一次
    @AppStorage(VaultKey.iconAutoFetch) private var iconAutoFetchEnabled = true
    /// 是否在安全评分页展示"已泄露"相关内容（顶部指标 + "为何被扣分"卡片，默认关闭）
    @AppStorage(VaultKey.showCompromisedInScoreReasons) private var showCompromisedInScoreReasons =
        false
    /// 外观模式：持久化用户的浅色 / 深色 / 跟随系统选择，由 App 根视图统一应用
    @AppStorage(VaultKey.appearanceMode) private var appearanceMode: AppAppearance = .system

    /// 「清除图标缓存」的瞬时回执（2 秒后复原）
    @State private var didClearIconCache = false

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

    /// 一级入口只显示简短状态，开关、错误详情与重试统一放到「同步与备份」子页
    private var syncBadge: String {
        switch appState.syncStatus {
        case .idle:
            return appState.isCloudSyncEnabled
                ? AppLocale.string("Enabled") : AppLocale.string("Not Enabled")
        case .inProgress:
            return AppLocale.string("Sync in progress...")
        case .completed:
            return AppLocale.string("Sync completed")
        case .failed:
            return AppLocale.string("Sync failed")
        }
    }

    @State private var showingChangePassword = false
    #if DEBUG
    @State private var isSeedingTestData = false
    #endif
    @State private var showingLanguagePicker = false
    @State private var showingTrash = false
    /// 换号 / 注销前必须处理的联系方式数量（进入页面时计算一次）
    @State private var blockingPhoneCount = 0
    @State private var blockingEmailCount = 0
    /// 被多个账户共用的密码组数量（进入页面时计算一次）
    @State private var reusedGroupCount = 0

    /// 设置页业务逻辑：回收站计数 / 弹窗状态
    @StateObject private var settingsVM = SettingsViewModel()

    /// 最近一次自动填充身份同步结果（供下方诊断区展示）
    @State private var autoFillReport: AutoFillIdentityService.SyncReport?
    /// 工具中心独立持有生成器配置，避免与编辑页的生成结果互相串改
    @StateObject private var passwordGeneratorService = PasswordGeneratorService()

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
                toolsSection
                generalSection
                securitySection
                //breachDetectionSection
                privacySection
                dataSection
                aboutSection
                autoFillSection
                #if DEBUG
                // 开发模式（生成测试库 / 滑动删除开关）只存在于 Debug 包
                developmentModeSection
                #endif
            }
            .listStyle(.insetGrouped)
            // 首个 Section 上方的系统默认留白偏大，这里压到 6pt；
            // 卡片行自身的 top inset 见 toolsSection
            .contentMargins(.top, 6, for: .scrollContent)
            // 原危险区 footer 承担的底部留白，移除后改由列表内容边距避开浮动 TabBar
            .contentMargins(.bottom, 80, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(SettingsBackground())
            .navigationTitle(AppLocale.string("Tools"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingChangePassword) {
                ChangeMasterPasswordView()
            }
            .sheet(isPresented: $showingLanguagePicker) {
                LanguagePickerView()
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
                reloadIdentityCounts()
                refreshAutoFillReport()
                Task {
                    await settingsVM.loadTrashedCount()
                }
            }
        }
        // 确认/结果弹窗挂载在导航栈外层：若挂在导航栈内部，push 到
        // 子页面后设置的 alert 会被子页面遮挡，直到回退才显示
        .alert(
            settingsVM.alert?.title ?? "",
            isPresented: Binding(
                get: { settingsVM.alert != nil },
                set: { if !$0 { settingsVM.alert = nil } }
            ),
            presenting: settingsVM.alert
        ) { alert in
            switch alert {
            #if DEBUG
            case .seedConfirm:
                Button(AppLocale.string("Generate")) {
                    Task { await seedTestPasswords() }
                }
                Button(AppLocale.string("Cancel"), role: .cancel) {}
            case .seedResult:
                Button(AppLocale.string("OK"), role: .cancel) {}
            #endif
            default:
                // 导入 / 导出 / 清除类的确认与结果弹窗已迁入「数据中心」页
                Button(AppLocale.string("OK"), role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    /// 联系方式评审与复用密码的徽标：进入页面时统计一次
    private func reloadIdentityCounts() {
        let reports = IdentityUsageAuditService().scan(entries: passwordEntries)
        blockingPhoneCount =
            reports
            .filter { $0.kind == .phone && $0.risk >= .high }
            .count
        blockingEmailCount =
            reports
            .filter { $0.kind == .email && $0.risk >= .high }
            .count
        reusedGroupCount = ReusedPasswordAuditService().scan(entries: passwordEntries).count
    }

    /// 读取最近一次自动填充身份同步结果。
    /// App 刚启动、还没同步过时报告为空，此时主动触发一次，避免设置页该区块整段不显示。
    private func refreshAutoFillReport() {
        if let report = AutoFillIdentityService.lastSyncReport {
            autoFillReport = report
            return
        }
        Task {
            await AutoFillIdentityService.shared.synchronize()
            autoFillReport = AutoFillIdentityService.lastSyncReport
        }
    }

    // MARK: - 工具

    /// 顶部工具卡片区：卡片而不是列表行，与下方配置型设置项区分开
    ///
    /// 水平 insets 显式归零：行内容放宽到 Section 背景板边缘，卡片的左右边缘
    /// 才能和下方每个设置块的外边缘对齐。不沿用系统默认行缩进（那会让卡片比
    /// 设置块多缩进一截），也不写死绝对像素，横屏 / iPad 上背景板 margin
    /// 变化时依旧对齐。网格内部同样不加水平 padding，原因见 ToolsGrid。
    private var toolsSection: some View {
        Section {
            ToolsGrid(
                passwordGeneratorService: passwordGeneratorService,
                phoneBlockingCount: blockingPhoneCount,
                emailBlockingCount: blockingEmailCount,
                reusedGroupCount: reusedGroupCount
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
        }
    }

    // MARK: - 安全

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

    // MARK: - 自动填充

    /// 自动填充身份同步状态。
    ///
    /// 身份条数 ≈ 密码条目的 2~4 倍（每条目注册「精确主机 / 父域或 www」两组 × domain/URL 两型）。
    /// 系统侧批量写入是原子的：一旦超过系统能接受的量，整批会被拒绝、QuickType 建议整体消失，
    /// 因此这里把身份数 / 预算 / 上次结果摊开，便于用户与支持人员一眼看出余量。
    @ViewBuilder
    private var autoFillSection: some View {
        if let report = autoFillReport {
            Section("AutoFill") {
                HStack {
                    CustomLabel(
                        leadingIcon: report.isEnabled
                            ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        leadingIconColor: report.isEnabled ? .primaryBrandColor : .errorColor,
                        text: "Status")
                    Spacer()
                    Text(
                        report.isEnabled
                            ? AppLocale.string("Enabled") : AppLocale.string("Not Enabled")
                    )
                    .font(.subheadline)
                    .foregroundColor(report.isEnabled ? .secondary : .errorColor)
                }

                HStack {
                    CustomLabel(
                        leadingIcon: "key.fill", leadingIconColor: .primaryBrandColor,
                        text: "Registered Identities")
                    Spacer()
                    Text("\(report.count) / \(report.budget)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                HStack {
                    CustomLabel(
                        leadingIcon: "square.stack.3d.up.fill",
                        leadingIconColor: .secondaryBrandColor,
                        text: "Entries Synced")
                    Spacer()
                    Text("\(report.entryCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                if report.droppedEntryCount > 0 {
                    HStack {
                        CustomLabel(
                            leadingIcon: "exclamationmark.triangle.fill",
                            leadingIconColor: .errorColor,
                            text: "Dropped Entries")
                        Spacer()
                        Text("\(report.droppedEntryCount)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.errorColor)
                    }
                }

                HStack {
                    CustomLabel(
                        leadingIcon: "clock.arrow.circlepath",
                        leadingIconColor: .secondaryBrandColor,
                        text: "Last Sync")
                    Spacer()
                    Text(report.date, style: .relative)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let message = report.errorMessage {
                    HStack(alignment: .top) {
                        CustomLabel(
                            leadingIcon: "xmark.octagon.fill", leadingIconColor: .errorColor,
                            text: "Error")
                        Spacer()
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.errorColor)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    /// 泄露检测展示开关
    /// 泄露检测尚未上线，"已泄露"条目并不影响评分，因此默认不出现在"为何被扣分"里；
    /// 打开后该分类才会作为一张可下钻的卡片出现。
    private var breachDetectionSection: some View {
        Section {
            Toggle(isOn: $showCompromisedInScoreReasons) {
                CustomLabel(
                    leadingIcon: "flame.fill",
                    leadingIconColor: .errorColor,
                    text: "Show Compromised Entries"
                )
            }
            .tint(.primaryBrandColor)
        } footer: {
            Text(
                AppLocale.string("Breach detection is not available yet, so compromised entries do not lower your score. Turn this on to list them under Security Score."
                )
            )
        }
    }

    // MARK: - 隐私

    /// 隐私：远程图标抓取开关与缓存清理
    /// 关闭开关只是不再发起新请求，**不会**顺带清掉已有缓存（两者互不牵连）
    private var privacySection: some View {
        Section("Privacy") {
            Toggle(isOn: $iconAutoFetchEnabled) {
                CustomLabel(
                    leadingIcon: "photo.on.rectangle.angled",
                    leadingIconColor: .primaryBrandColor,
                    text: "Website Icons")
            }
            .tint(.primaryBrandColor)

            Button(action: clearIconCache) {
                CustomLabel(
                    leadingIcon: didClearIconCache ? "checkmark.circle.fill" : "trash",
                    leadingIconColor: .primaryBrandColor,
                    text: "Clear Icon Cache")
            }
        }
    }

    /// 清除图标缓存：清缓存目录 + 失败集合（失败集合一并清掉后才会重新尝试抓取）
    private func clearIconCache() {
        IconPreferences.clearCache()
        withAnimation { didClearIconCache = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { didClearIconCache = false }
        }
    }

    // MARK: - 数据

    /// 数据操作：原「数据管理」二级页已取消，导入 / 导出 / 清除类操作收在「数据中心」，
    /// 备份 / 恢复与 iCloud 同步收在「同步与备份」子页
    private var dataSection: some View {
        Section("Data") {
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

            // 导入 / 导出 / 密码库清除 / iCloud 清除的入口都在「数据中心」子页
            NavigationLink {
                DataCenterView()
            } label: {
                CustomLabel(
                    leadingIcon: "externaldrive", leadingIconColor: .secondaryBrandColor,
                    text: "Data Center"
                )
            }

            // iCloud 同步、加密备份与恢复的入口都在「同步与备份」子页
            NavigationLink {
                CloudSyncView()
            } label: {
                HStack {
                    CustomLabel(
                        leadingIcon: "icloud", leadingIconColor: .secondaryBrandColor,
                        text: "Sync & Backup"
                    )
                    Spacer()
                    Text(syncBadge)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 通用

    /// 通用：外观、语言、字体与分类管理
    private var generalSection: some View {
        Section("General") {
            Picker(selection: $appearanceMode) {
                Text("Light").tag(AppAppearance.light)
                Text("Dark").tag(AppAppearance.dark)
                Text("Follow System").tag(AppAppearance.system)
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

            /*
            NavigationLink(destination: Text(AppLocale.string("Font Size"))) {
                CustomLabel(
                    leadingIcon: "textformat.size", leadingIconColor: .secondary, text: "Font Size")
            }
            */

            // 开关直接绑定列表 ViewModel：切换后列表立即重排，落盘由 ViewModel 的 didSet 完成
            Toggle(isOn: $viewModel.pinFavoritesToTop) {
                CustomLabel(
                    leadingIcon: "star.fill", leadingIconColor: .secondary,
                    text: "Pin Favorites to Top")
            }
            .tint(.primaryBrandColor)

            NavigationLink(destination: CategoryManagementView(viewModel: viewModel)) {
                CustomLabel(
                    leadingIcon: "tag.fill", leadingIconColor: .secondaryBrandColor,
                    text: "Password Categories")
            }

        }
    }

    // MARK: - 关于

    /// 关于：保留独立二级页，里面的评分 / 帮助 / 条款都在那一页里
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

    // MARK: - 开发模式

    #if DEBUG
    /// 开发模式：生成测试库与列表滑动删除开关，仅 Debug 包可见
    /// （上架包不暴露测试数据入口，避免审核判定为半成品功能，也避免污染用户密码库）
    private var developmentModeSection: some View {
        Section("Development Mode") {
            Toggle(isOn: $allowSwipeDeleteInVaultList) {
                CustomLabel(
                    leadingIcon: "hand.draw", leadingIconColor: .secondary,
                    text: "Swipe to Delete in Vault List")
            }
            .tint(.primaryBrandColor)

            Button {
                settingsVM.alert = .seedConfirm
            } label: {
                CustomLabel(
                    leadingIcon: isSeedingTestData ? "hourglass" : "sparkles.rectangle.stack",
                    leadingIconColor: .secondaryBrandColor,
                    text: "Generate Test Vault")
            }
            .disabled(isSeedingTestData)
        }
    }
    #endif

    // MARK: - 测试库

    #if DEBUG
    /// 生成测试库：仅 Debug 包可用，上架包不包含该入口
    private func seedTestPasswords() async {
        guard !isSeedingTestData else { return }

        if VaultTestDataSeeder.hasSeededTestVault(
            passwords: passwordEntries,
            alreadyGenerated: SettingsViewModel.isSeedTestVaultGenerated()
        ) {
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

        let seedEntries = VaultTestDataSeeder.makeSeedEntries()

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
        let seedPincodes = VaultTestDataSeeder.makeSeedPincodes()
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
        let seedBankcards = VaultTestDataSeeder.makeSeedBankcards()
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
    #endif

}

#Preview {
    ToolsView()
        .environmentObject(AppState())
        .environmentObject(VaultListViewModel(referenceData: ReferenceDataService()))
        .environmentObject(SafeNoteVaultService())
        .environmentObject(AppLanguageManager.shared)
}
