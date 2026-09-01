/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// SettingsViewModel.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import Combine
import CoreData
import Foundation

/// 数据操作类型：导入 / 恢复 / 备份导出 / 明文导出
enum DataOperationKind {
    /// 导入文件（自动识别 CSV / JSON / Chrome CSV）
    case importItems
    /// 从加密备份恢复
    case restoreItems
    /// 加密备份导出（.vgbackup）
    case backupExport
    /// 明文导出（CSV / JSON）
    case dataExport
}

/// 数据操作（导入 / 恢复 / 备份导出 / 明文导出）的结果提示载荷：
/// 成功时展示文件名与条目数量，失败时展示原因。
struct DataOperationResult {
    let operation: DataOperationKind
    /// 是否成功
    let succeeded: Bool
    /// 文件名（导入 / 恢复为所选文件；导出为生成的文件名）
    let fileName: String
    /// 成功时：新增 / 导出的条目数量
    let itemCount: Int
    /// 成功时：跳过的重复或无效条目数量（导出恒为 0）
    let skippedCount: Int
    /// 失败原因（成功时为 nil）
    let errorMessage: String?

    var title: String {
        switch (operation, succeeded) {
        case (.importItems, true): return String(localized: "Import Successful")
        case (.importItems, false): return String(localized: "Import Failed")
        case (.restoreItems, true): return String(localized: "Restore Successful")
        case (.restoreItems, false): return String(localized: "Restore Failed")
        case (.backupExport, true): return String(localized: "Backup Successful")
        case (.backupExport, false): return String(localized: "Backup Failed")
        case (.dataExport, true): return String(localized: "Export Successful")
        case (.dataExport, false): return String(localized: "Export Failed")
        }
    }

    var message: String {
        if let errorMessage {
            return errorMessage
        }
        switch operation {
        case .importItems:
            if skippedCount > 0 {
                return String(
                    localized:
                        "Imported \(itemCount) records from \(fileName). \(skippedCount) duplicate or invalid records skipped.")
            }
            return String(localized: "Imported \(itemCount) records from \(fileName).")
        case .restoreItems:
            if skippedCount > 0 {
                return String(
                    localized:
                        "Restored \(itemCount) records from \(fileName). \(skippedCount) duplicate records skipped.")
            }
            return String(localized: "Restored \(itemCount) records from \(fileName).")
        case .backupExport:
            return String(
                localized: "Backup file \(fileName) with \(itemCount) records exported successfully.")
        case .dataExport:
            return String(localized: "Exported \(itemCount) records to \(fileName).")
        }
    }
}

/// 设置页弹窗状态：收敛重置/测试库/数据操作相关的确认框与结果提示
enum SettingsAlert: Identifiable {
    case resetConfirm
    case resetFailed(String)
    case seedConfirm
    case seedResult(String)
    case operationResult(DataOperationResult)

    var id: String {
        switch self {
        case .resetConfirm: return "resetConfirm"
        case .resetFailed: return "resetFailed"
        case .seedConfirm: return "seedConfirm"
        case .seedResult: return "seedResult"
        case .operationResult: return "operationResult"
        }
    }

    var title: String {
        switch self {
        case .resetConfirm:
            return String(localized: "Reset Vault?")
        case .resetFailed:
            return String(localized: "Reset Failed")
        case .seedConfirm:
            return String(localized: "Generate Test Vault?")
        case .seedResult:
            return String(localized: "Test Data Result")
        case .operationResult(let result):
            return result.title
        }
    }

    var message: String {
        switch self {
        case .resetConfirm:
            return String(
                localized: "This will clear Keychain and local vault data. This action cannot be undone.")
        case .resetFailed(let message):
            return message
        case .seedConfirm:
            return String(
                localized: "This will generate 40+ test entries (passwords, pincodes, and bank cards), at least one for each common app, and will not generate duplicates if they already exist.")
        case .seedResult(let message):
            return message
        case .operationResult(let result):
            return result.message
        }
    }
}

