/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SettingsViewModel.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import Combine
import CoreData
import Foundation
import UniformTypeIdentifiers

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
        case (.importItems, true): return AppLocale.string("Import Successful")
        case (.importItems, false): return AppLocale.string("Import Failed")
        case (.restoreItems, true): return AppLocale.string("Restore Successful")
        case (.restoreItems, false): return AppLocale.string("Restore Failed")
        case (.backupExport, true): return AppLocale.string("Backup Successful")
        case (.backupExport, false): return AppLocale.string("Backup Failed")
        case (.dataExport, true): return AppLocale.string("Export Successful")
        case (.dataExport, false): return AppLocale.string("Export Failed")
        }
    }

    var message: String {
        if let errorMessage {
            return errorMessage
        }
        switch operation {
        case .importItems:
            if skippedCount > 0 {
                return AppLocale.string("Imported \(itemCount) records from \(fileName). \(skippedCount) duplicate or invalid records skipped.")
            }
            return AppLocale.string("Imported \(itemCount) records from \(fileName).")
        case .restoreItems:
            if skippedCount > 0 {
                return AppLocale.string("Restored \(itemCount) records from \(fileName). \(skippedCount) duplicate records skipped.")
            }
            return AppLocale.string("Restored \(itemCount) records from \(fileName).")
        case .backupExport:
            return AppLocale.string("Backup file \(fileName) with \(itemCount) records exported successfully.")
        case .dataExport:
            return AppLocale.string("Exported \(itemCount) records to \(fileName).")
        }
    }
}

/// 文件选择器的用途：导入与备份恢复**共用**同一个 `fileImporter`
///
/// 同一层级挂两个 `fileImporter` 时，系统只认最后一个（导入入口点了没有反应），
/// 因此统一成一个选择器，按用途切换可选文件类型并路由回调。
enum DataFilePickerMode {
    /// 导入条目（自动识别本 app 导出的 CSV / JSON 与 Chrome CSV）
    case importFile
    /// 选择 .vgbackup 备份文件用于恢复
    case restoreBackup
}

/// 重置密码库的结果
enum ResetVaultOutcome {
    /// 已清空钥匙串与本地数据并注销，App 回到「创建密码库」流程
    case reset
    /// 主密码错误，未做任何破坏性操作
    case incorrectPassword
    /// 钥匙串清除失败：密码库保持原样，界面提示原因
    case failed(String)
}

/// 设置页弹窗状态：收敛重置/测试库/数据操作相关的确认框与结果提示
enum SettingsAlert: Identifiable {
    case resetConfirm
    /// 清除 iCloud 云端数据的二次确认
    case clearICloudConfirm
    /// 清除 iCloud 云端数据的结果
    case clearICloudResult(succeeded: Bool, message: String)
    #if DEBUG
    /// 生成测试库（仅 Debug 包）
    case seedConfirm
    case seedResult(String)
    #endif
    case operationResult(DataOperationResult)

    var id: String {
        switch self {
        case .resetConfirm: return "resetConfirm"
        case .clearICloudConfirm: return "clearICloudConfirm"
        case .clearICloudResult: return "clearICloudResult"
        #if DEBUG
        case .seedConfirm: return "seedConfirm"
        case .seedResult: return "seedResult"
        #endif
        case .operationResult: return "operationResult"
        }
    }

    var title: String {
        switch self {
        case .resetConfirm:
            return AppLocale.string("Reset Vault?")
        case .clearICloudConfirm:
            return AppLocale.string("Clear iCloud Data?")
        case .clearICloudResult(let succeeded, _):
            return succeeded
                ? AppLocale.string("iCloud Data Cleared")
                : AppLocale.string("Clear Failed")
        #if DEBUG
        case .seedConfirm:
            return AppLocale.string("Generate Test Vault?")
        case .seedResult:
            return AppLocale.string("Test Data Result")
        #endif
        case .operationResult(let result):
            return result.title
        }
    }

