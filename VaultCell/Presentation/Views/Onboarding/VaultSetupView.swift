/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultSetupView.swift
/// created on: 28/08/2026
/// ------------------------------------------------------------------

import Combine
import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 引导资格判断

/// 判断是否应展示"密码库就绪"引导页：
/// 用户未看过引导 且 密码库内没有任何内容。
/// 老用户升级（已有条目）或已做过决策的用户不会看到此页。
enum VaultSetupGate {

    /// 密码库是否完全无内容（四类条目计数均为 0，含回收站中的软删除条目）
    static var isVaultEmpty: Bool {
        let context = CoreDataStack.shared.viewContext

        func isClear(_ count: Int?) -> Bool {
            // 查询失败（nil）时保守视为有内容，避免对已有数据的用户误弹引导
            guard let count else { return false }
            return count == 0
        }

        return isClear(try? context.count(for: CDPasswordEntry.fetchRequest()))
            && isClear(try? context.count(for: CDPincodeEntry.fetchRequest()))
            && isClear(try? context.count(for: CDBankcardEntry.fetchRequest()))
            && isClear(try? context.count(for: CDSafeNote.fetchRequest()))
    }
}

// MARK: - 导入/恢复结果

/// 导入与备份恢复的统一结果
enum VaultSetupImportOutcome {
    /// 成功导入 inserted 条（skipped 条被跳过）
    case success(inserted: Int, skipped: Int)
    /// 未导入任何条目（空文件 / 全部重复），message 用于提示后停留本页
    case nothingImported(String)
    /// 失败，message 用于提示
    case failure(String)
}

// MARK: - 视图模型

/// "密码库就绪"引导页业务逻辑：新增条目流程、Chrome CSV 导入、加密备份恢复。
/// 引导是一次性决策点——跳过 / 首个条目保存 / 导入成功任一发生后即结束。
@MainActor
final class VaultSetupViewModel: ObservableObject {

    enum ImporterMode {
        case csv
        case backup
    }

    // MARK: - 状态

    /// 文件选择器呈现状态（CSV 导入与备份恢复共用一个 fileImporter，按模式路由）
    @Published var showingImporter = false
    /// 当前文件选择器的用途，completion 回调时读取并清除
    @Published var importerMode: ImporterMode?

    /// 导入进行中（导入卡片加载态，覆盖 CSV / JSON 等所有来源）
    @Published var isImporting = false

    /// 备份恢复进行中（密码弹窗加载态）
    @Published var isRestoring = false
    @Published var showingRestorePasswordSheet = false
    @Published var restoreFileURL: URL?
    @Published var restoreError: String?

    /// CSV 导入结果提示（alert 展示）
    @Published var importResultMessage: String?

    // MARK: - 依赖

    /// 新增条目流程复用主列表 VM：CreateNewItemView 保存成功后置 isPresentingAddFlow = false
    /// （var 以支持 `$viewModel.listViewModel.isPresentingAddFlow` 可写绑定）
    var listViewModel: VaultListViewModel
    var toastCenter = ToastCenter()

    private var cancellables = Set<AnyCancellable>()

