/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// DataManagementView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import SwiftUI
import UniformTypeIdentifiers

/// 数据管理子页：备份和恢复、导入和导出、iCloud 同步。
/// 导入会自动识别来源（本 app 导出的 CSV / JSON、Chrome CSV）。
struct DataManagementView: View {

    /// 导入状态与备份恢复状态由设置页共享的 ViewModel 提供
    @ObservedObject var settingsVM: SettingsViewModel

    @State private var iCloudSyncEnabled = true

    /// 导出备份：密码弹窗 → 生成加密内容 → 系统保存面板
    @State private var showingExportPasswordSheet = false
    @State private var showingExporter = false
    @State private var exportDocument: VaultBackupDocument?
    /// 密码弹窗关闭后待调起保存面板的备份内容
    @State private var pendingExportDocument: VaultBackupDocument?
    /// 本次备份生成的文件名（保存面板与结果对话框共用，避免时间戳不一致）
    @State private var backupFileName = ""

    /// 明文导出（CSV / JSON）：分类勾选界面
    @State private var showingExportSheet = false

    var body: some View {
        List {
            backupSection
            importExportSection
            syncSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground())
        .navigationTitle(String(localized: "Data Management"))
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
        // 明文导出（CSV / JSON）
        .sheet(isPresented: $showingExportSheet) {
            ExportDataView(settingsVM: settingsVM)
        }
        // 导入：自动识别来源
        .fileImporter(
            isPresented: $settingsVM.showingImportPicker,
            allowedContentTypes: [.commaSeparatedText, .text, .json, .data],
            allowsMultipleSelection: false
        ) { result in
            settingsVM.handleImportResult(result)
        }
        // 备份恢复：先选择 .vgbackup 文件
        .fileImporter(
            isPresented: $settingsVM.showingRestorePicker,
            allowedContentTypes: [.vaultBackup, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            settingsVM.handleRestorePickerResult(result)
        }
        // 备份恢复：选择文件后输入备份密码
        .sheet(isPresented: $settingsVM.showingRestorePasswordSheet) {
            BackupRestorePasswordView(settingsVM: settingsVM) { password in
                Task { await settingsVM.restoreBackup(password: password) }
            }
        }
        // 加密备份导出：先设置备份密码
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
    }

    // MARK: - 备份和恢复

    /// 加密备份导出 / 从加密备份恢复
    private var backupSection: some View {
        Section(String(localized: "Backup & Restore")) {
            // 备份：导出加密的 .vgbackup，用于整机恢复
            Button(action: {
                showingExportPasswordSheet = true
            }) {
                CustomLabel(
                    leadingIcon: "arrow.down.doc.fill", leadingIconColor: .secondaryBrandColor,
                    trailingIcon: "chevron.right", text: "Backup")
            }
            .disabled(settingsVM.isImporting || settingsVM.isRestoring)

            // 恢复：选择 .vgbackup 文件并输入备份密码后导入条目
            Button(action: {
                settingsVM.showingRestorePicker = true
            }) {
                if settingsVM.isRestoring {
                    HStack(spacing: 8) {
                        ProgressView()
                            .frame(width: 24, height: 24)
                        Text(String(localized: "Restoring..."))
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                } else {
                    CustomLabel(
                        leadingIcon: "arrow.uturn.left.circle", leadingIconColor: .secondaryBrandColor,
                        trailingIcon: "chevron.right", text: "Restore")
                }
            }
            .disabled(settingsVM.isImporting || settingsVM.isRestoring)
        }
    }

    // MARK: - 导入和导出

    /// 导入（自动识别来源）/ 明文导出（CSV / JSON）
    private var importExportSection: some View {
        Section(String(localized: "Import & Export")) {
            // 导入：自动识别本 app 导出的 CSV/JSON 与 Chrome CSV
            Button(action: {
                settingsVM.showingImportPicker = true
            }) {
                if settingsVM.isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .frame(width: 24, height: 24)
                        Text(String(localized: "Importing..."))
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                } else {
                    CustomLabel(
                        leadingIcon: "tray.and.arrow.down", leadingIconColor: .secondaryBrandColor,
                        trailingIcon: "chevron.right", text: "Import")
                }
            }
            .disabled(settingsVM.isImporting || settingsVM.isRestoring)

            // 导出：按分类勾选，生成明文 CSV / JSON，用于迁移到其他密码管理器
            Button(action: {
                showingExportSheet = true
            }) {
                CustomLabel(
                    leadingIcon: "square.and.arrow.up", leadingIconColor: .secondaryBrandColor,
                    trailingIcon: "chevron.right", text: "Export")
            }
            .disabled(settingsVM.isImporting || settingsVM.isRestoring)
        }
    }

    // MARK: - iCloud 同步

    /// iCloud 同步开关（正式版本接入实现）
    private var syncSection: some View {
        Section {
            Toggle(isOn: $iCloudSyncEnabled) {
                CustomLabel(
                    leadingIcon: "icloud", leadingIconColor: .secondaryBrandColor,
                    text: "iCloud sync"
                )
            }
            .tint(.primaryBrandColor)
        }
    }

    /// 备份导出默认文件名（时间戳后缀，避免同名覆盖）
    private static func makeBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "VaultGo-Backup-\(formatter.string(from: Date()))"
    }
}