/// 设置页业务逻辑：回收站计数、Chrome CSV 导入、保险库重置
/// （测试库生成的种子数据仍在 SettingsView，正式版本随该功能一并移除）
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - 状态

    @Published var isImporting = false
    @Published var showingImportPicker = false
    @Published var trashedCount = 0
    @Published var alert: SettingsAlert?
    /// 最近一次加密备份包含的条目总数（供备份导出结果提示使用）
    @Published private(set) var lastBackupItemCount = 0

    // MARK: 备份恢复状态

    @Published var showingRestorePicker = false
    @Published var restoreFileURL: URL?
    @Published var isRestoring = false
    @Published var restoreError: String?
    @Published var showingRestorePasswordSheet = false

    // MARK: - 依赖（由 SettingsView 在 onAppear 注入）

    private weak var appState: AppState?
    private weak var vaultListViewModel: VaultListViewModel?
    private weak var safeNoteService: SafeNoteVaultService?

    func configure(
        appState: AppState,
        vaultListViewModel: VaultListViewModel,
        safeNoteService: SafeNoteVaultService
    ) {
        self.appState = appState
        self.vaultListViewModel = vaultListViewModel
        self.safeNoteService = safeNoteService
    }

    // MARK: - 回收站

    /// 当前密码条目（用于导入去重）
    private var passwordEntries: [PasswordEntry] {
        vaultListViewModel?.items.compactMap {
            guard case .password(let entry) = $0 else { return nil }
            return entry
        } ?? []
    }

    /// 加载回收站条目数量（vault items + safe notes）
    func loadTrashedCount() async {
        do {
            let trashedItems = try await vaultListViewModel?.loadTrashed() ?? []
            await safeNoteService?.loadTrashedNotes()
            trashedCount = trashedItems.count + (safeNoteService?.trashedNotes.count ?? 0)
        } catch {
            trashedCount = safeNoteService?.trashedNotes.count ?? 0
        }
    }

    // MARK: - 重置保险库

    /// 验证主密码后重置保险库
    ///
    /// 主密码错误时返回 `false`（不执行重置），验证通过则执行 `resetVault()` 并返回 `true`。
    func verifyAndReset(masterPassword: String) async -> Bool {
        do {
            try await appState?.verifyMasterPassword(masterPassword)
        } catch {
            return false
        }
        await resetVault()
        return true
    }

    func resetVault() async {
        do {
            try KeychainService().clearAll()
            UserDefaults.standard.removeObject(forKey: VaultKey.vaultInstalledMarker)
            try clearPasswordStore()
            Self.setSeedTestVaultGenerated(false)
            appState?.logout()
        } catch {
            alert = .resetFailed(error.localizedDescription)
        }
    }

    /// 批量清空密码相关的 Core Data 存储（条目、2FA 配置、标签）
    private func clearPasswordStore() throws {
        let context = CoreDataStack.shared.viewContext

        let deleteTwoFactor = NSBatchDeleteRequest(fetchRequest: CDTwoFactorConfig.fetchRequest())
        deleteTwoFactor.resultType = .resultTypeObjectIDs
        if let result = try context.execute(deleteTwoFactor) as? NSBatchDeleteResult,
            let objectIDs = result.result as? [NSManagedObjectID]
        {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [context]
            )
        }

        let deletePasswords = NSBatchDeleteRequest(fetchRequest: CDPasswordEntry.fetchRequest())
        deletePasswords.resultType = .resultTypeObjectIDs
        if let result = try context.execute(deletePasswords) as? NSBatchDeleteResult,
            let objectIDs = result.result as? [NSManagedObjectID]
        {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [context]
            )
        }

        let deleteTags = NSBatchDeleteRequest(fetchRequest: CDTag.fetchRequest())
        deleteTags.resultType = .resultTypeObjectIDs
        if let result = try context.execute(deleteTags) as? NSBatchDeleteResult,
            let objectIDs = result.result as? [NSManagedObjectID]
        {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [context]
            )
        }
    }

    // MARK: - 导入

    /// 处理文件选择器的结果
    func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importFile(from: url) }
        case .failure(let error):
            alert = .operationResult(
                DataOperationResult(
                    operation: .importItems,
                    succeeded: false,
                    fileName: "",
                    itemCount: 0,
                    skippedCount: 0,
                    errorMessage: "Failed to select file: \(error.localizedDescription)"
                )
            )
        }
    }

    /// 读取并导入文件，自动识别来源：本 app 导出的 CSV / JSON、Chrome CSV
    func importFile(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let result = try VaultImportService.parse(data: data)
            let fileName = url.lastPathComponent

            guard result.totalCount > 0 else {
                alert = .operationResult(
                    DataOperationResult(
                        operation: .importItems,
                        succeeded: false,
                        fileName: fileName,
                        itemCount: 0,
                        skippedCount: result.skippedCount,
                        errorMessage:
                            "No valid records were found to import in the file (skipped \(result.skippedCount) empty rows)."
                    )
                )
                return
            }

            let inserted = try await insert(parseResult: result)
            await vaultListViewModel?.loadItems()

            let skipped = result.totalCount - inserted + result.skippedCount
            alert = .operationResult(
                DataOperationResult(
                    operation: .importItems,
                    succeeded: true,
                    fileName: fileName,
                    itemCount: inserted,
                    skippedCount: skipped,
                    errorMessage: nil
                )
            )
        } catch {
            alert = .operationResult(
                DataOperationResult(
                    operation: .importItems,
                    succeeded: false,
                    fileName: url.lastPathComponent,
                    itemCount: 0,
                    skippedCount: 0,
                    errorMessage: "Import failed: \(error.localizedDescription)"
                )
            )
        }
    }

    /// 将统一解析结果去重入库，返回新增条数（复用 `VaultImportService.persist`）
    private func insert(parseResult result: VaultImportParseResult) async throws -> Int {
        try await VaultImportService.persist(
            parseResult: result,
            existingPasswords: passwordEntries,
            existingPincodes: pincodeEntries,
            existingBankcards: bankcardEntries,
            categories: vaultListViewModel?.categories ?? PasswordCategory.systemDefaults
        )
    }

    /// 当前 PIN 条目（用于导入去重）
    private var pincodeEntries: [PincodeEntry] {
        vaultListViewModel?.items.compactMap {
            guard case .pincode(let entry) = $0 else { return nil }
            return entry
        } ?? []
    }

    /// 当前银行卡条目（用于导入去重）
    private var bankcardEntries: [BankcardEntry] {
        vaultListViewModel?.items.compactMap {
            guard case .bankcard(let entry) = $0 else { return nil }
            return entry
        } ?? []
    }

    // MARK: - 备份恢复

    /// 处理备份文件选择器的结果：选中文件后先输入备份密码
    func handleRestorePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            restoreFileURL = url
            restoreError = nil
            // 等文件选择器完全收起后再弹密码输入框，避免系统级呈现冲突
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.showingRestorePasswordSheet = true
            }
        case .failure:
            // 用户取消选择
            break
        }
    }

    /// 从加密备份文件恢复密码条目
    func restoreBackup(password: String) async {
        guard let url = restoreFileURL, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent

            // PBKDF2 派生 + AES-GCM 解密为 CPU 密集操作，移出主线程；
            // 安全笔记按段惰性解密，附件明文不全部驻留内存
            let service = VaultBackupService()
            let reader = try await Task.detached(priority: .userInitiated) {
                try service.makeBackupReader(from: data, password: password)
            }.value

            if reader.isEmpty {
                showingRestorePasswordSheet = false
                alert = .operationResult(
                    DataOperationResult(
                        operation: .restoreItems,
                        succeeded: false,
                        fileName: fileName,
                        itemCount: 0,
                        skippedCount: 0,
                        errorMessage: String(localized: "This backup contains no entries.")
                    )
                )
                return
            }

            let inserted = try await insertRestored(reader: reader)
            await vaultListViewModel?.loadItems()
            await safeNoteService?.loadNotes()
            showingRestorePasswordSheet = false

            alert = .operationResult(
                DataOperationResult(
                    operation: .restoreItems,
                    succeeded: true,
                    fileName: fileName,
                    itemCount: inserted,
                    skippedCount: max(reader.totalCount - inserted, 0),
                    errorMessage: nil
                )
            )
        } catch let error as VaultBackupError {
            // 密码错误等失败：关闭密码弹窗并弹出对话框提示失败原因
            showingRestorePasswordSheet = false
            alert = .operationResult(
                DataOperationResult(
                    operation: .restoreItems,
                    succeeded: false,
                    fileName: url.lastPathComponent,
                    itemCount: 0,
                    skippedCount: 0,
                    errorMessage: error.localizedDescription
                )
            )
        } catch {
            showingRestorePasswordSheet = false
            alert = .operationResult(
                DataOperationResult(
                    operation: .restoreItems,
                    succeeded: false,
                    fileName: url.lastPathComponent,
                    itemCount: 0,
                    skippedCount: 0,
                    errorMessage: "Restore failed: \(error.localizedDescription)"
                )
            )
        }
    }

    /// 恢复的条目按类型入库：密码标记来源为备份恢复，按类型去重跳过已存在条目，
    /// 并将本机不存在的分类（如旧库的自定义分类）回落到默认分类
    private func insertRestored(reader: BackupReader) async throws -> Int {
        let categories = vaultListViewModel?.categories ?? PasswordCategory.systemDefaults
        let knownCategoryIDs = Set(categories.map(\.id))
        var insertedCount = 0

        // 密码条目：按站点名 + 用户名去重
        let passwordRepository: PasswordRepositoryProtocol = PasswordRepository()
        var seenPasswordKeys = Set(
            passwordEntries.map {
                Self.seedIdentity(siteName: $0.siteName, username: $0.username)
            }
        )
        for var entry in reader.passwords {
            let key = Self.seedIdentity(siteName: entry.siteName, username: entry.username)
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
            pincodeEntries.map { "\($0.title.lowercased())|\($0.pincode)" }
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
        var seenCardKeys = Set(bankcardEntries.map { normalizeCard($0.cardNumber) })
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

    // MARK: - 备份导出

    /// 将全部条目（密码 / PIN / 银行卡 / 安全笔记）加密为备份文件内容
    ///
    /// - Parameter password: 用户设置的备份密码（独立于主密码）
    /// - Returns: 完整的 .vgbackup 备份文件内容
    func createEncryptedBackup(password: String) async throws -> Data {
        async let passwords = PasswordRepository().fetchAll()
        async let pincodes = PincodeRepository().fetchAll()
        async let bankcards = BankcardRepository().fetchAll()
        let (resolvedPasswords, resolvedPincodes, resolvedBankcards) = try await (passwords, pincodes, bankcards)

        let service = VaultBackupService()
        // 笔记附件逐条解密/加密与 PBKDF2 派生均为 CPU/IO 密集操作，移出主线程；
        // 备份载荷分段加密，附件明文不全部驻留内存
        let exported = try await Task.detached(priority: .userInitiated) {
            try await service.exportData(
                passwords: resolvedPasswords,
                pincodes: resolvedPincodes,
                bankcards: resolvedBankcards,
                password: password
            )
        }.value
        lastBackupItemCount = exported.itemCount
        return exported.data
    }

    // MARK: - 种子数据标记（正式版本随测试库功能一并移除）

    private static let seedTestVaultFlagKey = "vaultgo.seedTestVaultGenerated"

    static func isSeedTestVaultGenerated() -> Bool {
        UserDefaults.standard.bool(forKey: seedTestVaultFlagKey)
    }

    static func setSeedTestVaultGenerated(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: seedTestVaultFlagKey)
    }

    /// 种子条目去重标识（站点名 + 用户名，忽略大小写）
    static func seedIdentity(siteName: String, username: String) -> String {
        "\(siteName.lowercased())|\(username.lowercased())"
    }
}
