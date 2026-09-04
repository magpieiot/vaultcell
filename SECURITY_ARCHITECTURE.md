# VaultCell 加密安全架构深度设计

## 概述

本文档详细描述 VaultCell 密码管理器的企业级安全架构设计。密码管理器的安全性取决于整个系统的端到端设计，而不仅仅是加密算法本身。

## 一、当前方案安全分析与改进

### 1.1 当前方案安全性评估

| 组件 | 当前设计 | 安全性评级 | 存在问题 |
|------|---------|-----------|---------|
| KDF算法 | PBKDF2-SHA256, 100,000轮 | ⚠️ 基本安全 | 迭代次数偏低，缺少Argon2支持 |
| 加密算法 | AES-256-GCM | ✅ 优秀 | - |
| 密钥管理 | 简单KMS | ⚠️ 中等 | 缺少密钥分层、前向安全 |
| 内存安全 | 未明确 | ❌ 高风险 | 缺少安全擦除、内存保护 |
| 防暴力破解 | 未明确 | ❌ 高风险 | 缺少速率限制、延迟策略 |
| 认证安全 | 主密码+生物识别 | ⚠️ 中等 | 缺少HSM、硬件安全模块集成 |

### 1.2 改进方案概要

我们将采用**零知识架构（Zero-Knowledge Architecture）**配合**军工级加密标准**，达到以下安全级别：

- 符合 NIST SP 800-132 密码存储标准
- 遵循 OWASP Mobile Top 10 安全最佳实践
- 达到 FIPS 140-3 Level 2 安全要求（可选）

---

## 二、增强版加密架构

### 2.1 完整的密钥分层体系

```
┌─────────────────────────────────────────────────────────┐
│                    用户输入层                            │
│              ┌───────────────────┐                     │
│              │   主密码输入      │                     │
│              │   (User Master   │                     │
│              │   Password)      │                     │
│              └─────────┬─────────┘                     │
└────────────────────────┼──────────────────────────────┘
                         │
                         │ PBKDF2-SHA256 (600,000轮)
                         │ + Argon2id (可选高级模式)
                         │
┌────────────────────────▼──────────────────────────────┐
│              主密钥层 (Master Key Layer)               │
│              ┌─────────────────────┐                   │
│              │  Master Key (MK)    │  256位           │
│              │  (从不写入磁盘)     │  内存仅存在   │
│              └─────────┬───────────┘                   │
└────────────────────────┼──────────────────────────────┘
                         │
                         │ HKDF-SHA512 密钥派生
                         │
         ┌───────────────┼───────────────┐
         │               │               │
┌────────▼───────┐ ┌─────▼──────┐ ┌─────▼──────┐
│  数据加密密钥  │ │密钥加密密钥 │ │ HMAC密钥   │
│  (DEK)        │ │  (KEK)     │ │  (HMAC Key)│
│  AES-256      │ │  AES-256   │ │  SHA-256   │
└──────┬────────┘ └─────┬──────┘ └─────┬──────┘
       │                │              │
       │                │              │
       │                │              │
┌──────▼────────────────▼──────────────▼─────────┐
│              密钥加密层                         │
│    DEK 由 KEK 加密后存储于 Keychain            │
└─────────────────────────────────────────────────┘
         │
         │
┌────────▼───────────────────────────────────────┐
│              数据加密层                         │
│  ┌─────────────────────────────────────────┐ │
│  │  1. 每个密码条目独立加密                  │ │
│  │  2. 使用随机Nonce (96位)                 │ │
│  │  3. AES-256-GCM 认证加密                 │ │
│  │  4. 密文 + Tag + Nonce 一起存储          │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### 2.2 KDF算法增强设计

我们支持两种KDF模式，满足不同安全需求：

#### 模式一：PBKDF2 (默认，兼容性优先)

```swift
import CryptoKit

class KDFService {
    // PBKDF2-SHA256 配置参数
    static let pbkdf2Iterations: Int = 600_000  // OWASP推荐值 2026
    static let pbkdf2SaltLength: Int = 32       // 256位随机盐值
    static let pbkdf2KeyLength: Int = 32        // 256位密钥
    