// MARK: - 导出备份密码弹窗

/// 设置备份密码并生成加密备份：密码 + 确认 + 强度提示，
/// 生成成功后回调备份内容，由父视图调起系统保存面板。
private struct BackupExportPasswordView: View {
    @ObservedObject var settingsVM: SettingsViewModel
    let onBackupReady: (VaultBackupDocument) -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    private enum Field { case password, confirmPassword }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // 说明：备份密码独立于保险库主密码
                    Label {
                        Text(String(localized: "Set a password to encrypt this backup file. It is separate from your master password."))
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
                            placeholder: String(localized: "At least 8 characters"),
                            isFocused: focusedField == .password,
                            hasError: errorMessage != nil
                        )
                        .focused($focusedField, equals: .password)
                        .textContentType(.oneTimeCode)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmPassword }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Confirm Password"))
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                        AuthSecureField(
                            text: $confirmPassword,
                            placeholder: String(localized: "Re-enter backup password"),
                            isFocused: focusedField == .confirmPassword,
                            hasError: errorMessage != nil
                        )
                        .focused($focusedField, equals: .confirmPassword)
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                    }

                    PrimaryActionButton(
                        title: String(localized: "Export"),
                        isLoading: isWorking,
                        isEnabled: canSubmit
                    ) {
                        submit()
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.errorColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "Export Encrypted Backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .password
                }
            }
        }
    }

    private var canSubmit: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && !isWorking
    }

    private func submit() {
        guard !isWorking else { return }

        guard password.count >= 8 else {
            errorMessage = String(localized: "Password must be at least 8 characters.")
            return
        }
        guard password == confirmPassword else {
            errorMessage = String(localized: "Passwords do not match.")
            return
        }
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                let data = try await settingsVM.createEncryptedBackup(password: password)
                onBackupReady(VaultBackupDocument(data: data))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 恢复备份密码弹窗

/// 输入备份密码以解密恢复；密码错误时保持弹窗打开并内联提示。
private struct BackupRestorePasswordView: View {
    @ObservedObject var settingsVM: SettingsViewModel
    let onConfirm: (String) -> Void

    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // 说明：备份密码独立于当前保险库主密码
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
                            hasError: settingsVM.restoreError != nil
                        )
                        .focused($focused)
                        // 与认证页一致：禁用键盘强密码建议
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                    }

                    if let error = settingsVM.restoreError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.errorColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryActionButton(
                        title: String(localized: "Restore"),
                        isLoading: settingsVM.isRestoring,
                        isEnabled: !password.isEmpty && !settingsVM.isRestoring
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
                        settingsVM.showingRestorePasswordSheet = false
                    }
                }
            }
            .interactiveDismissDisabled(settingsVM.isRestoring)
            .onAppear {
                settingsVM.restoreError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focused = true
                }
            }
        }
    }

    private func submit() {
        guard !password.isEmpty, !settingsVM.isRestoring else { return }
        onConfirm(password)
    }
}
