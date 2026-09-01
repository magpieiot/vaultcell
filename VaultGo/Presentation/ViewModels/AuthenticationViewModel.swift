/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// AuthenticationViewModel.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import LocalAuthentication
import Combine



enum BiometricType {
    case none
    case faceID
    case touchID
    case opticID

    var displayName: String {
        switch self {
        case .none:
            return String(localized: "None")
        case .faceID:
            return String(localized: "Face ID")
        case .touchID:
            return String(localized: "Touch ID")
        case .opticID:
            return String(localized: "Optic ID")
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
    
    private let appState: AppState
    
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
        !masterPassword.isEmpty
    }
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func unlock() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await appState.unlockVault(with: masterPassword)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func authenticateWithBiometrics() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await appState.unlockWithBiometrics()
        } catch {
            self.errorMessage = error.localizedDescription
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
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}