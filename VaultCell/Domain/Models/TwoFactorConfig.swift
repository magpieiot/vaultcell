/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TwoFactorConfig.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation

/// 双因素认证（2FA）配置
/// 表示一条密码条目所关联的某个 2FA 方式，例如 TOTP、SMS、硬件密钥等
struct TwoFactorConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var type: TwoFactorType  // 2FA 类型
    var secret: String?  // 2FA 密钥
    /// TOTP 哈希算法（"SHA1" / "SHA256" / "SHA512"），仅 TOTP 有效
    var algorithm: String  // TOTP 哈希算法
    /// TOTP 验证码位数，仅 TOTP 有效
    var digits: Int  // TOTP 验证码位数
    /// TOTP 时间步长（秒），仅 TOTP 有效
    var period: Int  // TOTP 时间步长
    var issuer: String?  // 发行方
    var boundValue: String?  // 绑定值（如手机号、邮箱等）
    var isEnabled: Bool  // 是否启用该 2FA 配置
    var createdAt: Date?  // 创建时间
    var lastVerifiedAt: Date?  // 最后验证时间
    var expiresAt: Date?  // 过期时间
    var notes: String?  // 备注

    init(
        id: UUID = UUID(),
        type: TwoFactorType,
        secret: String? = nil,
        algorithm: String = "SHA1",
        digits: Int = 6,
        period: Int = 30,
        issuer: String? = nil,
        boundValue: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date? = nil,
        lastVerifiedAt: Date? = nil,
        expiresAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.issuer = issuer
        self.boundValue = boundValue
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastVerifiedAt = lastVerifiedAt
        self.expiresAt = expiresAt
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, secret, algorithm, digits, period
        case issuer, boundValue, isEnabled
        case createdAt, lastVerifiedAt, expiresAt, notes
    }

    /// 自定义解码：兼容旧备份/导出文件（缺少 algorithm / digits / period 时使用默认值）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(TwoFactorType.self, forKey: .type)
        secret = try container.decodeIfPresent(String.self, forKey: .secret)
        algorithm = try container.decodeIfPresent(String.self, forKey: .algorithm) ?? "SHA1"
        digits = try container.decodeIfPresent(Int.self, forKey: .digits) ?? 6
        period = try container.decodeIfPresent(Int.self, forKey: .period) ?? 30
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        boundValue = try container.decodeIfPresent(String.self, forKey: .boundValue)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        lastVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// 双因素认证类型
enum TwoFactorType: String, Codable, CaseIterable {
    /// 基于时间的一次性密码（如 Google Authenticator）
    case totp = "TOTP"
    /// 短信验证码
    case sms = "Phone"
    /// 邮件验证码
    case email = "Email"
    /// 推送通知
    case push = "Push"
    /// 硬件安全密钥（如 YubiKey）
    case hardware = "Hardware"

    /// 每种 2FA 类型对应的 SF Symbol 图标名
    var icon: String {
        switch self {
        case .totp: return "key.viewfinder"
        case .sms: return "phone"
        case .email: return "mail"
        case .push: return "bell"
        case .hardware: return "key"
        }
    }

    /// 各类型的相对安全等级
    var securityLevel: SecurityLevel {
        switch self {
        case .hardware: return .veryHigh
        case .totp, .push: return .high
        case .email, .sms: return .medium
        }
    }

    /// 是否为推荐类型（TOTP 和硬件密钥为推荐）
    var isRecommended: Bool {
        return self == .totp || self == .hardware
    }
}

/// 安全等级
enum SecurityLevel: Int, Codable, CaseIterable {
    /// 低
    case low = 0
    /// 中
    case medium = 1
    /// 高
    case high = 2
    /// 极高
    case veryHigh = 3

    /// 展示名
    var displayName: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very High")
        }
    }

    /// 星级可视化（⭐个数 = rawValue + 1）
    var stars: String {
        String(repeating: "⭐", count: rawValue + 1)
    }
}

/// 双因素认证审计结果
/// 用于评估当前密码库中所有 2FA 配置的整体安全状况
struct TwoFactorAudit: Identifiable {
    let id: UUID
    /// 2FA 配置总数
    var total2FA: Int
    /// 已验证的 2FA 数量（lastVerifiedAt 不为 nil）
    var verified2FA: Int
    /// 未验证的 2FA 数量
    var unverified2FA: Int
    /// 安全评分（0-100）
    var securityScore: Int
    /// 各类型 2FA 的数量分布
    var typeDistribution: [TwoFactorType: Int]
    /// 识别出的安全风险列表
    var risks: [SecurityRisk]
    /// 改进建议列表
    var suggestions: [String]

    /// 已验证覆盖率（百分比）
    var coverageRate: Double {
        guard total2FA > 0 else { return 0 }
        return Double(verified2FA) / Double(total2FA) * 100
    }
}

/// 安全风险
struct SecurityRisk: Identifiable {
    let id: UUID
    /// 风险严重程度
    var severity: RiskSeverity
    /// 风险描述
    var description: String
    /// 受影响条目 ID（可选）
    var affectedEntryId: UUID?
    /// 改进建议
    var recommendation: String
}

/// 风险严重程度
enum RiskSeverity: String, Codable {
    /// 低风险
    case low = "low"
    /// 中风险
    case medium = "medium"
    /// 高风险
    case high = "high"
    /// 严重风险
    case critical = "critical"
}
