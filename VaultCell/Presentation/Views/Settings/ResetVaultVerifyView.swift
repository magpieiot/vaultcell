/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ResetVaultVerifyView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 重置保险库前的主密码验证弹窗
///
/// 通过 `onVerifyAndReset` 回调执行「验证 + 重置」，
/// 返回 `true` 表示验证通过并已重置，弹窗自动关闭；
/// 返回 `false` 表示主密码错误，弹窗内提示错误。
struct ResetVaultVerifyView: View {
    @Environment(\.dismiss) private var dismiss

    /// 验证主密码并执行重置；返回是否成功
    let onVerifyAndReset: (String) async -> Bool

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var passwordFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Enter master password", text: $password)
                        .focused($passwordFocused)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                } header: {
                    Text("Verify Master Password")
                } footer: {
                    Text(
                        String(
                            localized:
                                "Your master password is required to confirm this action. This will clear Keychain and local vault data."
                        )
                    )
                }

                Section {
                    Button(action: submit) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Reset Vault")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(!canSubmit)
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
            .navigationTitle(String(localized: "Reset Vault"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                passwordFocused = true
            }
        }
    }

    private var canSubmit: Bool {
        !password.isEmpty && !isLoading
    }

    private func submit() {
        guard canSubmit else { return }
        errorMessage = nil
        isLoading = true

        Task {
            let success = await onVerifyAndReset(password)
            if success {
                dismiss()
            } else {
                errorMessage = String(localized: "Incorrect master password")
                password = ""
                isLoading = false
                passwordFocused = true
            }
        }
    }
}
