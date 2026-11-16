/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CloudSyncView.swift
/// created on: 04/11/2026
/// ------------------------------------------------------------------

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 「同步与备份」子页：顶部说明卡片 + iCloud 同步状态卡片 + 备份与恢复入口。
///
/// 设置 / 导入 / 导出三个阶段只由 `AppState` 的真实同步回执推导，
/// 不使用计时器推测云端进度；开关与重试直连现有的 CKSyncEngine 链路。
/// 加密备份与恢复的全套弹窗也挂在本页，避免由工具中心在被 push 遮住后弹出。
struct CloudSyncView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vaultListViewModel: VaultListViewModel
    @EnvironmentObject private var safeNoteService: SafeNoteVaultService
    @Environment(\.dismiss) private var dismiss

    /// 本页独立持有数据操作 ViewModel，避免与工具中心的导入状态互相串改
    @StateObject private var settingsVM = SettingsViewModel()

    /// 加密备份导出走「设密码 → 系统保存面板」两步
    @State private var showingExportPasswordSheet = false
    @State private var showingExporter = false
    @State private var exportDocument: VaultBackupDocument?
    /// 密码弹窗关闭后待调起保存面板的备份内容
    @State private var pendingExportDocument: VaultBackupDocument?
    /// 本次备份生成的文件名（保存面板与结果对话框共用，避免时间戳不一致）
    @State private var backupFileName = ""

    /// 与主 App 保持同一个强调色
    private let accent = Color.appAccent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Sync & Backup")
                    .font(.appTitle)

                heroCard

                Text("iCloud sync")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)

                statusCard

                Text("Turning off iCloud sync keeps the data on this device, but changes will no longer sync to your other devices.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)

                backupSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        // 保留系统导航栏（可侧滑返回），但用参考图中的圆形返回按钮替换默认样式
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backButton }
        }
        // 二级页面隐藏底部浮动 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(cardColor))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
    }

    // MARK: - 说明卡片

    private var heroCard: some View {
        VStack(spacing: 14) {
            Image(systemName: syncSymbol)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(accent)
                .frame(height: 62)

            Text("Keep your data in sync")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Your data stays up to date across all your devices and moves with you when you switch to a new one. It is stored in your private iCloud account.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 26)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var syncSymbol: String {
        safeSymbol("clock.arrow.2.circlepath", fallback: "arrow.triangle.2.circlepath")
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: syncEnabled) {
                Text("iCloud sync")
                    .font(.system(size: 17))
            }
            .tint(.successColor)
            .disabled(appState.syncStatus == .inProgress)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)

            rowDivider

            if let message = errorMessage {
                errorRow(message: message)
                rowDivider
            }

            statusRow(title: "Setup", value: setupStatus)
            rowDivider
            statusRow(title: "Import", value: transferStatus)
            rowDivider
            statusRow(title: "Export", value: transferStatus)
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var syncEnabled: Binding<Bool> {
        Binding(
            get: { appState.isCloudSyncEnabled },
            set: { enabled in
                Task { await appState.setCloudSyncEnabled(enabled) }
            }
        )
    }

    private var errorMessage: String? {
        if case .failed(let message) = appState.syncStatus { return message }
        return nil
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Error")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.errorColor)
                Spacer(minLength: 12)
                Button {
                    Task { await appState.retryCloudSync() }
                } label: {
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func statusRow(title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 17))
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 20)
    }

    private var cardColor: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    // MARK: - 备份与恢复

    /// 参考图下半部分：分组标题 + 两行入口卡片 + 灰色说明。
    /// 入口直接触发原有的加密备份 / 备份恢复流程，不再另建一级页面。
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backup & Restore")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            VStack(spacing: 0) {
                backupEntry(
                    icon: safeSymbol("arrow.down.doc", fallback: "doc.text"),
                    title: "Backup",
                    subtitle: "Encrypted backup file (.vgbackup)"
                ) {
                    showingExportPasswordSheet = true
                }

                rowDivider

                backupEntry(
                    icon: safeSymbol(
                        "clock.arrow.circlepath", fallback: "arrow.counterclockwise.circle"),
                    title: "Restore",
                    subtitle: nil
                ) {
                    settingsVM.presentRestorePicker()
                }
            }
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Backup files are independent of iCloud sync. You can create an encrypted backup at any time, whether or not iCloud sync is on.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
        // 相关弹窗挂在备份分组这一层：与工具中心的导入选择器处于不同视图分支，
        // 避免同一层级挂两个 fileImporter 时系统只认最后一个。
        .sheet(isPresented: $showingExportPasswordSheet) {
            BackupExportPasswordView(settingsVM: settingsVM) { document in
                pendingExportDocument = document
            }
        }
        .onChange(of: showingExportPasswordSheet) { _, showing in
            // 密码弹窗关闭后（生成成功），调起系统保存面板
            if !showing, let document = pendingExportDocument {
                pendingExportDocument = nil
                exportDocument = document
                backupFileName = Self.makeBackupFilename()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingExporter = true
                }
            }
        }
        .fileImporter(
            isPresented: $settingsVM.showingFilePicker,
            allowedContentTypes: settingsVM.filePickerContentTypes,
            allowsMultipleSelection: false
        ) { result in
            settingsVM.handleFilePickerResult(result)
        }
        .sheet(isPresented: $settingsVM.showingRestorePasswordSheet) {
            BackupRestorePasswordView(settingsVM: settingsVM) { password in
                Task { await settingsVM.restoreBackup(password: password) }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .vaultBackup,
            defaultFilename: backupFileName
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                settingsVM.alert = .operationResult(
                    DataOperationResult(
                        operation: .backupExport,
                        succeeded: true,
                        fileName: backupFileName + ".vgbackup",
                        itemCount: settingsVM.lastBackupItemCount,
                        skippedCount: 0,
                        errorMessage: nil
                    )
                )
            case .failure(let error):
                settingsVM.alert = .operationResult(
                    DataOperationResult(
                        operation: .backupExport,
                        succeeded: false,
                        fileName: backupFileName + ".vgbackup",
                        itemCount: 0,
                        skippedCount: 0,
                        errorMessage: "Export failed: \(error.localizedDescription)"
                    )
                )
            }
        }
        .alert(item: $settingsVM.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(AppLocale.string("OK")))
            )
        }
        .onAppear {
            settingsVM.configure(
                appState: appState,
                vaultListViewModel: vaultListViewModel,
                safeNoteService: safeNoteService
            )
        }
    }

    private func backupEntry(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 23))
                    .foregroundStyle(Color.primaryBrandColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(settingsVM.isRestoring)
    }

    /// 备份导出默认文件名（时间戳后缀，避免同名覆盖）
    private static func makeBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "VaultCell-Backup-\(formatter.string(from: Date()))"
    }

    /// SF Symbol 在个别系统版本可能缺失，退回同义符号避免出现空白图标
    private func safeSymbol(_ preferred: String, fallback: String) -> String {
        UIImage(systemName: preferred) == nil ? fallback : preferred
    }

    // MARK: - 状态文案

    /// CloudKit 引擎初始化对应「设置」阶段；失败时它先于导入 / 导出中断。
    private var setupStatus: String {
        switch appState.syncStatus {
        case .idle:
            return appState.isCloudSyncEnabled
                ? AppLocale.string("Enabled") : AppLocale.string("Not started")
        case .inProgress:
            return AppLocale.string("Sync in progress...")
        case .completed:
            return completedStatus
        case .failed:
            return failedStatus
        }
    }

    /// 一次 `synchronize()` 同时包含从 iCloud 拉取与向 iCloud 推送，两个阶段共用同一份回执。
    private var transferStatus: String {
        switch appState.syncStatus {
        case .inProgress:
            return AppLocale.string("Sync in progress...")
        case .completed:
            return completedStatus
        default:
            return AppLocale.string("Not started")
        }
    }

    private var completedStatus: String {
        guard appState.lastSyncDate != nil else { return AppLocale.string("Sync completed") }
        return String(format: AppLocale.string("Completed: %@"), statusTime)
    }

    private var failedStatus: String {
        guard appState.lastSyncDate != nil else { return AppLocale.string("Sync failed") }
        return String(format: AppLocale.string("Failed: %@"), statusTime)
    }

    /// 用系统相对日期格式得到「今天 12:52 / Today, 12:52」这类展示文本。
    private var statusTime: String {
        guard let date = appState.lastSyncDate else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguage.current.bcp47 ?? Locale.current.identifier)
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
