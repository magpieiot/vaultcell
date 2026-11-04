/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ChangeMasterPasswordView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import CryptoKit
import SwiftUI

/// 修改主密码弹窗：验证当前密码并校验新密码强度
///
/// 真正的主密码替换由 `AppState.changeMasterPassword(from:to:)` 完成：
/// 校验旧密码 → 用新密码派生的 KEK 重新包裹 DEK → 成对写入 Keychain。
/// 因此界面必须把错误如实回显——改密失败时库并没有变，静默关闭会让用户
/// 以为「已经改过了」，下次解锁直接失败。
struct ChangeMasterPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 改密成功提示：确认后才关闭弹窗，避免用户错过"已完成"的反馈
    @State private var didChangePassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("Enter current password", text: $currentPassword)
                        .textContentType(.password)
                        .disabled(isLoading)
                }

                Section {
                    SecureField("Enter new password", text: $newPassword)
                        .textContentType(.newPassword)
                        .disabled(isLoading)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .disabled(isLoading)

                    if !newPassword.isEmpty {
                        PasswordStrengthIndicator(
                            strength: PasswordStrength.calculate(for: newPassword))
                    }
                } header: {
                    Text("New Password")
                } footer: {
                    if let hint = requirementHint {
                        Text(hint)
                    }
                }

                Section {
                    Button(action: changePassword) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Change Password")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canChange)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle(AppLocale.string("Change Master Password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .alert(
                AppLocale.string("Master Password Changed"),
                isPresented: $didChangePassword
            ) {
                Button(AppLocale.string("OK")) { dismiss() }
            } message: {
                Text(
                    AppLocale.string("Use your new master password the next time you unlock the vault."))
            }
        }
    }

    private var canChange: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
            && PasswordStrength.calculate(for: newPassword).rawValue
                >= PasswordStrength.medium.rawValue
    }

    /// 按钮置灰时告诉用户「差在哪」：光靠禁用状态没有任何说明
    private var requirementHint: String? {
        guard !newPassword.isEmpty else { return nil }
        if !confirmPassword.isEmpty && newPassword != confirmPassword {
            return AppLocale.string("Passwords do not match.")
        }
        if PasswordStrength.calculate(for: newPassword).rawValue
            < PasswordStrength.medium.rawValue
        {
            // 中强度（score >= 4）的达成路径：长度 + 多种字符类型
            return AppLocale.string("Use at least 8 characters and mix upper/lower case letters, digits and symbols."
            )
        }
        return nil
    }

    private func changePassword() {
        guard canChange else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await appState.changeMasterPassword(from: currentPassword, to: newPassword)
                // 改密成功后立刻清空内存中的明文密码，只留提示弹窗
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
                isLoading = false
                didChangePassword = true
            } catch {
                errorMessage = Self.friendlyMessage(for: error)
                // 当前密码已错，清空避免反复提交同一次输入；新密码保留，便于只改一处重试
                currentPassword = ""
                isLoading = false
            }
        }
    }

    /// 把底层错误翻译成用户看得懂的话（与解锁页保持同一口径）
    private static func friendlyMessage(for error: Error) -> String {
        // AES-GCM 认证失败即旧密码不对（DEK 解不出来）
        if let cryptoError = error as? CryptoKitError, case .authenticationFailure = cryptoError {
            return AppLocale.string("That's not the right master password. Try again.")
        }
        if error is UnlockThrottledError {
            return AppLocale.string("Too many attempts. Try again later.")
        }
        return AppLocale.string("Something went wrong. Please try again.")
    }
}

#Preview {
    ChangeMasterPasswordView()
        .environmentObject(AppState())
}
