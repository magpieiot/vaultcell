/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// LoginEvent.swift
/// created on: 08/23/2026
/// ------------------------------------------------------------------

import Foundation

/// 登录事件模型，用于 CloudKit 上报
struct LoginEvent {
    /// 登录时间
    let timestamp: Date
    
    /// iOS 系统版本号，例如 "17.5"
    let iosVersion: String
    
    /// 设备型号标识符，例如 "iPhone15,2"
    let deviceModel: String
    
    /// 当前用户唯一标识
    let userID: String?
}