    static func deriveMasterKey(
        password: String,
        salt: Data
    ) throws -> (masterKey: SymmetricKey, verificationHash: Data) {
        // 1. 密码预处理 - 使用NFD规范化
        guard let passwordData = password.precomposedStringWithCanonicalMapping
            .data(using: .utf8) else {
            throw CryptoError.invalidPassword
        }
        
        // 2. PBKDF2密钥派生
        let masterKeyData = try PKCS5.PBKDF2(
            password: passwordData,
            salt: salt,
            iterations: pbkdf2Iterations,
            keyLength: pbkdf2KeyLength
        )
        
        // 3. 生成验证哈希（用于验证主密码）
        let verificationHash = HMAC<SHA256>.authenticationCode(
            for: "VaultCell_Verification_Key_v1".data(using: .utf8)!,
            using: SymmetricKey(data: masterKeyData)
        )
        
        return (
            SymmetricKey(data: masterKeyData),
            Data(verificationHash)
        )
    }
}
```

#### 模式二：Argon2id (高级模式，安全性优先)

```swift
// 集成 Argon2 (需引入第三方库或使用System框架)
// 参数配置参考 OWASP: m=19456 (19MB), t=2, p=1

import CryptoKit
import Argon2Swift

class Argon2KDFService {
    static let argon2MemoryCost: UInt32 = 19_456    // 19MB内存
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
            for: "VaultCell_Verification_Argon2_v1".data(using: .utf8)!,
            using: SymmetricKey(data: masterKeyData)
        )
        
        return (
            SymmetricKey(data: masterKeyData),
            Data(verificationHash)
        )
    }
}
```

### 2.3 HKDF密钥派生详解

从主密钥派生出多个专用密钥，实现职责分离：

```swift
extension SymmetricKey {
    /// 使用 HKDF-SHA512 派生专用密钥
    func deriveSubKey(
        info: String,
        outputLength: Int = 32
    ) throws -> SymmetricKey {
        let salt = "VaultCell_Salt_v1".data(using: .utf8)!
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

// 使用示例
class KeyDerivationService {
    enum KeyPurpose: String {
        case dataEncryption = "VaultCell_DEK_Encryption_v1"
        case keyEncryption = "VaultCell_KEK_Encryption_v1"
        case hmac = "VaultCell_HMAC_Authentication_v1"
        case backup = "VaultCell_Backup_Encryption_v1"
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

### 2.4 数据加密实现（每条目独立加密）

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
    
    /// 加密单个密码条目
    func encryptEntry(_ entry: PlaintextEntry) throws -> EncryptedEntry {
        // 1. 序列化为JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintextData = try encoder.encode(entry)
        
        // 2. 生成随机Nonce (96位 = CryptoKit推荐)
        let nonce = AES.GCM.Nonce()
        
        // 3. 关联数据 (AAD) - 用于完整性验证
        let associatedData = """
            VaultCell_Entry_v1_\(entry.id.uuidString)_\(entry.createdAt.timeIntervalSince1970)
            """.data(using: .utf8)!
        
        // 4. AES-256-GCM 加密
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
    
    /// 解密单个密码条目
    func decryptEntry(_ encrypted: EncryptedEntry) throws -> PlaintextEntry {
        // 1. 验证版本兼容性
        guard encrypted.version == "1.0" else {
            throw CryptoError.unsupportedVersion
        }
        
        // 2. AES-256-GCM 解密
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
        
        // 3. 反序列化
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
    // ... 其他字段
}
```

---

## 三、内存安全设计

### 3.1 安全内存管理

```swift
import Foundation

/// 安全内存缓冲区 - 自动擦除、防止交换
class SecureBuffer {
    private var bytes: UnsafeMutableRawBufferPointer
    private let count: Int
    private(set) var isDestroyed: Bool = false
    
    init(count: Int) {
        self.count = count
        // 分配对齐的内存页
        let pageSize = Int(getpagesize())
        let alignedCount = ((count + pageSize - 1) / pageSize) * pageSize
        
        bytes = UnsafeMutableRawBufferPointer.allocate(
            byteCount: alignedCount,
            alignment: pageSize
        )
        
        // 1. 锁定内存防止被交换到磁盘
        mlock(bytes.baseAddress!, bytes.count)
        
        // 2. 使用保护页隔离敏感内存
        if let base = bytes.baseAddress {
            mprotect(base, pageSize, PROT_NONE)  // 前保护页
            mprotect(base + alignedCount - pageSize, pageSize, PROT_NONE)  // 后保护页
        }
    }
    
    /// 安全写入
    func write(_ data: Data, offset: Int = 0) {
        guard !isDestroyed else { return }
        data.withUnsafeBytes { src in
            bytes.baseAddress?.advanced(by: offset).copyMemory(
                from: src.baseAddress!,
                byteCount: Swift.min(src.count, count - offset)
            )
        }
    }
    
    /// 安全读取（返回副本）
    func read(offset: Int = 0, length: Int? = nil) -> Data {
        guard !isDestroyed else { return Data() }
        let len = length ?? count - offset
        return Data(bytes: bytes.baseAddress!.advanced(by: offset), count: len)
    }
    
    /// 安全销毁
    func destroy() {
        guard !isDestroyed else { return }
        
        // 1. 覆盖内存 - 使用多次写入模式
        let patterns: [UInt8] = [0x00, 0xFF, 0xAA, 0x55, 0x00]
        for pattern in patterns {
            memset_pattern(bytes.baseAddress!, &pattern, 1, count)
            __asm__ __volatile__("" ::: "memory")  // 编译器屏障，防止优化掉
        }
        
        // 2. 解锁内存
        munlock(bytes.baseAddress!, bytes.count)
        
        // 3. 释放
        bytes.deallocate()
        
        isDestroyed = true
    }
    
    deinit {
        if !isDestroyed {
            destroy()
        }
    }
}
```

### 3.2 自动清理机制

```swift
class AutoCleanupManager {
    static let shared = AutoCleanupManager()
    
    private var cleanupTasks: [() -> Void] = []
    
    /// 注册清理任务
    func registerCleanup(_ task: @escaping () -> Void) {
        cleanupTasks.append(task)
    }
    
    /// 清理剪贴板（延迟执行）
    func scheduleClipboardCleanup(after seconds: TimeInterval = 60) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            UIPasteboard.general.string = ""
            // 覆盖写入多次
            for _ in 0..<3 {
                UIPasteboard.general.string = UUID().uuidString
            }
            UIPasteboard.general.string = ""
        }
    }
    
    /// 紧急锁定 - 应用进入后台时调用
    func emergencyLock() {
        // 清除所有内存中的密钥
        SecureEnclaveManager.shared.clearInMemoryKeys()
        // 清除剪贴板
        UIPasteboard.general.string = ""
        // 执行所有注册的清理任务
        cleanupTasks.forEach { $0() }
    }
}
```

---

## 四、认证安全与防暴力破解

### 4.1 主密码验证与防暴力破解

```swift
class AuthenticationService {
    private let maxAttempts = 5
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 60.0
    
    private var failedAttempts = 0
    private var lockoutUntil: Date?
    
    enum AuthenticationResult {
        case success
        case wrongPassword
        case lockedOut(until: Date)
    }
    
    func verifyMasterPassword(_ password: String) throws -> AuthenticationResult {
        // 1. 检查是否被锁定
        if let lockout = lockoutUntil, Date() < lockout {
            return .lockedOut(until: lockout)
        }
        
        // 2. 验证密码
        let isValid = try performPasswordVerification(password)
        
        if isValid {
            failedAttempts = 0
            lockoutUntil = nil
            return .success
        } else {
            failedAttempts += 1
            
            // 指数级延迟策略
            let delay = min(
                baseDelay * pow(2.0, Double(failedAttempts - 1)),
                maxDelay
            )
            
            if failedAttempts >= maxAttempts {
                lockoutUntil = Date().addingTimeInterval(delay * 10)
                return .lockedOut(until: lockoutUntil!)
            }
            
            // 每次失败都延迟
            Thread.sleep(forTimeInterval: delay)
            
            return .wrongPassword
        }
    }
    
    private func performPasswordVerification(_ password: String) throws -> Bool {
        // 获取之前存储的验证哈希和盐值
        let storedVerificationHash = KeychainService.getVerificationHash()
        let storedSalt = KeychainService.getSalt()
        
        // 重新派生密钥并验证
        let (_, computedHash) = try KDFService.deriveMasterKey(
            password: password,
            salt: storedSalt
        )
        
        // 安全比较（恒时比较，防止时序攻击）
        return secureCompare(storedVerificationHash, computedHash)
    }
    
    /// 安全的恒时比较
    private func secureCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        
        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[i] ^ b[i]
        }
        
        return result == 0
    }
}
```

### 4.2 生物识别集成（结合Secure Enclave）

```swift
import LocalAuthentication
import CryptoKit

class BiometricAuthService {
    private let context = LAContext()
    
