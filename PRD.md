# VaultCell - iOS密码管理器 产品需求文档 (PRD)

## 文档信息
- **产品名称**: VaultCell
- **版本**: v1.0.0
- **创建日期**: 2026-06-03
- **文档状态**: 初稿
- **作者**: Product Team

---

## 1. 产品概述

### 1.1 产品定位
VaultCell是一款专为iOS用户设计的安全、便捷的密码管理器应用。通过本地加密存储、生物识别认证和智能自动填充功能，为用户提供企业级的安全保障和极致的使用体验。

### 1.2 核心价值主张
- **安全至上**: 零知识架构 + AES-256-GCM + Secure Enclave + 600,000次PBKDF2迭代
- **企业级安全**: 军事级内存保护 + 防暴力破解 + 防越狱检测 + 防调试
- **便捷高效**: 自动填充、自动导入、一键登录 + 生物识别
- **功能完整**: 密码库、生成器、第三方登录、验证码全覆盖
- **隐私保护**: 数据完全由用户掌控，默认本地存储

### 1.3 目标用户
| 用户群体 | 特征描述 | 核心需求 |
|---------|---------|---------|
| 个人用户 | 注重隐私安全，多账户管理需求 | 简单易用、安全可靠、免费/低成本 |
| 商务人士 | 工作账户多，频繁切换登录 | 快速填充、跨平台同步、团队协作 |
| 开发者/技术人员 | 大量服务器、API密钥管理 | 密码生成、分类管理、导入导出 |
| 家庭用户 | 共享家庭账户（WiFi、流媒体） | 家庭共享、权限管理 |

### 1.4 市场分析

#### 竞品对比
| 产品 | 优势 | 劣势 | VaultCell差异化 |
|-----|------|------|---------------|
| 1Password | 功能强大、跨平台 | 订阅制价格高 | 一次性购买/免费基础版 |
| LastPass | 云同步、免费版功能全 | 安全事故频发 | 本地存储更安全 |
| Bitwarden | 开源、免费 | UI较简陋 | 更精致的iOS原生体验 |
| Apple钥匙串 | 系统集成度高 | 功能单一、跨平台差 | 更强大的管理功能 |

#### 市场机会
1. iOS用户对隐私安全关注度持续上升
2. 订阅制密码管理器价格敏感用户寻求替代方案
3. 本地存储方案满足隐私敏感用户需求
4. 第三方登录和验证码管理功能市场空白

---

## 2. 功能需求

### 2.1 功能架构图

```
VaultCell
├── 密码库管理
│   ├── 密码条目CRUD
│   ├── 分类管理
│   ├── 搜索与筛选
│   ├── 收藏与标签
│   ├── 导入导出
│   └── 密码安全审计
├── 自动填充
│   ├── 系统扩展集成
│   ├── 自动识别登录页面
│   ├── 自动保存新密码
│   └── 自动更新密码
├── 密码生成器
│   ├── 自定义规则
│   ├── 密码强度检测
│   ├── 预设模板
│   └── 历史记录
├── 第三方凭证登录
│   ├── OAuth 2.0集成
│   ├── 社交账号绑定
│   └── 企业SSO支持
├── 验证码管理
│   ├── TOTP生成
│   ├── 扫码导入
│   ├── 备用码管理
│   └── 云同步验证码
└── 双因素认证(2FA)管理 ⭐NEW
    ├── 2FA类型识别与记录
    ├── 2FA配置保存
    ├── 2FA状态追踪
    ├── 2FA与密码条目关联
    ├── 2FA安全评级
    ├── 2FA审计报告
    ├── 2FA过期提醒
    └── 2FA健康检查
```

### 2.2 详细功能说明

#### 2.2.1 密码库管理

##### 功能描述
提供完整的密码条目管理功能，支持多种类型凭证的存储、组织、检索。

##### 功能清单
| 功能项 | 优先级 | 描述 |
|-------|-------|------|
| 添加密码条目 | P0 | 手动添加站点名称、URL、用户名、密码、备注 |
| 编辑密码条目 | P0 | 修改任意字段，支持历史版本回溯 |
| 删除密码条目 | P0 | 支持回收站机制，30天内可恢复 |
| 密码条目详情 | P0 | 查看完整信息，支持字段复制、显示/隐藏密码 |
| 分类管理 | P1 | 默认分类：社交、工作、金融、购物、娱乐；支持自定义 |
| 标签系统 | P1 | 多标签支持，灵活组织密码条目 |
| 搜索功能 | P0 | 支持站点名称、URL、用户名、备注全文搜索 |
| 高级筛选 | P1 | 按分类、标签、创建时间、密码强度筛选 |
| 收藏功能 | P1 | 快速访问常用密码条目 |
| 密码强度分析 | P1 | 实时分析密码强度，提示弱密码 |
| 重复密码检测 | P2 | 检测并提示重复使用的密码 |
| 过期提醒 | P2 | 设置密码更新周期，到期提醒 |
| 导入功能 | P1 | 支持CSV、JSON格式导入，兼容1Password、LastPass |
| 导出功能 | P1 | 支持加密导出，备份到本地/云盘 |

##### 数据模型
```swift
struct PasswordEntry {
    let id: UUID
    var siteName: String
    var siteURL: String?
    var username: String
    var password: String  // 加密存储
    var notes: String?     // 加密存储
    var category: Category
    var tags: [String]
    var isFavorite: Bool
    var passwordStrength: PasswordStrength
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var expiresAt: Date?
    var icon: String?      // 网站favicon URL或自定义图标
}

enum Category: String, CaseIterable {
    case social = "社交"
    case work = "工作"
    case finance = "金融"
    case shopping = "购物"
    case entertainment = "娱乐"
    case other = "其他"
}

enum PasswordStrength: Int {
    case veryWeak = 0
    case weak = 1
    case medium = 2
    case strong = 3
    case veryStrong = 4
}
```

#### 2.2.2 自动填充与自动导入

##### 功能描述
通过iOS系统扩展（Authentication Services）实现Safari及第三方App的密码自动填充和保存。

##### 功能清单
| 功能项 | 优先级 | 描述 |
|-------|-------|------|
| Safari自动填充 | P0 | 在Safari登录页面自动识别并填充密码 |
| App自动填充 | P0 | 在第三方App登录界面自动填充 |
| 快速类型键盘 | P0 | 键盘上方显示密码条目快速选择 |
| 自动保存新密码 | P0 | 检测新注册/登录成功后提示保存 |
| 自动更新密码 | P1 | 检测密码修改后提示更新 |
| 智能匹配 | P1 | 根据URL/包名智能匹配密码条目 |
| 多账户选择 | P1 | 同一站点多账户时显示选择列表 |
| Face ID/Touch ID验证 | P0 | 自动填充前生物识别验证 |

##### 技术实现要点
```swift
// 1. 实现 ASCredentialProviderExtension
class CredentialProviderViewController: ASCredentialProviderViewController {
    
    // 准备凭证选择界面
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // 根据serviceIdentifiers匹配密码条目
    }
    
    // 提供凭证
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        // 静默提供凭证（需要前置验证）
    }
    
    // 保存新密码
    override func saveCredential(_ credential: ASPasswordCredential, completionHandler: @escaping (Error?) -> Void) {
        // 保存新检测到的密码
    }
}

// 2. 配置 Info.plist
// NSExtension -> NSExtensionAttributes -> ASCredentialProviderExtensionSupportedServices
```

##### 用户流程
```
自动填充流程:
1. 用户在Safari/App打开登录页面
2. 系统识别登录表单，显示密码填充提示
3. 用户点击提示或键盘快速类型
4. Face ID/Touch ID验证（可配置）
5. 显示匹配的密码条目列表
6. 用户选择条目
7. 自动填充用户名和密码

自动保存流程:
1. 用户在登录页面输入新用户名/密码
2. 登录成功后系统检测到新凭证
3. 弹出保存提示
4. 用户确认保存
5. 自动创建新密码条目
```

#### 2.2.3 密码生成器

##### 功能描述
提供可自定义规则的强密码生成功能，支持多种密码类型和强度配置。

##### 功能清单
| 功能项 | 优先级 | 描述 |
|-------|-------|------|
| 基础生成 | P0 | 生成随机密码，默认16位混合字符 |
| 自定义长度 | P0 | 支持6-128位长度设置 |
| 字符类型选择 | P0 | 大写字母、小写字母、数字、特殊符号 |
| 排除相似字符 | P1 | 排除容易混淆的字符（0OIl1等） |
| 排除特定字符 | P1 | 手动指定排除字符 |
| 密码强度实时显示 | P0 | 可视化显示密码强度等级 |
| 预设模板 | P1 | 强密码、PIN码、密码短语等预设 |
| 密码短语生成 | P2 | 生成易记的单词组合密码 |
| 自定义规则保存 | P1 | 保存常用生成规则配置 |
| 历史记录 | P2 | 保存最近生成的密码（可选） |
| 一键复制 | P0 | 生成后一键复制到剪贴板 |