    var message: String {
        switch self {
        case .resetConfirm:
            return AppLocale.string("This will clear Keychain and local vault data. This action cannot be undone.")
        case .clearICloudConfirm:
            return AppLocale.string("This deletes the encrypted vault data stored in your private iCloud account on all your devices. Data on this device is kept, and iCloud sync will be turned off.")
        case .clearICloudResult(_, let message):
            return message
        #if DEBUG
        case .seedConfirm:
            return AppLocale.string("This will generate 40+ test entries (passwords, pincodes, and bank cards), at least one for each common app, and will not generate duplicates if they already exist.")
        case .seedResult(let message):
            return message
        #endif
        case .operationResult(let result):
            return result.message
        }
    }
}

/// 设置页业务逻辑：回收站计数、Chrome CSV 导入、密码库重置
/// （测试库生成的种子数据仍在 SettingsView，正式版本随该功能一并移除）
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - 状态

    @Published var isImporting = false
    @Published var trashedCount = 0
    @Published var alert: SettingsAlert?
    /// 最近一次加密备份包含的条目总数（供备份导出结果提示使用）
    @Published private(set) var lastBackupItemCount = 0

    // MARK: 文件选择器状态

    @Published var showingFilePicker = false
    /// 当前文件选择器用途（回调时先读取再清除）
    @Published var filePickerMode: DataFilePickerMode?

    // MARK: 备份恢复状态

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

    // MARK: - 重置密码库

    /// 验证主密码后重置密码库
    ///
    /// 只有主密码验证通过才进入破坏性流程；验证失败不做任何改动。
    func verifyAndReset(masterPassword: String) async -> ResetVaultOutcome {
        do {
            try await appState?.verifyMasterPassword(masterPassword)
        } catch {
            return .incorrectPassword
        }
        return await resetVault()
    }

    /// 重置密码库：清空钥匙串 + 全部本地数据，并把 App 带回「创建密码库」流程
    ///
    /// 两步的顺序与容错是这里的关键：
    /// 1. 钥匙串是「密码库是否存在」的唯一凭据，也是唯一不可回滚的一步。
    ///    它清除失败说明库还完好，此时绝不能再碰数据，直接报错返回。
    /// 2. 钥匙串一旦清除，旧库就再也解不开，因此后续清理即使部分失败也必须
    ///    继续走完并注销——否则会停在「已解锁、密钥已丢、数据还在」的僵尸状态。
    @discardableResult
    func resetVault() async -> ResetVaultOutcome {
        // 先断开 iCloud 同步：重置过程中不该再有同步任务读写即将被清空的库
        await appState?.setCloudSyncEnabled(false)

        do {
            try KeychainService().clearAll()
        } catch {
            return .failed(error.localizedDescription)
        }

        clearLocalVaultData()
        clearVaultScopedState()

        // 系统侧自动填充身份是库内容的镜像，库清空后重新同步即为移除
        Task { await AutoFillIdentityService.shared.synchronize() }

        appState?.logout()
        return .reset
    }

    /// 清空全部本地密码库数据（密码 / 2FA / OAuth / PIN / 银行卡 / 标签 / 安全笔记 / 分类）
    ///
    /// 顺序不能随意：2FA 与 OAuth 配置是从属于密码条目的子实体，直接批量删除它们会触发
    /// Core Data 的 `Constraint trigger violation: ... mandatory OTO nullify inverse`（134050），
    /// 整条重置链就此中断——历史 bug 正是这样「报错弹窗 + 钥匙串已被清空」。
    /// 因此先删父实体（由模型的 Cascade 规则带走子实体与标签关联），再兜底删一遍残留子实体。
    /// 单项失败只记录不中断：钥匙串已经清了，此时回滚没有任何意义。
    private func clearLocalVaultData() {
        let entities = [
            "CDPasswordEntry",  // 级联带走 2FA / OAuth / 标签关联
            "CDTwoFactorConfig",  // 兜底：孤儿 2FA 配置
            "CDOAuthProvider",  // 兜底：孤儿 OAuth 配置
            "CDPincodeEntry",
            "CDBankcardEntry",
            "CDTag",
            "CDSafeNote",  // 级联带走附件记录
            "CDSafeNoteAsset",  // 兜底：孤儿附件记录
            "CDPasswordCategory",  // 下次加载分类时由 ensureDefaults 重建系统分类
        ]

        for entity in entities {
            do {
                try batchDelete(entity)
            } catch {
                NSLog("Reset: 清空 %@ 失败（继续后续步骤）: %@", entity, error.localizedDescription)
            }
        }

        // 笔记附件的密文存在 App Group 目录里，不会随 Core Data 记录一起消失
        do {
            try EncryptedFileStorage().deleteAllFiles()
        } catch {
            NSLog("Reset: 清空安全笔记附件失败: %@", error.localizedDescription)
        }
    }

    /// 批量删除单个实体并同步到 viewContext（让界面立即感知删除）
    private func batchDelete(_ entityName: String) throws {
        let context = CoreDataStack.shared.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs

        guard let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
            let objectIDs = result.result as? [NSManagedObjectID]
        else {
            return
        }

        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
            into: [context]
        )
    }

    /// 清空与「这一个密码库」绑定的本地状态：安装标记、库标识、同步游标、搜索历史
    ///
    /// 漏清 vaultID / 同步状态会让新建的库继承旧库的 CloudKit zone 与删除记录。
    private func clearVaultScopedState() {
        let defaults = UserDefaults.standard
        let keys = [
            VaultKey.vaultInstalledMarker,
            VaultKey.vaultID,
            VaultKey.cloudKeyRevision,
            VaultKey.iCloudSyncEnabled,
            VaultKey.pendingCloudRestoreDownload,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }

        SyncLocalStore.shared.resetForVaultReset()
        // 搜索历史里留着旧库的站点名，一并清掉
        SearchHistoryStore.clearAll()
        Self.setSeedTestVaultGenerated(false)
    }

    // MARK: - iCloud 云端数据清除

    /// 清除 iCloud 云端同步数据：先停同步引擎，再删 zone 与订阅，最后复位本机同步游标。
    ///
    /// 本地密码库、钥匙串与登录状态不变。删除失败时不复位游标，
    /// 以免下次同步丢失比对基线、把云端残留记录当成新数据重复写入。
    func clearICloudData() async {
        await appState?.setCloudSyncEnabled(false)
        do {
            try await CloudVaultClearService().clearCloudData()
        } catch {
            alert = .clearICloudResult(succeeded: false, message: error.localizedDescription)
            return
        }
        SyncLocalStore.shared.resetForVaultReset()
        UserDefaults.standard.removeObject(forKey: VaultKey.pendingCloudRestoreDownload)
        alert = .clearICloudResult(
            succeeded: true,
            message: AppLocale.string("iCloud data has been cleared. Data on this device is kept.")
        )
    }

    // MARK: - 文件选择器

    /// 文件选择器可选类型：随用途切换
    var filePickerContentTypes: [UTType] {
        switch filePickerMode {
        case .importFile:
            // 自动识别本 app 导出的 CSV / JSON 与 Chrome CSV
            return [.commaSeparatedText, .text, .json, .data]
        case .restoreBackup:
            return [.vaultBackup, .data, .item]
        case nil:
            // 不会展示，取最宽松的类型兜底，避免空数组触发断言
            return [.data]
        }
    }

    /// 调起文件选择器：导入
    func presentImportPicker() {
        filePickerMode = .importFile
        showingFilePicker = true
    }

    /// 调起文件选择器：备份恢复
    func presentRestorePicker() {
        filePickerMode = .restoreBackup
        showingFilePicker = true
    }

    /// 文件选择器回调：按用途分流（先取用途再清除，避免读取到 nil）
    func handleFilePickerResult(_ result: Result<[URL], Error>) {
        let mode = filePickerMode
        filePickerMode = nil
        switch mode {
        case .importFile:
            handleImportResult(result)
        case .restoreBackup:
            handleRestorePickerResult(result)
        case nil:
            break
        }
    }

    // MARK: - 导入

    /// 处理文件选择器的结果
    private func handleImportResult(_ result: Result<[URL], Error>) {
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
    private func handleRestorePickerResult(_ result: Result<[URL], Error>) {
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
                        errorMessage: AppLocale.string("This backup contains no entries.")
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

    private static let seedTestVaultFlagKey = "vaultcell.seedTestVaultGenerated"

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