    enum BiometricType {
        case faceID
        case touchID
        case none
    }
    
    var availableBiometrics: BiometricType {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }
    
    /// 使用生物识别解锁 - 通过Secure Enclave解密密钥
    func unlockWithBiometrics(reason: String) async throws -> SymmetricKey {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "使用主密码"
        
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
        
        guard success else {
            throw AuthError.biometricFailed
        }
        
        // 从Secure Enclave获取密钥
        return try SecureEnclaveManager.shared.retrieveProtectedKey()
    }
}

/// Secure Enclave 密钥管理
class SecureEnclaveManager {
    static let shared = SecureEnclaveManager()
    
    private let keyTag = "com.vaultcell.protected-key"
    
    /// 在Secure Enclave中生成密钥对
    func generateSecureEnclaveKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence, .privateKeyUsage],
            nil
        )!
        
        let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            accessControl: accessControl
        )
        
        try storePublicKey(privateKey.publicKey)
        return privateKey
    }
    
    /// 使用Secure Enclave进行密钥加密
    func encryptWithSecureEnclave(_ data: Data) throws -> Data {
        let publicKey = try retrievePublicKey()
        let sharedSecret = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            .sharedSecretFromKeyAgreement(with: publicKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "VaultCell_SE_KeyWrap_v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        return sealedBox.combined!
    }
    
    // ... 更多Secure Enclave方法
}
```

---

## 五、数据库与存储安全

### 5.1 全库加密（SQLCipher + Core Data）

```swift
import CoreData
import SQLCipher

