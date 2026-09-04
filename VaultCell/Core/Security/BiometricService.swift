/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// BiometricService.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import LocalAuthentication

class BiometricService {
    static let shared = BiometricService()
    
    enum BiometricType {
        case none
        case faceID
        case touchID
        case opticID
        
        var iconName: String {
            switch self {
            case .none:
                return "lock"
            case .faceID:
                return "faceid"
            case .touchID:
                return "touchid"
            case .opticID:
                return "visionpro"
            }
        }
    }
    
    private var context: LAContext
    
    private init() {
        context = LAContext()
    }
    
    var biometricType: BiometricType {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        
        
        if #available(iOS 17.0, *) {
            if context.biometryType == .opticID {
                return .opticID
            }
        }
        
        switch context.biometryType {
            case .faceID:
                return .faceID
            case .touchID:
                return .touchID
            default:
                return .none
        }
    }
    
    var isBiometricAvailable: Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func authenticate(reason: String) async throws -> Bool {
        context = LAContext()
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
