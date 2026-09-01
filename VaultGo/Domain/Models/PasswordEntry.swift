/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// PasswordEntry.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation

struct PasswordEntry: Identifiable, Codable, Equatable {

    let id: UUID                                    // 唯一标识符
    var siteName: String                            // 站点名称
    var siteURL: String?                            // 站点URL，可为空
    var username: String                            // 用户名
    var password: String                            // 密码
    var passwordHistory: [PasswordHistoryEntry]?    // 密码历史记录，可为空
    var oAuthProvider: OAuthProviderConfig?         // OAuth 提供商配置，可为空
    var bundlePhoneNumber: String?                  // 手机号，可为空
    var bundleEmailAddress: String?                 // 邮箱，可为空
    var notes: String?                              // 备注，可为空
    var categoryID: UUID                            // 分类ID
    var tags: [String]?                             // 标签，可为空
    var isFavorite: Bool = false                    // 是否收藏
    var isPasswordResetEmail: Bool = false          // 是否邮箱密码重置
    var isPasswordResetPhone: Bool = false          // 是否手机号密码重置
    var has2FA: Bool = false                        // 是否开启2FA认证
    var twoFactorConfigs: [TwoFactorConfig]?        // 2FA配置，可为空
    var customFields: [CustomField]?                // 自定义字段，可为空
    
    var version: Int64 = 1                              // 版本号
    var isSynced: Bool = false                      // 是否同步
    var isDuplicatePassword: Bool = false           // 是否重复密码
    var passwordStrength: PasswordStrength?         // 密码强度，可为空
    var breachStatus: BreachStatus?                  // 漏露状态，可为空
    var accountStatus: AccountStatus?                 // 账户状态，可为空
    var passwordChangedAt: Date?                    // 密码最后修改时间
    var createdAt: Date?                              // 创建时间
    var updatedAt: Date?                              // 更新时间
    var lastUsedAt: Date?                             // 最后使用时间
    var expiresAt: Date?                              // 过期时间
    var deletedAt: Date?                              // 软删除时间戳：nil 表示正常，非 nil 表示在回收站中
    var icon: String?                                 // 图标
    var dataSource: PasswordDataSource?             // 数据来源：标记该条目的产生方式（手动添加 / 浏览器导入 / 备份恢复等）
    
    init(
        id: UUID = UUID(),
        siteName: String,
        siteURL: String? = nil,
        username: String,
        password: String,
        oAuthProvider: OAuthProviderConfig? = nil,
        bundlePhoneNumber: String? = nil,
        bundleEmailAddress: String? = nil,
        notes: String? = nil,
        categoryID: UUID = PasswordCategory.systemDefaults[0].id,
        tags: [String] = [],
        isFavorite: Bool = false,
        isPasswordResetEmail: Bool = false,  
        isPasswordResetPhone: Bool = false,
        has2FA: Bool = false,
        passwordStrength: PasswordStrength? = .medium,
        passwordHistory: [PasswordHistoryEntry]? = [],
        passwordChangedAt: Date? = nil,
        customFields: [CustomField]? = [],
        version: Int64 = 1,
        isSynced: Bool = true,
        isDuplicatePassword: Bool = false,
        breachStatus: BreachStatus? = .unknown,
        accountStatus: AccountStatus? = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        expiresAt: Date? = nil,
        deletedAt: Date? = nil,
        icon: String? = nil,
        twoFactorConfigs: [TwoFactorConfig]? = [],
        dataSource: PasswordDataSource? = .manual
    ) {
        self.id = id
        self.siteName = siteName
        self.siteURL = siteURL
        self.username = username
        self.password = password
        self.oAuthProvider = oAuthProvider
        self.bundlePhoneNumber = bundlePhoneNumber
        self.bundleEmailAddress = bundleEmailAddress
        self.notes = notes
        self.categoryID = categoryID
        self.tags = tags
        self.isFavorite = isFavorite
        self.isPasswordResetEmail = isPasswordResetEmail
        self.isPasswordResetPhone = isPasswordResetPhone
        self.has2FA = has2FA
        self.passwordStrength = passwordStrength
        self.passwordHistory = passwordHistory
        self.passwordChangedAt = passwordChangedAt
        self.customFields = customFields
        self.version = version
        self.isSynced = isSynced
        self.isDuplicatePassword = isDuplicatePassword
        self.breachStatus = breachStatus
        self.accountStatus = accountStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt
        self.deletedAt = deletedAt
        self.icon = icon
        self.has2FA = has2FA
        self.twoFactorConfigs = twoFactorConfigs
        self.dataSource = dataSource
    }
    
