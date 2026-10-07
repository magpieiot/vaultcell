/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CDPasswordEntry.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import CoreData
import Foundation

@objc(CDPasswordEntry)
public class CDPasswordEntry: NSManagedObject {

}

/// 无密码登录类型（用于标记该条目是否支持第三方登录/Passkey 等方式）
/// - 注意：该枚举的值会持久化到 CoreData 字段 `passwordlessLoginTypeRaw`
enum PasswordlessLoginType: Int {
    /// 不支持无密码登录
    case none = 0
    /// OAuth/第三方登录（例如 Google / Microsoft 等）
    case oauth = 1
    /// Passkey（通行密钥）
    case passkey = 2
}



extension CDPasswordEntry {
    
    /// 用于 CoreData 查询的请求
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPasswordEntry> {
        return NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
    }

    /// 主键：用于唯一标识一条密码记录
    @NSManaged public var id: UUID

    /// 展示用站点/应用名称（例如：GitHub、Amazon）
    @NSManaged public var siteName: String

    /// 站点 URL（可选；可能为空或不合法，仅用于展示/跳转）
    @NSManaged public var siteURL: String?

    /// 用户名/邮箱/账号
    @NSManaged public var username: String

    /// 加密后的密码正文（密文）
    /// - 说明：明文密码不应直接落库，这里存储加密后的 Data
    @NSManaged public var encryptedPassword: Data

    /// 加密后的备注信息（可选）
    @NSManaged public var encryptedNotes: Data?

    /// 分类（通过 categoryID 关联到 CDPasswordCategory 实体）
    @NSManaged public var categoryID: UUID

    /// 标签列表（字符串形式存储；具体分隔规则由上层仓储/服务决定）
    @NSManaged public var tags: String?

    /// 是否收藏
    @NSManaged public var isFavorite: Bool

    /// 密码强度（存储枚举的 raw 值）
    /// - 说明：对应 Domain 层 `PasswordStrength.rawValue`
    @NSManaged public var passwordStrengthRaw: Int16

    /// 创建时间
    @NSManaged public var createdAt: Date

    /// 更新时间
    @NSManaged public var updatedAt: Date

    /// 最近一次使用时间（例如：复制密码/打开详情）
    @NSManaged public var lastUsedAt: Date?

    /// 过期时间（可选；用于提示密码是否需要更新）
    @NSManaged public var expiresAt: Date?

    /// 软删除时间戳（nil 表示正常条目，非 nil 表示在回收站中）
    @NSManaged public var deletedAt: Date?

    /// 图标标识（可选；目前 UI 中多处以 URL 字符串/资源名形式使用）
    @NSManaged public var icon: String?

    /// 是否启用/存在 2FA 配置
    @NSManaged public var has2FA: Bool

    /// 2FA 配置集合（与 CDTwoFactorConfig 的一对多关系）
    @NSManaged public var twoFactorConfigs: NSSet?

    /// OAuth 提供方配置（与 CDOAuthProvider 的一对一关系）
    @NSManaged public var oAuthProvider: CDOAuthProvider?

    /// 是否绑定手机号（用于找回/验证等场景）
    @NSManaged public var hasBundlePhone: Bool

    /// 绑定手机号（可选；仅当 hasBundlePhone 为 true 时通常才有值）
    @NSManaged public var bundlePhoneNumber: String?

    /// 是否绑定邮箱（用于找回/验证等场景）
    @NSManaged public var hasBundleEmail: Bool

    /// 绑定邮箱（可选；仅当 hasBundleEmail 为 true 时通常才有值）
    @NSManaged public var bundleEmailAddress: String?

    /// 是否可通过邮箱重置密码
    @NSManaged public var isPasswordResetEmail: Bool

    /// 是否可通过手机号重置密码
    @NSManaged public var isPasswordResetPhone: Bool

    /// 无密码登录类型 raw 值（对应 PasswordlessLoginType）
    @NSManaged public var passwordlessLoginTypeRaw: Int
    
    /// OAuth 提供方标识（可选；用于区分第三方登录来源，例如 "google"/"microsoft" 等）
    @NSManaged public var OAuthProviderID: String?