    init() {
        let listViewModel = VaultListViewModel(referenceData: ReferenceDataService())
        self.listViewModel = listViewModel

        // 转发列表 VM 与 Toast 的变更，让订阅本 VM 的视图随之刷新
        // （fullScreenCover / toast 的绑定均落在这些子对象上）
        listViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        toastCenter.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - 导入

    /// 读取并导入文件，自动识别来源：本 app 导出的 CSV / JSON、Chrome CSV
    /// （识别与去重逻辑与设置页导入一致）
    func importFile(from url: URL) async -> VaultSetupImportOutcome {
        guard !isImporting else { return .failure(String(localized: "Import is already in progress.")) }
        isImporting = true
        defer { isImporting = false }

        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let result = try VaultImportService.parse(data: data)

            guard result.totalCount > 0 else {
                return .nothingImported(
                    String(localized: "No valid records were found to import in the file (skipped \(result.skippedCount) empty rows)."))
            }

            let insertedCount = try await VaultImportService.persist(
                parseResult: result,
                existingPasswords: currentPasswordEntries,
                existingPincodes: currentPincodeEntries,
                existingBankcards: currentBankcardEntries,
                categories: listViewModel.categories
            )
            await listViewModel.loadItems()

            if insertedCount > 0 {
                return .success(
                    inserted: insertedCount,
                    skipped: result.totalCount - insertedCount + result.skippedCount)
            }
            return .nothingImported(String(localized: "All records already exist in your vault."))
        } catch {
            await listViewModel.loadItems()
            return .failure("Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 备份恢复

    /// 从加密备份文件恢复密码条目
    func restoreBackup(from url: URL, password: String) async -> VaultSetupImportOutcome {
        guard !isRestoring else { return .failure(String(localized: "Restore is already in progress.")) }
        isRestoring = true
        defer { isRestoring = false }

        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)

            // PBKDF2 派生 + AES-GCM 解密为 CPU 密集操作，移出主线程；
            // 安全笔记按段惰性解密，附件明文不全部驻留内存
            let service = VaultBackupService()
            let reader = try await Task.detached(priority: .userInitiated) {
                try service.makeBackupReader(from: data, password: password)
            }.value

            if reader.isEmpty {
                return .nothingImported(String(localized: "This backup contains no entries."))
            }

            let insertedCount = try await insertRestored(reader: reader)
            await listViewModel.loadItems()

            if insertedCount > 0 {
                return .success(inserted: insertedCount, skipped: reader.totalCount - insertedCount)
            }
            return .nothingImported(String(localized: "All records already exist in your vault."))
        } catch let error as VaultBackupError {
            return .failure(error.localizedDescription)
        } catch {
            await listViewModel.loadItems()
            return .failure("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有 - 条目入库

    /// 恢复的条目按类型入库：密码标记来源为备份恢复，按类型去重跳过已存在条目，
    /// 并将本机不存在的分类（如旧库的自定义分类）回落到系统默认分类
    private func insertRestored(reader: BackupReader) async throws -> Int {
        let knownCategoryIDs = Set(listViewModel.categories.map(\.id))
        var insertedCount = 0

        // 密码条目：按站点名 + 用户名去重
        let passwordRepository: PasswordRepositoryProtocol = PasswordRepository()
        var seenPasswordKeys = Set(
            currentPasswordEntries.map {
                SettingsViewModel.seedIdentity(siteName: $0.siteName, username: $0.username)
            }
        )
        for var entry in reader.passwords {
            let key = SettingsViewModel.seedIdentity(siteName: entry.siteName, username: entry.username)
            if seenPasswordKeys.contains(key) { continue }

            entry.dataSource = .backupRestore
            if !knownCategoryIDs.contains(entry.categoryID) {
                entry.categoryID = PasswordCategory.defaultCategoryID
            }

            try await passwordRepository.save(entry)
            seenPasswordKeys.insert(key)
            insertedCount += 1
        }

        // PIN 条目：按标题 + 码值去重
        let pincodeRepository: PincodeRepositoryProtocol = PincodeRepository()
        var seenPincodeKeys = Set(
            currentPincodeEntries.map { "\($0.title.lowercased())|\($0.pincode)" }
        )
        for var entry in reader.pincodes {
            let key = "\(entry.title.lowercased())|\(entry.pincode)"
            if seenPincodeKeys.contains(key) { continue }

            if !knownCategoryIDs.contains(entry.categoryID) {
                entry.categoryID = PasswordCategory.defaultCategoryID
            }

            try await pincodeRepository.save(entry)
            seenPincodeKeys.insert(key)
            insertedCount += 1
        }

        // 银行卡条目：按卡号（纯数字）去重
        let bankcardRepository: BankcardRepositoryProtocol = BankcardRepository()
        let normalizeCard: (String) -> String = { $0.filter(\.isNumber) }
        var seenCardKeys = Set(currentBankcardEntries.map { normalizeCard($0.cardNumber) })
        for var entry in reader.bankcards {
            let key = normalizeCard(entry.cardNumber)
            if key.isEmpty || seenCardKeys.contains(key) { continue }

            if !knownCategoryIDs.contains(entry.categoryID) {
                entry.categoryID = PasswordCategory.defaultCategoryID
            }

            try await bankcardRepository.save(entry)
            seenCardKeys.insert(key)
            insertedCount += 1
        }

        // 安全笔记：按笔记 id 去重；备份笔记逐段解密（处理完即释放，
        // 避免全部附件明文同时驻留内存）
        let safeNoteRepository: SafeNoteRepositoryProtocol = SafeNoteRepository()
        let existingNoteIDs = Set((try? await safeNoteRepository.fetchAll())?.map(\.id) ?? [])
        while let noteBackup = try await reader.nextNoteInBackground() {
            var note = noteBackup.note
            if existingNoteIDs.contains(note.id) { continue }

            note.dataSource = .backupRestore
            note.deletedAt = nil

            // 附件以备份中的明文数据重新入库（目标设备 DEK 不同，必须重新加密）
            let draftAssets = note.assets.map { asset in
                SafeNoteDraftAsset(
                    id: asset.id,
                    imageData: noteBackup.imageDataByAssetID[asset.id],
                    thumbnailData: noteBackup.thumbnailDataByAssetID[asset.id],
                    existingAsset: nil,
                    sortOrder: asset.sortOrder,
                    mimeType: asset.mimeType
                )
            }
            try await safeNoteRepository.save(note, draftAssets: draftAssets)
            insertedCount += 1
        }

        return insertedCount
    }

    /// 当前库内已有的密码条目（用于导入去重）
    private var currentPasswordEntries: [PasswordEntry] {
        listViewModel.items.compactMap {
            guard case .password(let entry) = $0 else { return nil }
            return entry
        }
    }

    /// 当前库内已有的 PIN 条目（用于导入去重）
    private var currentPincodeEntries: [PincodeEntry] {
        listViewModel.items.compactMap {
            guard case .pincode(let entry) = $0 else { return nil }
            return entry
        }
    }

    /// 当前库内已有的银行卡条目（用于导入去重）
    private var currentBankcardEntries: [BankcardEntry] {
        listViewModel.items.compactMap {
            guard case .bankcard(let entry) = $0 else { return nil }
            return entry
        }
    }
}

// MARK: - 主视图

/// "密码库就绪"首次填充引导页
///
/// 设计语言：与 Onboarding / 认证页一致的浅色空气感背景、渐变图标与错峰入场动效。
/// signature 元素为"轨道环绕"：中心密码库图标四周，四个条目小圆沿椭圆轨道缓慢公转，
/// 隐喻"密码库在等待第一批住户"。
struct VaultSetupView: View {
    /// 引导完成回调（跳过 / 首个条目保存 / 导入恢复成功后触发）
    let onComplete: () -> Void

    @StateObject private var viewModel = VaultSetupViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 入场动效阶段
    @State private var appeared = false
    @State private var contentAppeared = false
    @State private var cardsAppeared = false
    @State private var skipAppeared = false

    var body: some View {
        ZStack {
            AuthBackground()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 28)

                    OrbitingVaultHero(reduceMotion: reduceMotion)
                        .padding(.bottom, 18)

                    successBadge
                        .opacity(contentAppeared ? 1.0 : 0.0)
                        .scaleEffect(contentAppeared ? 1.0 : 0.7)

                    titleSection
                        .opacity(contentAppeared ? 1.0 : 0.0)
                        .offset(y: contentAppeared ? 0 : 10)
                        .padding(.top, 14)

                    actionCards
                        .padding(.top, 30)

                    skipButton
                        .padding(.top, 26)

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // 新增条目流程：复用主列表 VM 的 isPresentingAddFlow，保存成功后自动关闭
        .fullScreenCover(isPresented: $viewModel.listViewModel.isPresentingAddFlow) {
            NavigationStack {
                CreateNewItemView(viewModel: viewModel.listViewModel, toastCenter: viewModel.toastCenter)
            }
        }
        .onChange(of: viewModel.listViewModel.isPresentingAddFlow) { _, presented in
            guard !presented else { return }
            // 新增流程关闭后刷新：若已有条目则视为完成首次填充
            Task {
                await viewModel.listViewModel.loadItems()
                if !viewModel.listViewModel.items.isEmpty {
                    finishSetup()
                }
            }
        }
        // 文件选择器：CSV 导入与备份恢复共用，按 importerMode 路由
        .fileImporter(
            isPresented: $viewModel.showingImporter,
            allowedContentTypes: importerAllowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImporterResult(result)
        }
        // 备份恢复：选择文件后先输入备份密码
        .sheet(isPresented: $viewModel.showingRestorePasswordSheet) {
            BackupPasswordPromptView(viewModel: viewModel) { password in
                Task { await performRestore(password: password) }
            }
        }
        .onChange(of: viewModel.showingRestorePasswordSheet) { _, showing in
            if !showing {
                viewModel.restoreFileURL = nil
                viewModel.restoreError = nil
            }
        }
        .alert(
            String(localized: "Import Result"),
            isPresented: Binding(
                get: { viewModel.importResultMessage != nil },
                set: { if !$0 { viewModel.importResultMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel.importResultMessage ?? "")
        }
        .toast($viewModel.toastCenter.toast)
        .onAppear {
            runEntranceAnimations()
        }
    }

    // MARK: - 组成部分

    /// 成功徽章：绿色胶囊，宣告"密码库已创建"
    private var successBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Vault created"))
                .font(.footnote.weight(.semibold))
        }
        .foregroundColor(.successColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.successColor.opacity(0.12)))
        .accessibilityAddTraits(.isHeader)
    }

    private var titleSection: some View {
        VStack(spacing: 10) {
            Text(String(localized: "Your vault is ready"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(String(localized: "Add your first item to get started"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    /// 三条路径等权重：新建条目 / 导入密码 / 从备份恢复
    private var actionCards: some View {
        VStack(spacing: 14) {
            SetupActionCard(
                icon: "plus",
                iconStyle: .gradient,
                title: String(localized: "Create item"),
                subtitle: String(localized: "Passwords, cards, secure notes and more"),
                isLoading: false,
                loadingText: String(localized: "Importing..."),
                isEnabled: !viewModel.isImporting && !viewModel.isRestoring
            ) {
                viewModel.listViewModel.isPresentingAddFlow = true
            }
            .modifier(SetupCardEntrance(delay: 0, appeared: cardsAppeared))

            SetupActionCard(
                icon: "tray.and.arrow.down",
                iconStyle: .tinted(Color(red: 0.30, green: 0.78, blue: 0.68)),
                title: String(localized: "Import passwords"),
                subtitle: String(localized: "VaultCell exports or Chrome CSV backups"),
                isLoading: viewModel.isImporting,
                loadingText: String(localized: "Importing..."),
                isEnabled: !viewModel.isImporting && !viewModel.isRestoring
            ) {
                startImporter(.csv)
            }
            .modifier(SetupCardEntrance(delay: 0.08, appeared: cardsAppeared))

            SetupActionCard(
                icon: "arrow.uturn.left",
                iconStyle: .tinted(Color(red: 0.55, green: 0.50, blue: 0.95)),
                title: String(localized: "Restore from backup"),
                subtitle: String(localized: "Restore from an encrypted VaultCell backup file"),
                isLoading: viewModel.isRestoring && !viewModel.showingRestorePasswordSheet,
                loadingText: String(localized: "Restoring..."),
                isEnabled: !viewModel.isImporting && !viewModel.isRestoring
            ) {
                startImporter(.backup)
            }
            .modifier(SetupCardEntrance(delay: 0.16, appeared: cardsAppeared))
        }
    }

    private var skipButton: some View {
        Button {
            finishSetup()
        } label: {
            Text(String(localized: "Skip for now"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .opacity(skipAppeared ? 1.0 : 0.0)
    }

    /// 文件选择器可选类型按用途过滤
    private var importerAllowedContentTypes: [UTType] {
        switch viewModel.importerMode {
        case .csv:
            // 自动识别：本 app 导出 CSV / JSON、Chrome CSV
            return [.commaSeparatedText, .text, .json, .data, .item]
        case .backup:
            return [.vaultBackup, .data, .item]
        case nil:
            return [.item]
        }
    }

    // MARK: - 行为

    private func startImporter(_ mode: VaultSetupViewModel.ImporterMode) {
        guard !viewModel.isImporting, !viewModel.isRestoring else { return }
        viewModel.importerMode = mode
        viewModel.showingImporter = true
    }

    private func handleImporterResult(_ result: Result<[URL], Error>) {
        guard let mode = viewModel.importerMode else { return }
        viewModel.importerMode = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch mode {
            case .csv:
                Task {
                    let outcome = await viewModel.importFile(from: url)
                    await handleImportOutcome(outcome)
                }
            case .backup:
                viewModel.restoreFileURL = url
                viewModel.restoreError = nil
                // 等文件选择器完全收起后再弹密码输入框，避免系统级呈现冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    viewModel.showingRestorePasswordSheet = true
                }
            }
        case .failure:
            // 用户取消选择
            break
        }
    }

    private func handleImportOutcome(_ outcome: VaultSetupImportOutcome) async {
        switch outcome {
        case .success(let inserted, _):
            finishSetup(
                withToast: ToastItem(
                    message: String(localized: "Imported \(inserted) items"),
                    style: .success
                )
            )
        case .nothingImported(let message):
            viewModel.importResultMessage = message
        case .failure(let message):
            viewModel.importResultMessage = message
        }
    }

    private func performRestore(password: String) async {
        guard let url = viewModel.restoreFileURL else { return }
        let outcome = await viewModel.restoreBackup(from: url, password: password)

        switch outcome {
        case .success(let inserted, _):
            viewModel.showingRestorePasswordSheet = false
            finishSetup(
                withToast: ToastItem(
                    message: String(localized: "Restored \(inserted) items"),
                    style: .success
                )
            )
        case .nothingImported(let message):
            viewModel.restoreError = message
        case .failure(let message):
            // 密码错误等失败保持弹窗打开，用户可重试或取消
            viewModel.restoreError = message
        }
    }

    /// 完成引导：置一次性标记并回调父视图切换主界面。
    ///
    /// 无 toast（创建首个条目）时立即转场；有 toast（导入/恢复成功）时先让
    /// toast 短暂可见，并把标记落盘与 onComplete 同步延迟到系统呈现
    /// （sheet dismiss）完全结束之后——否则在密码弹窗收起动画进行中移除
    /// VaultSetupView，会触发 SwiftUI/UIKit 呈现冲突导致闪退。
    /// 标记延迟不影响正确性：引导页的展示前提是 `VaultSetupGate.isVaultEmpty`，
    /// 恢复成功后库内已有条目，即使进程被杀也不会再次弹引导。
    private func finishSetup(withToast toast: ToastItem? = nil) {
        guard let toast else {
            UserDefaults.hasSeenVaultSetupGuide = true
            onComplete()
            return
        }
        viewModel.toastCenter.toast = toast
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            UserDefaults.hasSeenVaultSetupGuide = true
            onComplete()
        }
    }

    /// 错峰入场：徽章/标题 → 卡片（0.08s 间隔）→ 跳过按钮最后淡入
    private func runEntranceAnimations() {
        guard !appeared else { return }
        appeared = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if reduceMotion {
            contentAppeared = true
            cardsAppeared = true
            skipAppeared = true
            return
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.3)) {
            contentAppeared = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.55)) {
            cardsAppeared = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.95)) {
            skipAppeared = true
        }
    }
}

// MARK: - 卡片入场修饰符

/// 卡片错峰入场：透明度 + 上移
private struct SetupCardEntrance: ViewModifier {
    let delay: Double
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 14)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(delay), value: appeared)
    }
}

// MARK: - 轨道环绕主图标（signature）

/// 中心密码库渐变图标 + 四个条目小圆沿椭圆轨道缓慢公转。
/// 卫星四色取自 Onboarding 四页强调色：蓝 / 青绿 / 紫 / 橙。
private struct OrbitingVaultHero: View {
    let reduceMotion: Bool

    @State private var appeared = false
    @State private var floating = false
    @State private var orbitAngle: Double = 0
    @State private var satellitesAppeared = [false, false, false, false]

    private let accent = Color.primaryBrandColor
    private let accent2 = Color.secondaryBrandColor

    private struct Satellite: Identifiable {
        let id: Int
        let symbol: String
        let color: Color
        let baseAngle: Double
    }

    private let satellites: [Satellite] = [
        Satellite(id: 0, symbol: "key.fill", color: Color(red: 0.25, green: 0.60, blue: 1.00), baseAngle: 0),
        Satellite(id: 1, symbol: "creditcard.fill", color: Color(red: 0.30, green: 0.78, blue: 0.68), baseAngle: 90),
        Satellite(id: 2, symbol: "doc.text.fill", color: Color(red: 0.55, green: 0.50, blue: 0.95), baseAngle: 180),
        Satellite(id: 3, symbol: "wifi", color: Color(red: 0.98, green: 0.55, blue: 0.40), baseAngle: 270),
    ]

    /// 椭圆轨道半径
    private let orbitRadiusX: CGFloat = 104
    private let orbitRadiusY: CGFloat = 76

    var body: some View {
        ZStack {
            // 中心：渐变主圆 + 柔光晕 + 顶部高光（复用 Onboarding 图标语言）
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [accent.opacity(0.30), accent.opacity(0)]),
                            center: .center,
                            startRadius: 50,
                            endRadius: 110
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(floating ? 1.05 : 0.95)

                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [accent, accent2]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 116)
                    .shadow(color: accent.opacity(0.35), radius: 18, y: 12)

                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)]),
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 116, height: 116)
                    .mask(Circle().frame(width: 116, height: 116))

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: floating ? -5 : 5)

            // 轨道卫星
            ForEach(satellites) { satellite in
                satelliteView(satellite)
                    .offset(
                        x: orbitRadiusX * CGFloat(cos(radians(for: satellite))),
                        y: orbitRadiusY * CGFloat(sin(radians(for: satellite)))
                    )
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - 私有

    private func satelliteView(_ satellite: Satellite) -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 40, height: 40)
                .shadow(color: satellite.color.opacity(0.35), radius: 8, y: 4)

            Image(systemName: satellite.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(satellite.color)
        }
        .scaleEffect(satellitesAppeared[satellite.id] ? 1.0 : 0.01)
        .opacity(satellitesAppeared[satellite.id] ? 1.0 : 0.0)
    }

    /// 卫星当前轨道角（弧度）
    private func radians(for satellite: Satellite) -> Double {
        (orbitAngle + satellite.baseAngle) * .pi / 180
    }

    private func startAnimations() {
        guard !appeared else { return }
        appeared = true

        if reduceMotion {
            satellitesAppeared = [true, true, true, true]
            return
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            appeared = true
        }
        for index in satellites.indices {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.35 + Double(index) * 0.06)) {
                satellitesAppeared[index] = true
            }
        }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            floating = true
        }
        // 慢速公转（约 22 秒一圈），线性循环保证接缝平滑
        withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
            orbitAngle = 360
        }
    }
}