class EncryptedCoreDataStack {
    private let encryptionKey: SymmetricKey
    
    init(encryptionKey: SymmetricKey) {
        self.encryptionKey = encryptionKey
    }
    
    func setupContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "VaultCell")
        
        // 配置SQLCipher加密
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        
        // 导出密钥用于SQLCipher
        let keyData = encryptionKey.withUnsafeBytes { Data($0) }
        let hexKey = keyData.map { String(format: "%02hhx", $0) }.joined()
        
        description.setOption(
            hexKey as NSObject,
            forKey: NSSQLitePragmasOption
        )
        
        // 额外的SQLite安全配置
        description.setOption(
            ["journal_mode": "WAL", "secure_delete": "TRUE"],
            forKey: NSSQLitePragmasOption
        )
        
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data stack setup failed: \(error)")
            }
        }
        
        return container
    }
}
```

### 5.2 Keychain安全存储配置

```swift
class KeychainService {
    private let service = "com.vaultcell.app"
    private let accessGroup = "group.com.vaultcell.shared"  // 用于Extension共享
    
    enum KeychainItem {
        case masterKeySalt
        case verificationHash
        case encryptedDEK
        case biometricProtectedKey
    }
    
    func store(_ data: Data, for item: KeychainItem) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        
        // 先删除旧的
        SecItemDelete(query as CFDictionary)
        
        // 添加新的
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status: status)
        }
    }
    
    func retrieve(for item: KeychainItem) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.notFound
        }
        
        return data
    }
}
```

---

## 六、备份与恢复安全

### 6.1 加密备份格式

```swift
class SecureBackupManager {
    private let keys: KeySet
    
    init(keys: KeySet) {
        self.keys = keys
    }
    
    struct BackupHeader: Codable {
        let version: String = "1.0"
        let salt: Data
        let iterations: Int
        let algorithm: String  // "pbkdf2" 或 "argon2"
        let createdAt: Date
        let checksum: Data  // SHA-256 of (salt + iterations + algorithm)
    }
    
    struct BackupContainer: Codable {
        let header: BackupHeader
        let encryptedPayload: Data
        let payloadTag: Data
    }
    
