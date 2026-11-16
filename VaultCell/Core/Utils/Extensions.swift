/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// Extensions.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

// 界面 token 已移到 Shared/UIDesignTokens.swift，
// 主 App 与 AutoFill 扩展共用同一份定义；这里只保留主 App 专属的扩展。

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

