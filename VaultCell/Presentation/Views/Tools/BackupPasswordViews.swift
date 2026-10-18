/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// BackupPasswordViews.swift
/// created on: 23/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 设置备份密码并生成加密备份：密码 + 确认 + 强度提示，
/// 生成成功后回调备份内容，由父视图调起系统保存面板。
struct BackupExportPasswordView: View {
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
                    // 说明：备份密码独立于密码库主密码
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

/// 输入备份密码以解密恢复；密码错误时保持弹窗打开并内联提示。
struct BackupRestorePasswordView: View {
    @ObservedObject var settingsVM: SettingsViewModel
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
