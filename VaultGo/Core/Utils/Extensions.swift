/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// Extensions.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation

extension CGFloat {
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 24
}

extension BiometricType {
    var iconName: String {
        switch self {
        case .none: return "lock"
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "visionpro"
        }
    }
}