##### 生成规则模型
```swift
struct PasswordGeneratorRule {
    var name: String
    var length: Int  // 6-128
    var includeUppercase: Bool
    var includeLowercase: Bool
    var includeNumbers: Bool
    var includeSymbols: Bool
    var excludeAmbiguous: Bool  // 排除 0OIl1
    var customExcludedChars: String
    var customIncludedChars: String
    
    // 预设规则
    static let strongPassword = PasswordGeneratorRule(
        name: "强密码",
        length: 16,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: true,
        excludeAmbiguous: true,
        customExcludedChars: "",
        customIncludedChars: ""
    )
    
    static let pinCode = PasswordGeneratorRule(
        name: "PIN码",
        length: 6,
        includeUppercase: false,
        includeLowercase: false,
        includeNumbers: true,
        includeSymbols: false,
        excludeAmbiguous: false,
        customExcludedChars: "",
        customIncludedChars: ""
    )
}
```

##### 密码强度算法
```swift
func calculatePasswordStrength(_ password: String) -> PasswordStrength {
    var score = 0
    
    // 长度评分
    if password.count >= 8 { score += 1 }
    if password.count >= 12 { score += 1 }
    if password.count >= 16 { score += 1 }
    
    // 字符类型评分
    let hasUppercase = password.contains(where: { $0.isUppercase })
    let hasLowercase = password.contains(where: { $0.isLowercase })
    let hasNumbers = password.contains(where: { $0.isNumber })
    let hasSymbols = password.contains(where: { "!@#$%^&*()_+-=[]{}|;:',.<>?".contains($0) })
    
    score += [hasUppercase, hasLowercase, hasNumbers, hasSymbols].filter { $0 }.count
    
    // 熵值评估
    let entropy = calculateEntropy(password)
    if entropy > 60 { score += 1 }
    
    // 映射到强度等级
    switch score {
    case 0...2: return .veryWeak
    case 3...4: return .weak
    case 5...6: return .medium
    case 7...8: return .strong
    default: return .veryStrong
    }
}
```

#### 2.2.4 第三方凭证登录

##### 功能描述
集成OAuth 2.0协议，支持使用社交账号（Google、Apple、微信等）快速登录第三方应用。

##### 功能清单
| 功能项 | 优先级 | 描述 |
|-------|-------|------|
| Sign in with Apple | P0 | 苹果官方登录，隐私保护最佳 |
| Sign in with Google | P1 | Google账号登录 |
| 微信登录 | P1 | 国内用户常用社交登录 |
| 企业SSO | P2 | 企业级单点登录支持 |
| 账号绑定管理 | P0 | 查看和管理已绑定的第三方账号 |
| 快速登录入口 | P0 | 从App内快速发起第三方登录 |
| Token管理 | P1 | 安全存储和管理OAuth Token |
| 自动刷新Token | P2 | Token过期自动刷新 |

##### 技术实现
```swift
// Sign in with Apple
import AuthenticationServices

func signInWithApple() {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.fullName, .email]
    
    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.performRequests()
}

// OAuth 2.0 通用流程
struct OAuthConfig {
    let clientId: String
    let authorizeURL: String
    let tokenURL: String
    let redirectURI: String
    let scope: String
}

func performOAuthLogin(_ config: OAuthConfig) {
    // 1. 构建授权URL
    // 2. 打开ASWebAuthenticationSession
    // 3. 获取授权码
    // 4. 交换Token
    // 5. 安全存储Token
}
```

##### 数据模型
```swift
struct OAuthCredential {
    let id: UUID
    let provider: OAuthProvider
    let userId: String
    let email: String?
    let name: String?
    let accessToken: String  // 加密存储
    let refreshToken: String?  // 加密存储
    let expiresAt: Date?
    let createdAt: Date
    let lastUsedAt: Date?
}

enum OAuthProvider: String, CaseIterable {
    case apple = "Apple"
    case google = "Google"
    case wechat = "WeChat"
    case microsoft = "Microsoft"
    case github = "GitHub"
}
```

#### 2.2.5 双因素认证（2FA）管理

##### 功能描述
提供完整的双因素认证（2FA）项目管理功能，支持短信、邮件、TOTP等多种认证方式，便于密码安全审计和2FA状态追踪。

##### 2FA类型支持

| 2FA类型 | 描述 | 配置信息 | 安全级别 |
|---------|------|---------|---------|
| **短信验证码 (SMS)** | 手机短信接收验证码 | 手机号、运营商、绑定期 | ⚠️ 中等（存在SIM卡劫持风险） |
| **邮件验证码 (Email)** | 邮箱接收验证码 | 邮箱地址、邮箱服务商 | ⚠️ 中等（依赖邮箱安全） |
| **TOTP应用** | Google Authenticator等APP | 密钥、二维码URI | ✅ 高（推荐） |
| **推送通知** | 专用APP推送确认 | 设备ID、推送令牌 | ✅ 高 |
| **硬件密钥** | YubiKey等物理密钥 | 密钥序列号、品牌型号 | ✅ 极高 |
| **备用码** | 一次性备用登录码 | 码库、使用记录 | ⚠️ 需安全存储 |

##### 功能清单

| 功能项 | 优先级 | 描述 |
|-------|-------|------|
| **2FA类型识别** | P0 | 自动识别并记录站点的2FA类型 |
| **2FA配置保存** | P0 | 保存2FA配置信息（类型、绑定账号、绑定期） |
| **2FA状态追踪** | P0 | 记录2FA启用/禁用状态、最后验证时间 |
| **2FA绑定管理** | P0 | 管理2FA与密码条目的关联关系 |
| **2FA安全评级** | P1 | 根据2FA类型和配置评估安全性 |
| **2FA过期提醒** | P1 | 2FA密钥过期或需要更新时提醒 |
| **2FA审计报告** | P1 | 生成2FA使用情况统计和安全性报告 |
| **2FA恢复指导** | P1 | 提供2FA恢复步骤指导 |
| **批量2FA扫描** | P2 | 自动扫描并识别常用网站的2FA配置 |
| **2FA健康检查** | P2 | 检测未启用2FA的高风险账号 |

##### 2FA数据模型

