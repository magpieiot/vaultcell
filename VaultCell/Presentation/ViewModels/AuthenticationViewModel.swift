/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AuthenticationViewModel.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import LocalAuthentication
import Combine
import CryptoKit
import Security



enum BiometricType {
    case none
    case faceID
    case touchID
    case opticID

    var displayName: String {
        switch self {
        case .none:
            return AppLocale.string("None")
        case .faceID:
            return AppLocale.string("Face ID")
        case .touchID:
            return AppLocale.string("Touch ID")
        case .opticID:
            return AppLocale.string("Optic ID")
        }
    }
}

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var masterPassword: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    @Published var errorMessage: String?
    @Published var validationError: String = ""
    @Published var isLoading: Bool = false
    @Published private(set) var vaultMaterialInstalled = false
    
    private let appState: AppState
    /// 本页的 toast 提示中心：失败原因一律走 toast，不再用内联红字
    private let toastCenter: ToastCenter
    
    var biometricType: BiometricType {
        switch BiometricService.shared.biometricType {
        case .none:
            return .none
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        }
    }
    
    var hasExistingVault: Bool {
        appState.hasExistingVault
    }
    
    var passwordStrength: PasswordStrength {
        PasswordStrength.calculate(for: newPassword)
    }
    
    var passwordHint: String {
        if newPassword.isEmpty {
            return ""
        } else if newPassword.count < 8 {
            return "Password must be at least 8 characters"
        } else {
            return ""
        }
    }
    
    var canCreateVault: Bool {
        !newPassword.isEmpty &&
        newPassword.count >= 8 &&
        newPassword == confirmPassword &&
        passwordStrength.rawValue >= PasswordStrength.medium.rawValue
    }
    
    var canUnlock: Bool {
        // 冷却剩余秒数取自 AppState（> 0 时冻结输入）；每秒刷新由界面侧订阅 AppState 完成
        !masterPassword.isEmpty && appState.unlockCooldownRemaining <= 0
    }
    
    init(appState: AppState, toastCenter: ToastCenter) {
        self.appState = appState
        self.toastCenter = toastCenter
    }
    
    func unlock() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await appState.unlockVault(with: masterPassword)
        } catch {
            // 密码框标红与 toast 用同一句话，避免两种表述打架
            let message = Self.friendlyMessage(for: error)
            errorMessage = message
            showFailureToast(message)
        }
        
        isLoading = false
    }
    
    func authenticateWithBiometrics() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await appState.unlockWithBiometrics()
        } catch {
            // 生物识别失败不归咎于密码框，只引导改用主密码；
            // 用户主动放弃（如点了取消）不算失败，不打扰
            if !Self.isUserCancelled(error) {
                showFailureToast(AppLocale.string("Biometric unlock failed. Enter your master password."))
            }
        }
        
        isLoading = false
    }
    
    func createVault() async {
        validationError = ""
        guard newPassword.count >= 8 else {
            validationError = "Password must be at least 8 characters long"
            return
        }
        guard newPassword == confirmPassword else {
            validationError = "Passwords do not match"
    
            return
        }
        guard passwordStrength.rawValue >= PasswordStrength.medium.rawValue else {
            validationError = "Password strength is too weak, please use a stronger password. "
            return
        }
        
        isLoading = true
        
        do {
            try await appState.createVault(with: newPassword)
        } catch {
            showFailureToast(Self.friendlyMessage(for: error))
        }
        
        isLoading = false
    }

    func restoreFromICloud() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let material = try await CloudVaultRestoreService().fetchKeyMaterial() else {
                showFailureToast(AppLocale.string("No iCloud vault was found for this account."))
                return
            }
            try AppLockService().importCloudKeyMaterial(material)
            vaultMaterialInstalled = true
            toastCenter.toast = ToastItem(
                message: AppLocale.string("Vault restored. Enter your original master password to unlock."),
                style: .success,
                duration: 3.2
            )
        } catch {
            showFailureToast(Self.friendlyMessage(for: error))
        }
    }

    /// 用户重新输入主密码时解除错误态：toast 会自行消失，输入框的红框也该一起退场
    func clearError() {
        errorMessage = nil
    }

    // MARK: - 失败提示

    /// 以 toast 呈现失败原因：toast 会自行消失，不长期挤占表单空间
    private func showFailureToast(_ message: String) {
        toastCenter.toast = ToastItem(message: message, style: .error, duration: 2.6)
    }

    /// 把底层错误翻译成用户看得懂的话：只说清"怎么了 + 下一步"，不暴露技术细节
    private static func friendlyMessage(for error: Error) -> String {
        // AES-GCM 认证失败即主密码不对（与备份解密的判断口径一致）
        if let cryptoError = error as? CryptoKitError, case .authenticationFailure = cryptoError {
            return AppLocale.string("That's not the right master password. Try again.")
        }
        if error is UnlockThrottledError {
            return AppLocale.string("Too many attempts. Try again later.")
        }
        if let cloudError = error as? CloudSyncError {
            return cloudError.localizedDescription
        }
        return AppLocale.string("Something went wrong. Please try again.")
    }

    /// 用户主动放弃生物识别（系统弹窗取消 / 被系统中断）不算失败
    private static func isUserCancelled(_ error: Error) -> Bool {
        guard let keychainError = error as? KeychainError,
              case .retrieveFailed(let status) = keychainError
        else { return false }
        return status == errSecUserCanceled || status == errSecInteractionNotAllowed
    }
}