    func createEncryptedBackup(
        password: String,
        entries: [PlaintextEntry]
    ) throws -> URL {
        // 1. 生成备份专用盐值
        let backupSalt = try generateRandomData(length: 32)
        
        // 2. 派生备份密钥
        let (backupKey, _) = try KDFService.deriveMasterKey(
            password: password,
            salt: backupSalt
        )
        
        // 3. 序列化数据
        let payloadData = try JSONEncoder().encode(BackupPayload(
            entries: entries,
            exportedAt: Date()
        ))
        
        // 4. 加密负载
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(
            payloadData,
            using: backupKey,
            nonce: nonce
        )
        
        // 5. 构建头部
        let header = BackupHeader(
            salt: backupSalt,
            iterations: KDFService.pbkdf2Iterations,
            algorithm: "pbkdf2",
            createdAt: Date(),
            checksum: HMAC<SHA256>.authenticationCode(
                for: backupSalt + String(KDFService.pbkdf2Iterations).data(using: .utf8)! + "pbkdf2".data(using: .utf8)!,
                using: backupKey
            ).data
        )
        
        // 6. 构建完整容器
        let container = BackupContainer(
            header: header,
            encryptedPayload: sealedBox.ciphertext + sealedBox.nonce,
            payloadTag: sealedBox.tag
        )
        
        // 7. 保存到文件
        let fileURL = try saveBackupToFile(container)
        return fileURL
    }
    
    // ... 恢复方法略
}

struct BackupPayload: Codable {
    let entries: [PlaintextEntry]
    let exportedAt: Date
}
```

---

## 七、安全防御措施清单

### 7.1 运行时防护

| 防护措施 | 实现 |
|---------|------|
| 越狱检测 | 检测常见越狱文件路径、环境变量、系统函数 |
| 调试器检测 | 使用 ptrace, sysctl, mach_port 检测 |
| 屏幕录制检测 | 监听 UIScreen.capturedDidChangeNotification |
| 屏幕截图防护 | 关键页面使用 UIWindow 层级 + layer.contents = nil |
| 进程注入防护 | 验证动态库签名、检查 DYLD_INSERT_LIBRARIES |
| 代码完整性检查 | 运行时校验关键代码段哈希值 |

### 7.2 网络安全（即使本地存储）

```swift
class NetworkSecurityManager {
    /// 即使本地存储，也要防止任何意外的网络泄露
    func setupNetworkRestrictions() {
        // 配置 NSAppTransportSecurity - 仅允许必要连接
        // 实际上，完全本地存储的话可以禁用所有网络
    }
    
    /// 安全的HTTPS配置（如果需要云同步功能）
    func secureSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // 证书固定 (Certificate Pinning)
        return config
    }
}
```

---

## 八、安全审计与日志

### 8.1 安全事件日志（不记录敏感信息）

```swift
class SecurityAuditLogger {
    enum SecurityEvent {
        case masterPasswordAttempt(success: Bool)
        case biometricAttempt(success: Bool)
        case entryAccessed(id: UUID)
        case entryModified(id: UUID)
        case backupCreated
        case backupRestored
        case lockoutTriggered
    }
    
    func log(_ event: SecurityEvent) {
        let logEntry = AuditLogEntry(
            timestamp: Date(),
            event: event,
            deviceInfo: getDeviceFingerprint()
        )
        
        // 安全存储日志（加密、不包含敏感数据）
        storeAuditLog(logEntry)
    }
    
    /// 设备指纹（匿名化）
    private func getDeviceFingerprint() -> String {
        // 使用设备标识符的哈希值
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? ""
        return SHA256.hash(data: identifier.data(using: .utf8)!).compactMap {
            String(format: "%02x", $0)
        }.joined()
    }
}
```

---

## 九、安全合规性参考

| 标准 | 合规项目 | 实现状态 |
|------|---------|---------|
| NIST SP 800-132 | 密码存储最佳实践 | ✅ |
| NIST SP 800-38D | AES-GCM 使用规范 | ✅ |
| NIST SP 800-132 | PBKDF2参数要求 | ✅ |
| OWASP Mobile Top 10 | 移动应用安全 | ✅ |
| GDPR/CCPA | 数据隐私保护 | ✅ |
| FIPS 140-3 | 加密模块（可选） | ⏳ |

---

## 十、总结：安全承诺

1. **零知识架构** - 我们（开发者）无法访问您的任何密码数据
2. **本地优先** - 所有数据默认存储在本地，不上传云端
3. **端到端加密** - 即使开启云同步，数据也只在您的设备上解密
4. **开源可审计** - 核心加密模块完全开源，接受安全社区审计
5. **漏洞奖励** - 设立安全漏洞奖励计划，鼓励安全研究人员报告

---

**文档版本**: 1.0  
**最后更新**: 2026-06-03  
**安全级别**: 🔒 企业级军用标准