```swift
// 双因素认证配置
struct TwoFactorConfig {
    let id: UUID
    var type: TwoFactorType
    var provider: String?              // 服务商名称 (如: Google, GitHub)
    var linkedPasswordId: UUID?         // 关联的密码条目ID
    var isEnabled: Bool                // 2FA是否启用
    var isVerified: Bool               // 2FA是否已验证配置正确
    var bindingInfo: BindingInfo       // 绑定信息 (类型相关)
    var securityLevel: SecurityLevel   // 安全级别评估
    var backupMethods: [BackupMethod]  // 备份方式
    var createdAt: Date
    var updatedAt: Date
    var lastVerifiedAt: Date?          // 最后验证时间
    var expiresAt: Date?               // 配置过期时间
    var notes: String?                 // 备注信息
}

// 2FA类型枚举
enum TwoFactorType: String, CaseIterable, Codable {
    case sms = "sms"                    // 短信验证码
    case email = "email"                // 邮件验证码
    case totp = "totp"                  // TOTP应用 (Google Authenticator等)
    case push = "push"                  // 推送通知
    case hardware = "hardware"           // 硬件密钥 (YubiKey等)
    case backupCodes = "backup_codes"    // 备用码
    case unknown = "unknown"             // 未知/未检测到
    
    var displayName: String {
        switch self {
        case .sms: return "短信验证码"
        case .email: return "邮件验证码"
        case .totp: return "TOTP应用"
        case .push: return "推送通知"
        case .hardware: return "硬件密钥"
        case .backupCodes: return "备用码"
        case .unknown: return "未检测"
        }
    }
    
    var securityLevel: SecurityLevel {
        switch self {
        case .totp, .hardware: return .high
        case .push: return .high
        case .email: return .medium
        case .sms, .backupCodes: return .low
        case .unknown: return .unknown
        }
    }
    
    var riskDescription: String {
        switch self {
        case .totp: return "推荐 - 基于时间的一次性密码，安全性高"
        case .hardware: return "最安全 - 物理密钥，不怕钓鱼攻击"
        case .push: return "安全 - 推送通知需物理设备确认"
        case .email: return "中等 - 依赖邮箱安全性"
        case .sms: return "风险 - 存在SIM卡交换攻击风险"
        case .backupCodes: return "备份 - 仅用于恢复，请安全存储"
        case .unknown: return "未知 - 请确认2FA配置"
        }
    }
}

// 安全级别
enum SecurityLevel: Int, Codable {
    case unknown = 0
    case low = 1
    case medium = 2
    case high = 3
    case veryHigh = 4
    
    var displayName: String {
        switch self {
        case .unknown: return "未知"
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "高安全"
        case .veryHigh: return "极高安全"
        }
    }
}

// 绑定信息 (根据2FA类型不同，包含不同字段)
struct BindingInfo: Codable {
    var phoneNumber: String?           // SMS: 手机号
    var phoneMasked: String?           // 脱敏手机号 (如: 138****1234)
    var emailAddress: String?          // Email: 邮箱地址
    var emailMasked: String?           // 脱敏邮箱 (如: u***@example.com)
    var totpIssuer: String?            // TOTP: 发行方
    var totpAccount: String?           // TOTP: 账户名
    var totpSecretEncrypted: Data?     // TOTP: 加密存储的密钥
    var deviceId: String?              // Push: 设备ID
    var deviceName: String?            // Push: 设备名称
    var hardwareKeySerial: String?     // Hardware: 硬件密钥序列号
    var hardwareKeyBrand: String?       // Hardware: 品牌型号
    var backupCodesCount: Int           // 备用码数量
    var backupCodesUsedCount: Int      // 已使用的备用码数量
}

// 备份方式
struct BackupMethod: Codable {
    var type: TwoFactorType
    var isEnabled: Bool
    var isVerified: Bool
    var priority: Int                  // 优先级，数字越小优先级越高
}

// TOTP配置 (详细)
struct TOTPConfig: Codable {
    let id: UUID
    var secretEncrypted: Data         // Base32编码密钥 (加密存储)
    var issuer: String                 // 服务商名称
    var accountName: String            // 账户名
    var algorithm: TOTPAlgorithm      // 算法: SHA1/SHA256/SHA512
    var digits: Int                    // 位数: 6或8
    var period: Int                    // 周期: 30秒或60秒
    var qrCodeData: String?           // otpauth:// URI
    var icon: String?                  // 网站图标
    var createdAt: Date
    var lastUsedAt: Date?
}

enum TOTPAlgorithm: String, Codable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

// 备用码
struct BackupCode: Codable {
    let id: UUID
    var code: String                   // 备用码 (加密存储)
    var isUsed: Bool                  // 是否已使用
    var usedAt: Date?                // 使用时间
    var createdAt: Date
}

// 2FA验证历史
struct TwoFactorVerification: Codable {
    let id: UUID
    var twoFactorId: UUID             // 关联的2FA配置ID
    var verifiedAt: Date              // 验证时间
    var verificationMethod: TwoFactorType  // 验证方式
    var wasSuccessful: Bool           // 验证是否成功
    var ipAddress: String?            // IP地址 (可选)
    var deviceInfo: String?           // 设备信息 (可选)
}
```

##### 2FA技术实现

```swift
// 2FA服务
class TwoFactorAuthService {
    
    // 添加2FA配置
    func addTwoFactor(
        type: TwoFactorType,
        provider: String,
        linkedPasswordId: UUID?,
        bindingInfo: BindingInfo,
        backupMethods: [BackupMethod] = []
    ) throws -> TwoFactorConfig {
        let config = TwoFactorConfig(
            id: UUID(),
            type: type,
            provider: provider,
            linkedPasswordId: linkedPasswordId,
            isEnabled: true,
            isVerified: false,
            bindingInfo: bindingInfo,
            securityLevel: type.securityLevel,
            backupMethods: backupMethods,
            createdAt: Date(),
            updatedAt: Date(),
            lastVerifiedAt: nil,
            expiresAt: nil,
            notes: nil
        )
        
        // 保存加密配置
        try saveSecureConfig(config)
        return config
    }
    
    // 验证2FA配置
    func verifyTwoFactor(_ configId: UUID, code: String) throws -> Bool {
        guard let config = try loadConfig(configId) else {
            throw TwoFactorError.configNotFound
        }
        
        var isValid = false
        
        switch config.type {
        case .totp:
            isValid = try verifyTOTPCode(config, code: code)
        case .sms:
            isValid = try verifySMSCode(config, code: code)
        case .email:
            isValid = try verifyEmailCode(config, code: code)
        case .backupCodes:
            isValid = try verifyBackupCode(config, code: code)
        default:
            throw TwoFactorError.unsupportedType
        }
        
        // 记录验证历史
        if isValid {
            try recordVerification(configId: configId, success: true)
        }
        
        return isValid
    }
    
    // TOTP验证码生成
    func generateTOTPCode(_ config: TOTPConfig) throws -> String {
        let secret = try decryptSecret(config.secretEncrypted)
        return TOTPGenerator.generateTOTP(
            secret: secret,
            digits: config.digits,
            period: config.period,
            algorithm: config.algorithm
        )
    }
    
    // 2FA安全审计
    func performSecurityAudit() throws -> TwoFactorAuditReport {
        let allConfigs = try loadAllConfigs()
        
        var stats = TwoFactorStatistics()
        var recommendations: [SecurityRecommendation] = []
        
        // 统计各类型2FA数量
        for config in allConfigs {
            stats.totalCount += 1
            stats.countByType[config.type, default: 0] += 1
            
            // 风险检测
            if config.type == .sms {
                recommendations.append(SecurityRecommendation(
                    severity: .medium,
                    configId: config.id,
                    title: "短信2FA存在SIM卡交换攻击风险",
                    suggestion: "建议升级到TOTP应用或硬件密钥"
                ))
            }
            
            if config.type == .unknown {
                recommendations.append(SecurityRecommendation(
                    severity: .high,
                    configId: config.id,
                    title: "2FA类型未知",
                    suggestion: "请确认并记录该站点的2FA配置"
                ))
            }
            
            // 检查长期未验证
            if let lastVerified = config.lastVerifiedAt {
                let daysSinceVerified = Calendar.current.dateComponents(
                    [.day], from: lastVerified, to: Date()
                ).day ?? 0
                
                if daysSinceVerified > 90 {
                    recommendations.append(SecurityRecommendation(
                        severity: .low,
                        configId: config.id,
                        title: "2FA超过90天未验证",
                        suggestion: "建议验证2FA是否正常工作"
                    ))
                }
            }
        }
        
        return TwoFactorAuditReport(
            generatedAt: Date(),
            statistics: stats,
            recommendations: recommendations,
            overallSecurityScore: calculateSecurityScore(stats)
        )
    }
    
    // 计算安全评分
    private func calculateSecurityScore(_ stats: TwoFactorStatistics) -> Int {
        guard stats.totalCount > 0 else { return 0 }
        
        var score = 100
        
        // 降低无2FA或低安全2FA的分数
        let lowSecurityCount = stats.countByType[.sms] ?? 0 +
                              stats.countByType[.unknown] ?? 0
        score -= lowSecurityCount * 10
        
        // 奖励高安全2FA
        let highSecurityCount = stats.countByType[.totp] ?? 0 +
                               stats.countByType[.hardware] ?? 0
        score += min(highSecurityCount * 5, 20)
        
        return max(0, min(100, score))
    }
}

// 2FA审计报告
struct TwoFactorAuditReport: Codable {
    var generatedAt: Date
    var statistics: TwoFactorStatistics
    var recommendations: [SecurityRecommendation]
    var overallSecurityScore: Int       // 0-100
}

struct TwoFactorStatistics: Codable {
    var totalCount: Int = 0
    var countByType: [TwoFactorType: Int] = [:]
    var verifiedCount: Int = 0
    var unverifiedCount: Int = 0
}

struct SecurityRecommendation: Codable {
    var severity: Severity
    var configId: UUID
    var title: String
    var suggestion: String
    
    enum Severity: Int, Codable {
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4
    }
}
```

##### 2FA审计报告示例

```
┌─────────────────────────────────────────────┐
│         VaultCell 2FA 安全审计报告            │
│         生成时间: 2026-06-03               │
├─────────────────────────────────────────────┤
│  📊 总体评分: 78/100                       │
│  🔒 安全等级: 良好                         │
├─────────────────────────────────────────────┤
│  📈 统计概览                                │
│  • 总2FA配置: 42个                         │
│  • 已验证: 40个                            │
│  • 未验证: 2个                              │
│                                             │
│  按类型分布:                                │
│  • TOTP应用: 25个 (59.5%)                  │
│  • 硬件密钥: 3个 (7.1%)                    │
│  • 短信验证码: 8个 (19.0%) ⚠️             │
│  • 邮件验证: 6个 (14.3%)                   │
├─────────────────────────────────────────────┤
│  ⚠️ 安全建议                                │
│                                             │
│  [高] GitHub账户2FA类型未知                 │
│       → 请确认并记录GitHub的2FA配置        │
│                                             │
│  [中] 8个账户使用短信2FA                    │
│       → 建议升级到TOTP应用以提高安全性     │
│                                             │
│  [低] 5个2FA超过90天未验证                 │
│       → 建议定期验证2FA是否正常工作        │
└─────────────────────────────────────────────┘
```