    mutating func updatePassword(_ newPassword: String) {
        let oldEntry = PasswordHistoryEntry(password: self.password, changedAt: self.passwordChangedAt ?? self.updatedAt ?? Date())
        self.passwordHistory?.append(oldEntry)
        self.password = newPassword
        self.passwordStrength = PasswordStrength.calculate(for: newPassword)
        self.passwordChangedAt = Date()
        self.updatedAt = Date()
        self.version += 1
        self.isSynced = false
    }
}

/// 密码数据来源：标记一条密码记录的产生方式
enum PasswordDataSource: Int, Codable, CaseIterable {
    /// 手动添加
    case manual = 0
    /// Chrome 浏览器导入
    case chromeImport = 1
    /// Safari 浏览器导入
    case safariImport = 2
    /// Firefox 浏览器导入
    case firefoxImport = 3
    /// 备份恢复
    case backupRestore = 4
    /// 测试数据
    case testSeed = 5
    /// 通过 Credential Exchange 从其他密码管理器导入（iOS 26+）
    case credentialExchange = 6

    var displayName: String {
        switch self {
        case .manual: return String(localized: "Manual")
        case .chromeImport: return String(localized: "Chrome Import")
        case .safariImport: return String(localized: "Safari Import")
        case .firefoxImport: return String(localized: "Firefox Import")
        case .backupRestore: return String(localized: "Backup Restore")
        case .testSeed: return String(localized: "Test Seed")
        case .credentialExchange: return String(localized: "Credential Exchange Import")
        }
    }

    var iconName: String {
        switch self {
        case .manual: return "hand.draw"
        case .chromeImport: return "globe"
        case .safariImport: return "safari"
        case .firefoxImport: return "flame"
        case .backupRestore: return "arrow.uturn.left.circle"
        case .testSeed: return "testtube.2"
        case .credentialExchange: return "arrow.right.doc.on.clipboard"
        }
    }
}

/// 密码历史记录条目
struct PasswordHistoryEntry: Codable, Equatable, Identifiable {    let id: UUID
    let password: String
    let changedAt: Date
    
    init(id: UUID = UUID(), password: String, changedAt: Date) {
        self.id = id
        self.password = password
        self.changedAt = changedAt
    }
}

/// 自定义字段
struct CustomField: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var value: String
    var isSensitive: Bool    
    
    init(id: UUID = UUID(), name: String, value: String, isSensitive: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isSensitive = isSensitive
    }
}

/// 密码泄露检测状态
enum BreachStatus: Int, Codable, CaseIterable {
    case unknown = 0
    case safe = 1
    case compromised = 2
    
    var displayName: String {
        switch self {
        case .unknown: return String(localized: "Unknown")
        case .safe: return String(localized: "Safe")
        case .compromised: return String(localized: "Compromised")
        }
    }
}

/// 账户状态
enum AccountStatus: Int, Codable, CaseIterable {
    case active = 0
    case inactive = 1
    case suspended = 2
    case closed = 3
    
    var displayName: String {
        switch self {
        case .active: return String(localized: "Active")
        case .inactive: return String(localized: "Inactive")
        case .suspended: return String(localized: "Suspended")
        case .closed: return String(localized: "Closed")
        }
    }
}

enum Category: String, Codable, CaseIterable {
    case social = "Social"
    case work = "Work"
    case finance = "Finance"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .social: return "person.2.fill"
        case .work: return "briefcase.fill"
        case .finance: return "banknote.fill"
        case .shopping: return "cart.fill"
        case .entertainment: return "gamecontroller.fill"
        case .other: return "folder.fill"
        }
    }
}

enum PasswordStrength: Int, Codable, CaseIterable {
    case veryWeak = 0
    case weak = 1
    case medium = 2
    case strong = 3
    case veryStrong = 4
    
    var displayName: String {
        switch self {
        case .veryWeak: return String(localized: "Very Weak")
        case .weak: return String(localized: "Weak")
        case .medium: return String(localized: "Medium")
        case .strong: return String(localized: "Strong")
        case .veryStrong: return String(localized: "Very Strong")
        }
    }
    
    var color: String {
        switch self {
        case .veryWeak: return "danger"
        case .weak: return "warning"
        case .medium: return "warning"
        case .strong: return "success"
        case .veryStrong: return "success"
        }
    }
    
    static func calculate(for password: String) -> PasswordStrength {
        var score = 0
        
        // 长度检查
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        
        // 字符类型检查
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>\\/?]", options: .regularExpression) != nil { score += 1 }
        
        // 映射到强度枚举
        switch score {
        case 0...2: return .veryWeak
        case 3: return .weak
        case 4...5: return .medium
        case 6: return .strong
        default: return .veryStrong
        }
    }
}
