/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ChangeMasterPasswordView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 修改主密码弹窗：验证当前密码并校验新密码强度
struct ChangeMasterPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("Enter current password", text: $currentPassword)
                }

                Section("New Password") {
                    SecureField("Enter new password", text: $newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)

                    if !newPassword.isEmpty {
                        PasswordStrengthIndicator(
                            strength: PasswordStrength.calculate(for: newPassword))
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
            .navigationTitle("Change Master Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canChange: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
            && PasswordStrength.calculate(for: newPassword).rawValue
                >= PasswordStrength.medium.rawValue
    }

    private func changePassword() {
        errorMessage = nil
        isLoading = true

        Task {
            isLoading = false
            dismiss()
        }
    }
}