##### 与密码条目的关联

每个2FA配置可以关联到一个密码条目，形成完整的安全档案：

```swift
// 密码条目增强 - 添加2FA关联
struct PasswordEntry {
    let id: UUID
    var siteName: String
    var siteURL: String?
    var username: String
    var password: String              // 加密存储
    var notes: String?                 // 加密存储
    var category: Category
    var tags: [String]
    var isFavorite: Bool
    var passwordStrength: PasswordStrength
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var expiresAt: Date?
    var icon: String?
    
    // 2FA关联
    var twoFactorConfigs: [TwoFactorConfig]  // 该账户的2FA配置列表
    var has2FA: Bool                              // 是否启用了2FA
    var overallSecurityLevel: SecurityLevel        // 综合安全级别
}
```

---

## 3. 技术架构设计

### 3.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    Presentation Layer                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   SwiftUI    │  │   MVVM      │  │   Combine    │  │
│  │    Views     │  │  ViewModel  │  │  Bindings    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                    Business Logic Layer                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Password    │  │   Crypto     │  │   TOTP       │  │
│  │   Manager    │  │   Service    │  │   Service    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   OAuth      │  │   AutoFill   │  │   Generator  │  │
│  │   Service    │  │   Service    │  │   Service    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                      Data Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   Core Data  │  │    Keychain  │  │   SQLite     │  │
│  │   Storage    │  │   Service    │  │   (Cipher)  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Encryption  │  │   Backup     │  │   Import/    │  │
│  │   Manager    │  │   Manager    │  │   Export     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                   System Integration                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Authentication│  │   CryptoKit  │  │   Local      │  │
│  │   Services   │  │   Framework  │  │ Authentication│  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 3.2 技术栈选型

| 技术领域 | 选型方案 | 选型理由 |
|---------|---------|---------|
| UI框架 | SwiftUI | 声明式UI、现代化、iOS 15+原生支持 |
| 架构模式 | MVVM | 数据驱动、可测试性强、与SwiftUI完美契合 |
| 数据持久化 | Core Data + SQLite (SQLCipher) | Core Data管理对象图，SQLCipher提供加密 |
| 加密算法 | CryptoKit | 苹果官方加密框架，硬件加速，安全可靠 |
| 密钥存储 | Keychain Services | 系统级安全存储，硬件隔离 |
| 生物识别 | LocalAuthentication | Face ID/Touch ID原生支持 |
| 自动填充 | Authentication Services | 系统扩展，Safari和App通用 |
| 网络请求 | URLSession + Combine | 原生支持，响应式编程 |
| 依赖注入 | Swift DI / 手动注入 | 轻量级，避免过度设计 |
| 测试框架 | XCTest | 原生测试框架 |

### 3.3 安全架构（企业级军用标准）

VaultCell采用零知识架构(Zero-Knowledge Architecture)，确保即使在最坏情况下，开发者也无法访问用户的密码数据。

#### 3.3.1 安全架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户输入层                                │
│                    ┌───────────────────┐                         │
│                    │  主密码输入 +      │                         │
│                    │  生物识别验证      │                         │
│                    └─────────┬─────────┘                         │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                               │ PBKDF2-SHA256 (600,000次迭代)
                               │ 可选: Argon2id (高级模式)
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                      主密钥层 (内存仅存)                         │
│                    ┌───────────────────┐                         │
│                    │  Master Key (MK)  │ 256位                   │
│                    │  (永不写入磁盘)    │                         │
│                    └─────────┬─────────┘                         │
└──────────────────────────────┼──────────────────────────────────┘
                               │ HKDF-SHA512 密钥派生
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
┌────────▼─────────┐  ┌────────▼─────────┐  ┌───────▼────────┐
│ 数据加密密钥     │  │ 密钥加密密钥     │  │ HMAC认证密钥   │
│ (DEK) - AES-256 │  │ (KEK) - AES-256  │  │ SHA-256        │
└────────┬─────────┘  └────────┬─────────┘  └───────┬────────┘
         │                     │                     │
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                       密钥加密存储层                              │
│              DEK由KEK加密后存储于 Keychain (Secure Enclave)       │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                       数据加密层                                 │
│  ┌───────────────────────────────────────────────────────────┐│
│  │  每个密码条目独立加密:                                     ││
│  │  1. 生成随机Nonce (96位)                                   ││
│  │  2. AES-256-GCM 认证加密                                   ││
│  │  3. 密文 + Tag + Nonce + 关联数据(AAD)一起存储              ││
│  └───────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
```

#### 3.3.2 KDF密钥派生函数

VaultCell支持两种KDF模式，满足不同安全需求：

**模式一: PBKDF2 (默认，兼容性优先)**
```swift
import CryptoKit

class KDFService {
    // PBKDF2-SHA256 配置参数 (OWASP 2026推荐标准)
    static let pbkdf2Iterations: Int = 600_000
    static let pbkdf2SaltLength: Int = 32
    static let pbkdf2KeyLength: Int = 32
    
    static func deriveMasterKey(
        password: String,
        salt: Data
    ) throws -> (masterKey: SymmetricKey, verificationHash: Data) {
        // 密码预处理 - 使用NFD规范化防止编码差异
        guard let passwordData = password.precomposedStringWithCanonicalMapping
            .data(using: .utf8) else {
            throw CryptoError.invalidPassword
        }
        
        // PBKDF2密钥派生
        let masterKeyData = try PKCS5.PBKDF2(
            password: passwordData,
            salt: salt,
            iterations: pbkdf2Iterations,
            keyLength: pbkdf2KeyLength
        )
        
        // 生成验证哈希 (用于验证密码正确性，不用于加密)
        let verificationHash = HMAC<SHA256>.authenticationCode(
            for: "VaultCell_Verification_v1.0".data(using: .utf8)!,
            using: SymmetricKey(data: masterKeyData)
        )
        
        return (
            SymmetricKey(data: masterKeyData),
            Data(verificationHash)
        )
    }
}
```

**模式二: Argon2id (高级模式，安全性优先)**
```swift
import Argon2Swift

class Argon2KDFService {
    static let argon2MemoryCost: UInt32 = 19_456 // 19MB
    static let argon2TimeCost: UInt32 = 2
    static let argon2Parallelism: UInt32 = 1
    static let argon2SaltLength: Int = 32
    static let argon2KeyLength: Int = 32
    
    static func deriveMasterKeyAdvanced(
        password: String,
        salt: Data
    ) throws -> (masterKey: SymmetricKey, verificationHash: Data) {
        let result = try Argon2Swift.hashPasswordString(
            password: password,
            salt: salt,
            type: .id,
            timeCost: argon2TimeCost,
            memoryCost: argon2MemoryCost,
            parallelism: argon2Parallelism,
            length: argon2KeyLength
        )
        
        let masterKeyData = result.hashData()
        let verificationHash = HMAC<SHA256>.authenticationCode(
            for: "VaultCell_Verification_Argon2_v1.0".data(using: .utf8)!,
            using: SymmetricKey(data: masterKeyData)
        )
        
        return (
            SymmetricKey(data: masterKeyData),
            Data(verificationHash)
        )
    }
}
```

#### 3.3.3 HKDF分层密钥派生

```swift
extension SymmetricKey {
    func deriveSubKey(
        info: String,
        outputLength: Int = 32
    ) throws -> SymmetricKey {
        let salt = "VaultCell_HKDF_Salt_v1.0".data(using: .utf8)!
        let infoData = info.data(using: .utf8)!
        
        var hkdf = HKDF<SHA512>(
            inputKeyMaterial: self,
            salt: salt,
            info: infoData,
            outputByteCount: outputLength
        )
        
        var derivedKey = Data()
        while derivedKey.count < outputLength {
            try derivedKey.append(hkdf.read())
        }
        
        return SymmetricKey(data: derivedKey)
    }
}

class KeyDerivationService {
    enum KeyPurpose: String {
        case dataEncryption = "VaultCell_DEK_Purpose_v1.0"
        case keyEncryption = "VaultCell_KEK_Purpose_v1.0"
        case hmac = "VaultCell_HMAC_Purpose_v1.0"
        case backup = "VaultCell_Backup_Purpose_v1.0"
    }
    
