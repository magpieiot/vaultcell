import SwiftUI

/// 已完成 iCloud 密钥材料安装后的首次下载页，避免在数据到达前展示空密码库。
struct CloudVaultRestoreView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.primaryBrandColor.opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(.primaryBrandColor)
            }

            VStack(spacing: 10) {
                Text(AppLocale.string("Restoring from iCloud..."))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(
                    AppLocale.string(
                        "Downloading your encrypted passwords and notes. Keep VaultCell open until this finishes."
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            }

            if appState.isRestoringCloudVault {
                ProgressView()
                    .controlSize(.large)
                    .padding(.top, 8)
            } else if let error = appState.cloudRestoreError {
                VStack(spacing: 14) {
                    Label(
                        AppLocale.string("Couldn't finish iCloud restore"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 28)
                }
            }

            Spacer()

            if !appState.isRestoringCloudVault {
                VStack(spacing: 12) {
                    Button {
                        Task { await appState.retryCloudVaultRestore() }
                    } label: {
                        Text(AppLocale.string("Try Again"))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.primaryBrandColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.continueWithoutCloudRestore()
                    } label: {
                        Text(AppLocale.string("Continue Without iCloud"))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
