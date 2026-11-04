/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ResetVaultVerifyView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 重置密码库前的主密码验证弹窗
///
/// 通过 `onVerifyAndReset` 回调执行「验证 + 重置」：
/// 返回 `.reset` 表示已重置，弹窗自动关闭；返回 `.incorrectPassword` 在弹窗内提示密码错误；
/// 返回 `.failed` 展示具体失败原因（例如钥匙串清除失败，此时密码库未被改动）。
struct ResetVaultVerifyView: View {
    @Environment(\.dismiss) private var dismiss

    /// 验证主密码并执行重置
    let onVerifyAndReset: (String) async -> ResetVaultOutcome

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
                        AppLocale.string("Your master password is required to confirm this action. This will clear Keychain and local vault data."
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
            .navigationTitle(AppLocale.string("Reset Vault"))
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
            switch await onVerifyAndReset(password) {
            case .reset:
                dismiss()
            case .incorrectPassword:
                errorMessage = AppLocale.string("Incorrect master password")
                password = ""
                isLoading = false
                passwordFocused = true
            case .failed(let message):
                // 钥匙串没能清掉：密码库仍然完好，留在本页让用户看清原因
                errorMessage = message
                isLoading = false
            }
        }
    }
}