    static func deriveKeys(from masterKey: SymmetricKey) throws -> KeySet {
        return KeySet(
            dataEncryptionKey: try masterKey.deriveSubKey(
                info: KeyPurpose.dataEncryption.rawValue
            ),
            keyEncryptionKey: try masterKey.deriveSubKey(
                info: KeyPurpose.keyEncryption.rawValue
            ),
            hmacKey: try masterKey.deriveSubKey(
                info: KeyPurpose.hmac.rawValue
            ),
            backupKey: try masterKey.deriveSubKey(
                info: KeyPurpose.backup.rawValue,
                outputLength: 64
            )
        )
    }
}

struct KeySet {
    let dataEncryptionKey: SymmetricKey
    let keyEncryptionKey: SymmetricKey
    let hmacKey: SymmetricKey
    let backupKey: SymmetricKey
}
```

#### 3.3.4 数据加密（每条目独立加密）

```swift
class SecureEncryptionService {
    private let keys: KeySet
    
    init(keys: KeySet) {
        self.keys = keys
    }
    
    struct EncryptedEntry: Codable {
        let ciphertext: Data
        let nonce: AES.GCM.Nonce
        let tag: Data
        let associatedData: Data
        let version: String = "1.0"
    }
    
    func encryptEntry(_ entry: PlaintextEntry) throws -> EncryptedEntry {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintextData = try encoder.encode(entry)
        
        // 生成随机Nonce (96位 = CryptoKit推荐长度)
        let nonce = AES.GCM.Nonce()
        
        // 关联数据 (AAD) - 用于完整性验证，防止替换攻击
        let associatedData = """
            VaultCell_Entry_v1.0_\(entry.id.uuidString)_\(entry.createdAt.timeIntervalSince1970)
            """.data(using: .utf8)!
        
        // AES-256-GCM 认证加密
        let sealedBox = try AES.GCM.seal(
            plaintextData,
            using: keys.dataEncryptionKey,
            nonce: nonce,
            authenticating: associatedData
        )
        
        return EncryptedEntry(
            ciphertext: sealedBox.ciphertext,
            nonce: sealedBox.nonce,
            tag: sealedBox.tag,
            associatedData: associatedData
        )
    }
    
    func decryptEntry(_ encrypted: EncryptedEntry) throws -> PlaintextEntry {
        guard encrypted.version == "1.0" else {
            throw CryptoError.unsupportedVersion
        }
        
        let sealedBox = try AES.GCM.SealedBox(
            nonce: encrypted.nonce,
            ciphertext: encrypted.ciphertext,
            tag: encrypted.tag
        )
        
        let plaintextData = try AES.GCM.open(
            sealedBox,
            using: keys.dataEncryptionKey,
            authenticating: encrypted.associatedData
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaintextEntry.self, from: plaintextData)
    }
}

struct PlaintextEntry: Codable {
    let id: UUID
    let siteName: String
    let siteURL: String?
    let username: String
    let password: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}
```

#### 3.3.5 Secure Enclave 硬件安全

```swift
import LocalAuthentication
import CryptoKit

class SecureEnclaveManager {
    static let shared = SecureEnclaveManager()
    private let keyTag = "com.vaultcell.protected.key"
    
    func generateSecureEnclaveKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence, .privateKeyUsage, .biometryCurrentSet],
            nil
        )!
        
        let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            accessControl: accessControl
        )
        
        try storePublicKey(privateKey.publicKey)
        return privateKey
    }
    
    func encryptWithSecureEnclave(_ data: Data) throws -> Data {
        let publicKey = try retrievePublicKey()
        let ephemeralKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: publicKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "VaultCell_SE_Wrap_v1.0".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        return sealedBox.combined!
    }
}
```

#### 3.3.6 内存安全保护

```swift
/// 安全内存缓冲区 - 自动擦除、防止交换、隔离保护
class SecureBuffer {
    private var bytes: UnsafeMutableRawBufferPointer
    private let count: Int
    private(set) var isDestroyed: Bool = false
    
    init(count: Int) {
        self.count = count
        let pageSize = Int(getpagesize())
        let alignedCount = ((count + pageSize - 1) / pageSize) * pageSize
        
        bytes = UnsafeMutableRawBufferPointer.allocate(
            byteCount: alignedCount,
            alignment: pageSize
        )
        
        // 锁定内存防止被交换到磁盘
        mlock(bytes.baseAddress!, bytes.count)
        
        // 前后保护页 - 防止缓冲区溢出
        if let base = bytes.baseAddress {
            mprotect(base, pageSize, PROT_NONE)
            mprotect(base + alignedCount - pageSize, pageSize, PROT_NONE)
        }
    }
    
    func write(_ data: Data, offset: Int = 0) {
        guard !isDestroyed else { return }
        data.withUnsafeBytes { src in
            bytes.baseAddress?.advanced(by: offset).copyMemory(
                from: src.baseAddress!,
                byteCount: Swift.min(src.count, count - offset)
            )
        }
    }
    
    func read(offset: Int = 0, length: Int? = nil) -> Data {
        guard !isDestroyed else { return Data() }
        let len = length ?? count - offset
        return Data(bytes: bytes.baseAddress!.advanced(by: offset), count: len)
    }
    
    func destroy() {
        guard !isDestroyed else { return }
        
        // 多次覆盖，防止内存取证
        let patterns: [UInt8] = [0x00, 0xFF, 0xAA, 0x55, 0x00]
        for pattern in patterns {
            memset_pattern(bytes.baseAddress!, &pattern, 1, count)
            __asm__ __volatile__("" ::: "memory") // 防止编译器优化
        }
        
        munlock(bytes.baseAddress!, bytes.count)
        bytes.deallocate()
        isDestroyed = true
    }
    
    deinit {
        if !isDestroyed { destroy() }
    }
}
```

#### 3.3.7 认证安全与防暴力破解

> 本节描述**已落地**的主密码失败限流方案（v1.3）。早期草稿里的 `AuthenticationService` 示意代码从未实现，已移除。

**设计边界：三类威胁，只防其中一类**

应用层限速只对 A 类有效。先把边界讲清楚，是为了避免"看起来有防护、实际可一键绕过"的虚假安全感。

| 类别 | 场景 | 应用层限速 | 真正有效的手段 |
|-----|------|-----------|--------------|
| **A. 手输猜解** | 拿到已开机但 App 处于锁定态的手机，反复试主密码 | ✅ 有效（本方案主战场） | 失败退避 + 持久化计数 |
| **B. 离线爆破** | 越狱/取证取出 salt 与加密后的 DEK，上 GPU/ASIC 跑字典 | ❌ 无效，计数器形同虚设 | KDF 成本 + 主密码强度（见 3.3.2） |
| **C. 生物识别旁路** | 通过 Face ID 或设备密码直接读取生物识别 DEK，绕开主密码 | ❌ 无关 | 生物识别策略（后续版本） |

因此本方案**不为"防篡改计数器"引入额外复杂度**：能改本地存储的攻击者本来就能走 B 类，与其加固计数器，不如把投入放在 KDF 与密码强度上。

**退避策略**

| 连续失败 | 处置 |
|---------|------|
| 1–4 次 | 不延迟（留给正常用户偶尔输错的余量），仅提示密码错误 |
| 5 次 | 冷却 30 秒 |
| 6 次 | 冷却 60 秒 |
| 7 次 | 2 分钟 |
| 8 次 | 5 分钟 |
| 9 次 | 15 分钟 |
| ≥ 10 次 | 30 分钟（封顶） |

补充规则：

- **成功即清零**：密码解锁、生物识别、二次验证任一成功，计数与冷却一并清除；
- **24 小时衰减**：距上次失败超过 24 小时视为新的一轮，避免历史失败长期累积惩罚；
- **冷却期内不消耗算力**：拦截发生在 PBKDF2 派生**之前**，冻结期间不会白烧每次 0.3–0.8 秒的 CPU；
- **生物识别失败不计入**：Face ID 的尝试次数由系统自己限制，重复计数只会误伤正常用户。

**拦截点**

三条会校验主密码的链路都汇聚在 `AppState`，闸门统一架在这一层（而不是 ViewModel），否则"重置密码库的二次验证"会变成一条免费的重试通道：

```text
解锁页         → AuthenticationViewModel.unlock()      → AppState.unlockVault(with:)
重置密码库验证  → SettingsViewModel.verifyAndReset()    → AppState.verifyMasterPassword(_:)
生物识别       → BiometricButton                       → AppState.unlockWithBiometrics()
```

冷却期内三条链路一律抛 `UnlockThrottledError` 直接返回，不进入密钥派生。

**持久化**

计数存 Keychain（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`），与 salt、加密 DEK 同一套可访问性：不进备份、不跨设备同步，**杀掉进程或重启 App 都无法绕过**。设备锁定期间读不到时按"从未失败"处理——宁可放行，也不误伤正常用户。