    /// 加密后的密码历史记录（可选；JSON 数组加密后存储为二进制数据）
    @NSManaged public var encryptedPasswordHistory: Data?

    /// 密码最后修改时间（可选；区别于条目整体的 updatedAt）
    @NSManaged public var passwordChangedAt: Date?

    /// 加密后的自定义字段数据（可选；JSON 数组加密后存储）
    @NSManaged public var encryptedCustomFields: Data?

    /// 数据版本号（用于冲突解决；新建条目默认为 1）
    @NSManaged public var version: Int64

    /// 是否已同步
    @NSManaged public var isSynced: Bool

    /// 是否为重复密码（冗余字段，加速查询）
    @NSManaged public var isDuplicatePassword: Bool

    /// 密码泄露检测状态 raw 值（对应 BreachStatus）
    @NSManaged public var breachStatusRaw: Int16

    /// 账户状态 raw 值（对应 AccountStatus）
    @NSManaged public var accountStatusRaw: Int16

    /// 数据来源 raw 值（对应 PasswordDataSource）
    @NSManaged public var dataSourceRaw: Int16

    /// 标签关系（与 CDTag 的多对多关系）
    @NSManaged public var tagsRelationship: NSSet?
}

extension CDPasswordEntry: Identifiable {
    
}

@objc(CDTwoFactorConfig)
public class CDTwoFactorConfig: NSManagedObject {
    
}

extension CDTwoFactorConfig {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTwoFactorConfig> {
        return NSFetchRequest<CDTwoFactorConfig>(entityName: "CDTwoFactorConfig")
    }

    /// 主键：用于唯一标识一条 2FA 配置
    @NSManaged public var id: UUID

    /// 2FA 类型（字符串形式存储；通常对应 Domain 层的枚举 rawValue）
    @NSManaged public var type: String

    /// 加密后的密钥（可选；例如 TOTP secret，出于安全不保存明文）
    @NSManaged public var encryptedSecret: Data?

    /// TOTP 哈希算法（可选；"SHA1" / "SHA256" / "SHA512"）
    @NSManaged public var algorithm: String?

    /// TOTP 验证码位数（默认 6）
    @NSManaged public var digits: Int16

    /// TOTP 时间步长（秒，默认 30）
    @NSManaged public var period: Int16

    /// 发行方（可选；例如 Google、GitHub）
    @NSManaged public var issuer: String?

    /// 绑定值（可选；例如绑定的邮箱/手机号/账号名等）
    @NSManaged public var boundValue: String?

    /// 是否启用该 2FA 配置
    @NSManaged public var isEnabled: Bool

    /// 最近一次验证时间（可选）
    @NSManaged public var lastVerifiedAt: Date?

    /// 过期时间（可选）
    @NSManaged public var expiresAt: Date?

    /// 备注（可选）
    @NSManaged public var notes: String?

    /// 所属的密码条目（与 CDPasswordEntry 的多对一关系）
    @NSManaged public var passwordEntry: CDPasswordEntry?
}

extension CDTwoFactorConfig: Identifiable {
    
}


@objc(CDOAuthProvider)
public class CDOAuthProvider: NSManagedObject {

}

extension CDOAuthProvider {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDOAuthProvider> {
        return NSFetchRequest<CDOAuthProvider>(entityName: "CDOAuthProvider")
    }

    /// 主键
    @NSManaged public var id: UUID

    /// 加密后的密钥（可选；不保存明文）
    @NSManaged public var encryptedSecret: Data?

    /// 提供方标识（例如 "google"、"microsoft" 等）
    @NSManaged public var provider: String?

    /// 绑定值（例如绑定的邮箱/手机号/账号名等）
    @NSManaged public var boundValue: String?

    /// 是否启用
    @NSManaged public var isEnabled: Bool

    /// 最近一次验证时间
    @NSManaged public var lastVerifiedAt: Date?

    /// 过期时间
    @NSManaged public var expiresAt: Date?

    /// 备注
    @NSManaged public var notes: String?

    /// 所属的密码条目（与 CDPasswordEntry 的多对一关系）
    @NSManaged public var passwordEntry: CDPasswordEntry?
}

extension CDOAuthProvider: Identifiable {

}
