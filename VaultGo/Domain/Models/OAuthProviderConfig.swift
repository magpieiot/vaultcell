/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// OAuthProviderConfig.swift
/// created on: 15/06/2026
/// ------------------------------------------------------------------

//
//  TwoFactorConfig 2.swift
//  VaultGo
//
//  Created by gavanwang on 2026/6/15.
//


import Foundation

/// 双因素认证（2FA）配置
/// 表示一条密码条目所关联的某个 2FA 方式，例如 TOTP、SMS、硬件密钥等
struct OAuthProviderConfig: Codable, Equatable {
    /// 主键
    var providerID: UUID
    /// 密钥/共享密钥（例如 TOTP secret；出于安全，存储时不落明文）
    var secret: String?
    /// 发行方（例如 Google、GitHub）
    var provider: String?
    /// 绑定值（例如绑定的邮箱、手机号、账号名）
    var boundValue: String?
    /// 是否启用
    var isEnabled: Bool
    /// 最近一次验证时间
    var lastVerifiedAt: Date?
    /// 过期时间
    var expiresAt: Date?
    /// 备注
    var notes: String?
    
    init(
        providerID: UUID = UUID(),
        secret: String? = nil,
        provider: String? = nil,
        boundValue: String? = nil,
        isEnabled: Bool = true,
        lastVerifiedAt: Date? = nil,
        expiresAt: Date? = nil,
        notes: String? = nil
    ) {
        self.providerID = providerID
        self.secret = secret
        self.provider = provider
        self.boundValue = boundValue
        self.isEnabled = isEnabled
        self.lastVerifiedAt = lastVerifiedAt
        self.expiresAt = expiresAt
        self.notes = notes
    }
}


/// 双因素认证审计结果
/// 用于评估当前密码库中所有 2FA 配置的整体安全状况
struct OAuthProviderAudit: Identifiable {
    let id: UUID
    /// 2FA 配置总数
    var totalOAuth: Int
    /// 已验证的 2FA 数量（lastVerifiedAt 不为 nil）
    var verifiedOAuth: Int
    /// 未验证的 2FA 数量
    var unverifiedOAuth: Int
    /// 安全评分（0-100）
    var securityScore: Int
    /// 识别出的安全风险列表
    var risks: [SecurityRisk]
    /// 改进建议列表
    var suggestions: [String]
    
    /// 已验证覆盖率（百分比）
    var coverageRate: Double {
        guard totalOAuth > 0 else { return 0 }
        return Double(verifiedOAuth) / Double(totalOAuth) * 100
    }
}