**界面表现**

| 位置 | 表现 |
|-----|------|
| 解锁按钮 | 冷却期内置灰不可点（`canUnlock` 增加冷却判断） |
| 密码框下方 | 常驻一行提示：警告图标 + "尝试次数过多" + 倒计时胶囊（不足 1 分钟显示 `29s`，否则 `5:00`） |
| 键盘 Go 提交 | 走 toast 提示"尝试次数过多，请稍后再试"，不静默失败 |

倒计时数值每秒由 `AppState` 心跳刷新，界面通过 `@EnvironmentObject` 订阅；空闲时数值不变则不推送，不产生无谓刷新。

**已知缺口（后续版本）**

1. **B 类防护**：KDF 迭代次数目前是硬编码常量，需先把参数写入密码库才能安全升级，再评估迁移 Argon2id；
2. **主密码强度门槛**：当前只看长度与字符类型，`Password123!` 会被判为 Strong，需接入弱口令与模式检测（另见 3.3.2）；
3. **C 类旁路**：生物识别 DEK 的 ACL 为 `userPresence`，设备数字密码同样可解，需单独设计强制主密码的策略。

### 3.4 数据存储设计

#### 3.4.1 数据库Schema

```swift
// Core Data Entities

@Entity
class PasswordEntry {
    @ID var id: UUID
    @Attribute(.externalStorage) var encryptedData: Data  // 加密的密码数据
    var siteName: String
    var siteURL: String?
    var username: String
    var category: String
    var tags: [String]
    var isFavorite: Bool
    var passwordStrength: Int
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var expiresAt: Date?
    var icon: String?
    @Relationship(deleteRule: .cascade) var totpCredential: TOTPCredential?
}

@Entity
class TOTPCredential {
    @ID var id: UUID
    var issuer: String?
    var accountName: String
    @Attribute(.externalStorage) var encryptedSecret: Data
    var digits: Int
    var period: Int
    var algorithm: String
    var createdAt: Date
    var lastUsedAt: Date?
}

@Entity
class OAuthCredential {
    @ID var id: UUID
    var provider: String
    var userId: String
    var email: String?
    var name: String?
    @Attribute(.externalStorage) var encryptedAccessToken: Data
    @Attribute(.externalStorage) var encryptedRefreshToken: Data?
    var expiresAt: Date?
    var createdAt: Date
    var lastUsedAt: Date?
}

@Entity
class UserSettings {
    @ID var id: UUID
    var biometricEnabled: Bool
    var autoLockTimeout: Int  // 秒
    var clipboardClearTimeout: Int  // 秒
    var passwordGeneratorRule: Data  // 序列化的生成规则
    var theme: String
    var language: String
}
```

#### 3.4.2 数据备份与恢复

```swift
class BackupManager {
    // 创建加密备份
    func createEncryptedBackup() throws -> URL {
        // 1. 导出所有数据
        let entries = try passwordManager.exportAllEntries()
        let credentials = try totpManager.exportAllCredentials()
        
        // 2. 序列化为JSON
        let backupData = try JSONEncoder().encode(BackupData(
            version: "1.0",
            entries: entries,
            credentials: credentials,
            createdAt: Date()
        ))
        
        // 3. 加密备份数据
        let encryptedBackup = try encryptionService.encrypt(
            backupData,
            using: backupEncryptionKey
        )
        
        // 4. 保存到文件
        let fileURL = try saveToFile(encryptedBackup, name: "vaultcell_backup_\(Date()).vbackup")
        return fileURL
    }
    
    // 从备份恢复
    func restoreFromBackup(_ url: URL, password: String) throws {
        // 1. 读取备份文件
        let encryptedData = try Data(contentsOf: url)
        
        // 2. 解密备份数据
        let backupData = try encryptionService.decrypt(encryptedData, using: password)
        
        // 3. 解析JSON
        let backup = try JSONDecoder().decode(BackupData.self, from: backupData)
        
        // 4. 验证版本兼容性
        guard backup.version == "1.0" else {
            throw BackupError.incompatibleVersion
        }
        
        // 5. 恢复数据
        try passwordManager.importEntries(backup.entries)
        try totpManager.importCredentials(backup.credentials)
    }
}
```

### 3.5 自动填充扩展架构

```
┌─────────────────────────────────────────────────────┐
│              Main App (Container App)               │
│  ┌──────────────────────────────────────────────┐  │
│  │  - 密码管理界面                               │  │
│  │  - 设置与配置                                 │  │
│  │  - 数据同步                                   │  │
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │  App Groups (共享数据容器)                    │  │
│  │  - 共享UserDefaults                           │  │
│  │  - 共享Keychain                               │  │
│  │  - 共享数据库文件                              │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         │
                         │ App Groups
                         │
┌─────────────────────────────────────────────────────┐
│       Credential Provider Extension                 │
│  ┌──────────────────────────────────────────────┐  │
│  │  ASCredentialProviderViewController          │  │
│  │  - prepareCredentialList                     │  │
│  │  - provideCredentialWithoutUserInteraction   │  │
│  │  - saveCredential                           │  │
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │  Credential Selection UI                     │  │
│  │  - SwiftUI界面                               │  │
│  │  - 生物识别验证                               │  │
│  │  - 密码条目列表                               │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 4. UI/UX设计规范

### 4.1 设计原则

1. **安全优先**: 所有敏感信息默认隐藏，需要主动显示
2. **简洁高效**: 最少点击次数完成任务，常用功能快速访问
3. **一致性**: 遵循iOS Human Interface Guidelines，保持系统一致性
4. **可访问性**: 支持动态字体、VoiceOver、高对比度模式

### 4.2 信息架构

```
Tab Bar Navigation:
├── 密码库
│   ├── 全部密码列表
│   ├── 分类筛选
│   ├── 搜索
│   └── 添加新密码
├── 验证码
│   ├── 验证码列表
│   ├── 扫码添加
│   └── 手动添加
├── 生成器
│   ├── 密码生成
│   ├── 规则配置
│   └── 历史记录
├── 第三方登录
│   ├── 已绑定账号
│   ├── 添加新账号
│   └── 快速登录
└── 设置
    ├── 安全设置
    ├── 外观设置
    ├── 数据管理
    ├── 关于
    └── 帮助与反馈