// MARK: - 操作卡片

/// 引导页路径卡片：图标 + 标题 + 描述 + chevron，整卡可点击（≥44pt）
private struct SetupActionCard: View {
    enum IconStyle {
        /// 品牌渐变底 + 白色符号（新建路径）
        case gradient
        /// 淡色底 + 彩色符号
        case tinted(Color)
    }

    let icon: String
    let iconStyle: IconStyle
    let title: String
    let subtitle: String
    let isLoading: Bool
    let loadingText: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconView

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Text(isLoading ? loadingText : subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                if !isLoading {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary.opacity(0.5))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(CardPressStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            switch iconStyle {
            case .gradient:
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.primaryBrandColor, .secondaryBrandColor]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            case .tinted(let color):
                Circle()
                    .fill(color.opacity(0.14))
            }

            if isLoading {
                ProgressView()
                    .tint(loadingTint)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var symbolColor: Color {
        switch iconStyle {
        case .gradient:
            return .white
        case .tinted(let color):
            return color
        }
    }

    private var loadingTint: Color {
        switch iconStyle {
        case .gradient:
            return .white
        case .tinted(let color):
            return color
        }
    }
}

/// 卡片按压缩放反馈
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 恢复备份密码弹窗

/// 输入备份密码以解密恢复；密码错误时保持弹窗打开并内联提示
private struct BackupPasswordPromptView: View {
    @ObservedObject var viewModel: VaultSetupViewModel
    let onConfirm: (String) -> Void

    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // 说明：备份密码独立于当前密码库主密码
                    Label {
                        Text(String(localized: "Enter the password used to encrypt this backup."))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.primaryBrandColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.primaryBrandColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Backup Password"))
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)

                        AuthSecureField(
                            text: $password,
                            placeholder: String(localized: "Enter backup password"),
                            isFocused: focused,
                            hasError: viewModel.restoreError != nil
                        )
                        .focused($focused)
                        // 与认证页一致：禁用键盘强密码建议
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                    }

                    if let error = viewModel.restoreError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.errorColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryActionButton(
                        title: String(localized: "Restore"),
                        isLoading: viewModel.isRestoring,
                        isEnabled: !password.isEmpty && !viewModel.isRestoring
                    ) {
                        submit()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "Restore from backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "Cancel")) {
                        viewModel.showingRestorePasswordSheet = false
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isRestoring)
            .onAppear {
                viewModel.restoreError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focused = true
                }
            }
        }
    }

    private func submit() {
        guard !password.isEmpty, !viewModel.isRestoring else { return }
        onConfirm(password)
    }
}

// MARK: - 预览

#Preview("Vault Setup") {
    VaultSetupView {}
}

#Preview("Restore Password Sheet") {
    BackupPasswordPromptView(viewModel: VaultSetupViewModel()) { _ in }
}