```

### 4.3 核心界面设计

#### 4.3.1 密码库主界面

```
┌─────────────────────────────────────┐
│  ≡  VaultCell              🔍 ⚙️      │  ← 导航栏
├─────────────────────────────────────┤
│  全部  社交  工作  金融  购物  娱乐  │  ← 分类标签
├─────────────────────────────────────┤
│  ⭐ Google                          │
│     user@gmail.com                  │  ← 密码条目
│     ●●●●●●●●●●●●                    │
├─────────────────────────────────────┤
│  🏦 中国银行                        │
│     6228****                        │
│     ●●●●●●●●●●●●                    │
├─────────────────────────────────────┤
│  🛒 淘宝                            │
│     user123                         │
│     ●●●●●●●●●●●●                    │
├─────────────────────────────────────┤
│  💬 微信                            │
│     user123                         │
│     ●●●●●●●●●●●●                    │
├─────────────────────────────────────┤
│                 +                   │  ← 悬浮添加按钮
└─────────────────────────────────────┘
```

#### 4.3.2 密码详情界面

```
┌─────────────────────────────────────┐
│  ←  密码详情              编辑      │
├─────────────────────────────────────┤
│                                     │
│          🌐 Google                  │
│                                     │
├─────────────────────────────────────┤
│  站点名称                           │
│  Google                    📋       │
├─────────────────────────────────────┤
│  网址                               │
│  https://google.com       📋 🌐     │
├─────────────────────────────────────┤
│  用户名                             │
│  user@gmail.com           📋       │
├─────────────────────────────────────┤
│  密码                               │
│  ●●●●●●●●●●●●       👁 📋 🔄       │
│  强度: ████████░░ 很强              │
├─────────────────────────────────────┤
│  验证码                             │
│  123 456  (剩余 23s)      📋       │
├─────────────────────────────────────┤
│  备注                               │
│  主要工作账号                       │
├─────────────────────────────────────┤
│  标签                               │
│  工作  重要                         │
├─────────────────────────────────────┤
│  创建时间: 2026-01-15 10:30        │
│  更新时间: 2026-03-20 15:45        │
│  最后使用: 2026-06-03 09:00        │
└─────────────────────────────────────┘
```

#### 4.3.3 密码生成器界面

```
┌─────────────────────────────────────┐
│  密码生成器                         │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │  Kj#9mP$2xLqW8nF            │   │
│  │  ●●●●●●●●●●●●●●●●           │   │
│  └─────────────────────────────┘   │
│                                     │
│  强度: ████████████ 非常强          │
│                                     │
│  📋 复制    🔄 重新生成             │
│                                     │
├─────────────────────────────────────┤
│  长度: 16                           │
│  ├───────●───────────────────┤    │
│  6                           128    │
├─────────────────────────────────────┤
│  字符类型                           │
│  ☑ 大写字母 (A-Z)                  │
│  ☑ 小写字母 (a-z)                  │
│  ☑ 数字 (0-9)                      │
│  ☑ 特殊符号 (!@#$%^&*)             │
├─────────────────────────────────────┤
│  高级选项                           │
│  ☑ 排除相似字符 (0OIl1)            │
│  ☐ 排除特定字符                     │
│  ☐ 保存生成规则                     │
├─────────────────────────────────────┤
│  预设模板                           │
│  [强密码] [PIN码] [密码短语]        │
└─────────────────────────────────────┘
```

### 4.4 交互设计

#### 4.4.1 手势与操作

| 操作 | 手势 | 功能 |
|-----|------|------|
| 查看密码 | 长按密码字段 | 临时显示明文密码 |
| 复制密码 | 点击密码字段 | 复制到剪贴板并提示 |
| 快速填充 | 左滑密码条目 | 显示快速操作菜单 |
| 删除密码 | 右滑密码条目 | 删除确认 |
| 批量操作 | 长按列表 | 进入多选模式 |
| 搜索 | 下拉列表 | 显示搜索栏 |

#### 4.4.2 动画与反馈

- **成功操作**: 轻微震动 + 绿色对勾图标
- **错误提示**: 红色警告图标 + 错误信息
- **复制成功**: Toast提示"已复制到剪贴板"
- **删除确认**: 底部弹出确认对话框
- **生物识别**: Face ID/Touch ID动画

### 4.5 视觉设计

#### 4.5.1 配色方案

```
主色调:
- Primary: #007AFF (iOS蓝)
- Secondary: #5856D6 (紫色)
- Success: #34C759 (绿色)
- Warning: #FF9500 (橙色)
- Danger: #FF3B30 (红色)

中性色:
- Background: #F2F2F7 (浅灰背景)
- Surface: #FFFFFF (白色卡片)
- Text Primary: #000000 (黑色文字)
- Text Secondary: #8E8E93 (灰色文字)
- Border: #C6C6C8 (边框灰)

深色模式:
- Background: #000000
- Surface: #1C1C1E
- Text Primary: #FFFFFF
- Text Secondary: #8E8E93
```

#### 4.5.2 图标设计

- 使用SF Symbols系统图标
- 自定义图标采用圆角矩形风格
- 分类图标使用emoji或自定义图标
- 网站favicon自动获取并缓存

---

## 5. 开发计划

### 5.1 里程碑规划

#### Phase 1: 基础架构 (2周)
**目标**: 搭建项目基础架构和核心安全模块

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| 项目初始化 | 1天 | Xcode项目、目录结构、Git仓库 |
| Core Data模型设计 | 2天 | 数据模型、数据库Schema |
| 加密服务实现 | 3天 | AES-256-GCM加密、密钥派生 |
| Keychain集成 | 2天 | 密钥安全存储、生物识别集成 |
| 主密码验证流程 | 2天 | 主密码设置、验证、修改 |
| 单元测试 | 2天 | 加密模块测试、密钥管理测试 |

#### Phase 2: 密码库核心功能 (3周)
**目标**: 实现密码库的完整CRUD功能

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| 密码条目UI | 3天 | 列表页、详情页、编辑页 |
| 密码CRUD功能 | 3天 | 添加、编辑、删除、查看 |
| 分类管理 | 2天 | 分类列表、自定义分类 |
| 搜索与筛选 | 2天 | 全文搜索、高级筛选 |
| 密码强度分析 | 2天 | 强度算法、可视化显示 |
| 导入导出 | 3天 | CSV/JSON导入导出、格式转换 |
| UI/UX优化 | 2天 | 动画、交互优化、深色模式 |

#### Phase 3: 自动填充扩展 (2周)
**目标**: 实现系统级自动填充功能

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| Extension Target创建 | 1天 | Credential Provider Extension |
| 数据共享配置 | 2天 | App Groups、共享Keychain |
| 自动填充UI | 3天 | 凭证选择界面、生物识别 |
| 自动填充逻辑 | 3天 | URL匹配、凭证提供、保存 |
| 测试与调试 | 2天 | Safari测试、第三方App测试 |

#### Phase 4: 密码生成器 (1周)
**目标**: 实现可自定义的密码生成功能

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| 生成器UI | 2天 | 生成器界面、规则配置 |
| 生成算法 | 2天 | 随机密码生成、强度计算 |
| 规则管理 | 1天 | 预设规则、自定义规则保存 |

#### Phase 5: 第三方登录 (1.5周)
**目标**: 实现OAuth第三方登录功能

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| Sign in with Apple | 2天 | Apple登录集成 |
| Google OAuth | 2天 | Google登录集成 |
| 微信登录 | 2天 | 微信SDK集成 |
| Token管理 | 1天 | Token安全存储、刷新 |

#### Phase 6: 验证码功能 (1.5周)
**目标**: 实现TOTP验证码功能

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| TOTP算法实现 | 2天 | TOTP生成、倒计时 |
| 验证码UI | 2天 | 验证码列表、详情页 |
| 扫码导入 | 2天 | 相机扫码、二维码解析 |
| 与密码关联 | 1天 | 绑定显示、快速访问 |

#### Phase 7: 测试与优化 (1周)
**目标**: 全面测试和性能优化

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| 单元测试补充 | 2天 | 测试覆盖率>80% |
| UI测试 | 2天 | 关键流程UI测试 |
| 性能优化 | 1天 | 启动时间、内存优化 |
| Bug修复 | 1天 | 测试问题修复 |

#### Phase 8: 上线准备 (0.5周)
**目标**: App Store上线准备

| 任务 | 预估时间 | 交付物 |
|-----|---------|--------|
| App Store素材 | 1天 | 图标、截图、描述 |
| 隐私政策 | 0.5天 | 隐私政策文档 |
| 提交审核 | 1天 | App Store Connect提交 |

### 5.2 总体时间线

```
Week 1-2:   Phase 1 - 基础架构
Week 3-5:   Phase 2 - 密码库核心功能
Week 6-7:   Phase 3 - 自动填充扩展
Week 8:     Phase 4 - 密码生成器
Week 9-10:  Phase 5 - 第三方登录
Week 11-12: Phase 6 - 验证码功能
Week 13:    Phase 7 - 测试与优化
Week 14:    Phase 8 - 上线准备
```

**总计: 约14周 (3.5个月)**

### 5.3 团队配置建议

| 角色 | 人数 | 职责 |
|-----|------|------|
| iOS开发工程师 | 2人 | 核心功能开发、Extension开发 |
| UI/UX设计师 | 1人 | 界面设计、交互设计、图标设计 |
| 测试工程师 | 1人 | 功能测试、安全测试、兼容性测试 |
| 产品经理 | 0.5人 | 需求管理、进度跟踪、上线协调 |

---

## 6. 非功能性需求

### 6.1 性能要求

| 指标 | 目标值 | 测试方法 |
|-----|-------|---------|
| 应用启动时间 | < 2秒 | 冷启动测试 |
| 密码列表加载 | < 500ms (1000条) | 性能测试 |
| 搜索响应时间 | < 200ms | 搜索性能测试 |
| 自动填充响应 | < 1秒 | Extension性能测试 |
| 内存占用 | < 100MB | 内存监控 |
| 数据库大小 | < 50MB (1000条) | 存储测试 |

### 6.2 安全要求（企业级标准）

| 类别 | 要求 | 实现方式 | 参考标准 |
|-----|------|---------|---------|
| **KDF算法** | PBKDF2-SHA256 600,000次迭代 | 默认使用，可选Argon2id | OWASP 2026, NIST SP 800-132 |
| **加密算法** | AES-256-GCM 认证加密 | 每条目独立加密 + 96位随机Nonce | NIST SP 800-38D |
| **密钥管理** | HKDF分层密钥派生 | DEK/KEK/HMAC分离，职责隔离 | NIST SP 800-56C |
| **密钥存储** | Keychain + Secure Enclave | 硬件安全模块隔离存储 | Apple Security Framework |
| **内存安全** | 自动擦除 + 内存锁定 | mlock() + 保护页 + 多次覆盖 | 军事级内存安全 |
| **防暴力破解** | 连续失败阶梯退避：免罚 4 次，第 5 次起 30s 起跳、30min 封顶 | AppState 三处校验链统一闸门 + Keychain 持久化计数 + 冷却倒计时（详见 3.3.7） | OWASP推荐 |
| **生物识别** | Secure Enclave绑定验证 | 用户在场要求 + 硬件验证 | LocalAuthentication |
| **数据完整性** | AAD关联数据认证 | 防止替换和篡改攻击 | AES-GCM |
| **零泄漏** | 主密钥永不写入磁盘 | 仅内存存在，自动清理 | 零知识架构 |
| **自动锁定** | 后台30秒自动锁定 | 可配置时间 | 用户设置 |
| **剪贴板安全** | 复制后60秒自动清理 | 多次覆盖防止残留 | 剪贴板保护 |
| **防截屏** | 敏感页面禁止截屏 | UIWindow层级保护 | iOS安全API |
| **防录制** | 检测屏幕录制并提示 | 监听UIScreen通知 | iOS安全API |
| **越狱检测** | 多种检测方式 | 检测关键文件/系统函数 | 安全防护 |
| **调试器检测** | 运行时检测调试器 | ptrace/sysctl/mach_port检测 | 防逆向 |
| **代码完整性** | 运行时完整性校验 | 哈希验证关键代码段 | 防篡改 |
| **网络安全** | 本地优先，禁用不必要网络 | 可选iCloud同步时使用TLS 1.3 | ATS, TLS 1.3 |

### 6.3 兼容性要求

| 项目 | 要求 |
|-----|------|
| iOS版本 | iOS 15.0+ |
| 设备 | iPhone 6s及以上 |
| 方向 | 仅竖屏（密码详情页支持横屏） |
| 深色模式 | 完整支持 |
| 动态字体 | 支持 |
| VoiceOver | 完整支持 |
| iPad | 适配iPad界面 |

### 6.4 可维护性要求

- 代码覆盖率 > 80%
- 模块化设计，职责清晰
- 完善的错误日志系统
- 支持远程配置（可选）

---

## 7. 风险评估与应对

### 7.1 技术风险

| 风险 | 影响 | 概率 | 应对措施 |
|-----|------|------|---------|
| Extension性能不达标 | 高 | 中 | 优化数据库查询、缓存机制 |
| 加密算法实现漏洞 | 高 | 低 | 使用CryptoKit、代码审查、安全测试 |
| iOS系统更新兼容性 | 中 | 中 | 及时适配新版本、Beta测试 |
| 第三方OAuth API变更 | 中 | 中 | 抽象接口层、及时更新SDK |

### 7.2 产品风险

| 风险 | 影响 | 概率 | 应对措施 |
|-----|------|------|---------|
| 用户接受度低 | 高 | 中 | 用户调研、MVP测试、快速迭代 |
| 竞品压力 | 中 | 高 | 差异化功能、用户体验优化 |
| 安全事故 | 高 | 低 | 安全审计、漏洞奖励计划 |

### 7.3 合规风险

| 风险 | 影响 | 概率 | 应对措施 |
|-----|------|------|---------|
| App Store审核拒绝 | 高 | 中 | 遵循审核指南、提前沟通 |
| 隐私合规问题 | 高 | 低 | 隐私政策、数据最小化 |
| 加密出口限制 | 中 | 低 | 使用系统加密框架 |

---

## 8. 成功指标

### 8.1 产品指标

| 指标 | 目标值 | 衡量周期 |
|-----|-------|---------|
| 日活跃用户(DAU) | 10,000+ | 上线后3个月 |
| 用户留存率(次日) | > 40% | 上线后1个月 |
| 用户留存率(7日) | > 20% | 上线后1个月 |
| App Store评分 | > 4.5星 | 持续 |
| 崩溃率 | < 0.1% | 持续 |

### 8.2 功能使用指标

| 功能 | 目标使用率 |
|-----|----------|
| 自动填充 | > 80% |
| 密码生成器 | > 60% |
| 验证码功能 | > 40% |
| 第三方登录 | > 30% |
| **2FA管理** | > 50% ⭐ |
| **2FA审计报告查看** | > 30% ⭐ |

### 8.3 2FA安全指标

| 指标 | 目标值 | 说明 |
|-----|-------|------|
| 2FA覆盖率 | > 70% | 有密码的账户中启用2FA的比例 |
| 高安全2FA占比 | > 50% | TOTP/硬件密钥占所有2FA的比例 |
| 2FA验证通过率 | > 95% | 2FA验证成功率 |
| 2FA审计完成率 | > 40% | 用户查看2FA审计报告的比例 |

---

## 9. 后续规划

### 9.1 v1.1版本规划

- iCloud同步功能
- 密码共享功能（家庭共享）
- 密码健康检查报告
- 多语言支持
- **2FA安全审计功能** ⭐
- **2FA类型识别与评级** ⭐
- **2FA与密码条目关联管理** ⭐

### 9.2 v1.2版本规划

- iPad原生适配
- Apple Watch配套App
- Safari扩展增强
- 密码泄露检测
- **2FA健康检查（未启用2FA提醒）** ⭐
- **批量2FA扫描** ⭐

### 9.3 v2.0版本规划

- 团队版本（企业协作）
- 云端加密备份
- 跨平台支持（macOS、Web）
- API密钥管理
- **2FA恢复指导助手** ⭐
- **2FA风险评估报告** ⭐

---

## 10. 附录

### 10.1 参考资料

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple Authentication Services](https://developer.apple.com/documentation/authenticationservices)
- [CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)
- [RFC 6238: TOTP](https://tools.ietf.org/html/rfc6238)
- [RFC 6749: OAuth 2.0](https://tools.ietf.org/html/rfc6749)

### 10.2 术语表

| 术语 | 说明 |
|-----|------|
| TOTP | Time-based One-Time Password，基于时间的一次性密码 |
| OAuth | Open Authorization，开放授权协议 |
| AES | Advanced Encryption Standard，高级加密标准 |
| PBKDF2 | Password-Based Key Derivation Function 2，基于密码的密钥派生函数 |
| Keychain | iOS系统安全存储服务 |
| Extension | iOS应用扩展 |
| **2FA** | Two-Factor Authentication，双因素认证 |
| **SMS 2FA** | 通过短信接收验证码的双因素认证 |
| **Email 2FA** | 通过邮件接收验证码的双因素认证 |
| **Hardware Key** | 硬件安全密钥（如YubiKey） |
| **Backup Codes** | 备用码，用于2FA恢复的一次性码 |
| **SIM Swapping** | SIM卡交换攻击，2FA安全风险之一 |

### 10.3 安全合规参考

| 标准 | 合规项目 | 实现状态 |
|-----|---------|---------|
| NIST SP 800-132 | 密码存储最佳实践 | ✅ |
| NIST SP 800-38D | AES-GCM使用规范 | ✅ |
| NIST SP 800-56C | 密钥派生规范 | ✅ |
| NIST SP 800-140B | 密码模块验证 | ⏳ (可选) |
| OWASP Mobile Top 10 | 移动应用安全 | ✅ |
| GDPR/CCPA | 数据隐私保护 | ✅ |
| FIPS 140-3 Level 2 | 加密模块 (可选) | ⏳ |

### 10.4 安全承诺

1. **零知识架构**: 我们永远无法访问您的密码数据，即使服务器被攻破也毫无价值
2. **本地优先**: 所有数据默认存储在本地设备，不上传任何服务器
3. **端到端加密**: 即使开启云同步，数据也只在您的设备上加密和解密
4. **开源可审计**: 核心加密模块完全开源，接受安全社区审计
5. **漏洞奖励**: 设立安全漏洞奖励计划，鼓励安全研究人员报告
6. **无后门保证**: 承诺不会在任何版本中加入后门或隐藏功能

### 10.6 更新历史

| 版本 | 日期 | 更新内容 | 作者 |
|-----|------|---------|------|
| 1.3 | 2026-10-18 | 3.3.7 重写为已落地的主密码失败限流方案（威胁分层、退避阶梯、拦截点、持久化、界面表现），移除未实现的示意代码 | Security Team |
| 1.2 | 2026-06-03 | 新增2FA管理功能完整设计 | Product Team |
| 1.1 | 2026-06-03 | 增强安全架构，升级至企业级标准 | Security Team |
| 1.0 | 2026-06-03 | 初稿完成 | Product Team |

---

**文档结束**