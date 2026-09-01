# VaultGo - iOS密码管理器 技术架构设计文档

## 文档信息

| 项目 | 内容
---|---
文档名称 | VaultGo技术架构设计
文档版本 | 1.0
创建日期 | 2026-06-03
最后更新 | 2026-06-03
作者 | 开发团队
状态 | 初稿

---

## 1. 架构概述

### 1.1 技术栈选型

| 领域 | 技术选型 | 说明
---|---|---
开发语言 | Swift 5.8+ | 现代Swift语法，性能好，安全性高
UI框架 | SwiftUI + UIKit | SwiftUI为主，UIKit用于复杂交互
架构模式 | MVVM + Clean Architecture | 清晰分层，依赖注入
数据持久化 | Core Data + SQLiteCipher | Core Data对象关系映射，SQLCipher提供加密
加密算法 | CryptoKit | 系统官方加密框架
密钥存储 | Keychain Services | 系统级安全存储，Secure Enclave
生物识别 | LocalAuthentication | FaceID / TouchID
自动填充 | AuthenticationServices | iOS官方API
依赖管理 | Swift Package Manager (SPM) | 纯Swift包管理
测试 | XCTest + Quick/Nimble | 单元测试和UI测试

### 1.2 设计原则

- **安全优先**：敏感数据永远不暴露，内存安全，零知识
- **模块化**：清晰分层，职责单一
- **可测试性**：依赖注入，可mock
- **可维护性**：清晰的架构，良好的文档，清晰的代码规范
- **用户体验**：响应式UI，流畅动画，完美适配iOS设计准则

### 1.3 系统架构分层

```
┌─────────────────────────────────────────────────────────────┐
│                         Presentation Layer (UI) - 视图层 (SwiftUI
│  ・ View (Views & ViewModels
└────────────────────────────┬─────────────────────────────┘
┌────────────────────────────┴─────────────────────────────┐
│                      Business Logic Layer - 业务逻辑层
│  ・ Services - 业务服务
│  ・ UseCases - 用例/交互
└────────────────────────────┬─────────────────────────────┘
┌────────────────────────────┴─────────────────────────────┐
│                   Data Layer - 数据层
│  ・ Repositories - 数据仓库
│  ・ Models - 数据模型
│  ・ DataSources - 数据来源
└────────────────────────────┬─────────────────────────────┘
┌────────────────────────────┴─────────────────────────────┐
│              Security Layer - 安全层
│  ・ EncryptionService - 加密服务
│  ・ KeychainService - 密钥链服务
│  ・ SecureMemory - 安全内存
└─────────────────────────────────────────────────────────┘
```

---

## 2. 项目目录结构

### 2.1 主项目结构

```
VaultGo/
├── VaultGo/                      # 主应用
│   ├── App/                    # App入口
│   │   ├── VaultGoApp.swift
│   │   ├── AppAssembly.swift
│   │   └── AppEnvironment.swift
│   ├── Presentation/            # 视图层
│   │   ├── Views/
│   │   │   ├── PasswordVault/
│   │   │   ├── PasswordListView.swift
│   │   │   ├── PasswordDetailView.swift
│   │   │   ├── PasswordGenerator/
│   │   │   ├── Authentication/
│   │   │   ├── TwoFactorAuth/
│   │   │   ├── Settings/
│   │   │   └── Common/
│   │   ├── ViewModels/
│   │   │   ├── PasswordListViewModel.swift
│   │   │   ├── PasswordDetailViewModel.swift
│   │   │   ├── AuthViewModel.swift
│   │   │   ├── GeneratorViewModel.swift
│   │   │   └── SettingsViewModel.swift
│   │   ├── Router/
│   │   │   └── AppRouter.swift
│   ├── Domain/                # 业务逻辑层
│   │   ├── Services/
│   │   │   ├── PasswordVaultService.swift
│   │   │   ├── CryptoService.swift
│   │   │   ├── KeychainService.swift
│   │   │   ├── TwoFactorAuthService.swift
│   │   │   ├── AutoFillService.swift
│   │   │   ├── GeneratorService.swift
│   │   │   └── BackupService.swift
│   │   ├── UseCases/
│   │   │   ├── PasswordCRUDUseCase.swift
│   │   │   ├── AuthUseCase.swift
│   │   │   └── TwoFactorAuthUseCase.swift
│   │   └── Models/
│   │       ├── PasswordEntry.swift
│   │       ├── TwoFactorConfig.swift
│   │       └── Category.swift
│   ├── Data/                   # 数据层
│   │   ├── Repositories/
│   │   │   ├── PasswordRepository.swift
│   │   │   ├── TwoFactorRepository.swift
│   │   │   └── BackupRepository.swift
│   │   ├── DataSources/
│   │   │   ├── CoreData/
│   │   │   │   ├── CoreDataStack.swift
│   │   │   │   └── Models/
│   │   │   │       ├── CDPasswordEntry.swift
│   │   │   │       └── CDTwoFactorConfig.swift
│   │   │   └── Keychain/
│   │   └── Mappers/
│   │       ├── PasswordEntryMapper.swift
│   │       └── TwoFactorConfigMapper.swift
│   ├── Core/                   # 核心层
│   │   ├── Security/
│   │   │   ├── SecureMemory/
│   │   │   │   ├── SecureBuffer.swift
│   │   │   │   ├── EncryptionService.swift
│   │   │   │   ├── KeyDerivationService.swift
│   │   │   ├── CryptoKit/
│   │   │   │   ├── AES256GCM.swift
│   │   │   │   ├── PBKDF2.swift
│   │   │   │   └── HKDF.swift
│   │   │   └── Keychain/
│   │   │       ├── KeychainHelper.swift
│   │   │       └── KeychainQuery.swift
│   │   ├── Utils/
│   │   │   ├── Extensions/
│   │   │   ├── Constants.swift
│   │   │   └── Logger.swift
│   │   └── DI/
│   │       ├── Assembly.swift
│   │       └── DIContainer.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── AutoFillProvider/          # 自动填充扩展
│   ├── CredentialProviderViewController.swift
│   ├── AutoFillService.swift
│   ├── CredentialSelectionView.swift
│   └── AutoFillAssembly.swift
├── Shared/                  # 共享代码
│   ├── Models/
│   │   ├── SharedPasswordEntry.swift
│   │   └── AppGroupConstants.swift
│   ├── Services/
│   │   ├── KeychainAccess.swift
│   └── Utils/
└── VaultGoTests/              # 测试
    ├── UnitTests/
    │   ├── SecurityTests/
    │   ├── ServiceTests/
    │   └── ViewModelTests/
    └── UITests/
```

---

## 3. 详细技术设计

### 3.1 MVVM架构实现

#### 3.1.1 视图层

```swift
import SwiftUI
import Combine

class PasswordListViewModel: ObservableObject {
    @Published var entries: [PasswordEntry] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private let passwordService: PasswordVaultServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(passwordService: PasswordVaultServiceProtocol) {
        self.passwordService = passwordService
        self.setupBindings()
    }
    
    private func setupBindings() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main
            .sink { [weak self] query in
                self?.searchPasswords(query: query)
            }
            .store(in: &cancellables)
    }
    
    func loadPasswords() {
        isLoading = true
        Task {
            do {
                let entries = try await passwordService.fetchAll()
                await MainActor.run {
                    self.entries = entries
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func searchPasswords(query: String) {
        isLoading = true
        Task {
            do {
                let entries = try await passwordService.search(query: query)
                await MainActor.run {
                    self.entries = entries
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct PasswordListView: View {
    @StateObject var viewModel: PasswordListViewModel
    
    var body: some View {
        NavigationStack {
            List(viewModel.entries) { entry in
                PasswordEntryRow(entry: entry)
            }
            .searchable(text: $viewModel.searchQuery)
            .navigationTitle("密码库")
            .onAppear {
                viewModel.loadPasswords()
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("关闭") { viewModel.errorMessage = nil
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
```

### 3.2 依赖注入实现

```swift
protocol Assembly {
    static let shared = Assembly()
    
    var passwordService: PasswordVaultServiceProtocol {
        let cryptoService: CryptoServiceProtocol()
        let keychainService = KeychainService()
        let repository = PasswordRepository(
            coreDataSource: CoreDataSource(),
            cryptoService: cryptoService,
            keychainService: keychainService
        )
        return PasswordVaultService(repository: repository)
    }
    
    var twoFactorService: TwoFactorAuthServiceProtocol {
        let repository = TwoFactorRepository(
            coreDataSource: CoreDataSource(),
            cryptoService: cryptoService
        )
        return TwoFactorAuthService(repository: repository)
    }
    
    var encryptionService: EncryptionServiceProtocol {
        EncryptionService(
            keyDerivation: KeyDerivationService(),
            keychain: KeychainService()
        )
    }
}
```

---

## 4. 数据库设计

### 4.1 Core Data模型

#### 4.1.1 Core Data Entities

```swift
// CoreDataEntity(CDPasswordEntry.swift

import CoreData

@objc(CDPasswordEntry)
public class CDPasswordEntry: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPasswordEntry> {
        return NSFetchRequest<CDPasswordEntry>(entityName: "CDPasswordEntry")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var siteName: String
    @NSManaged public var siteURL: String?
    @NSManaged public var username: String
    @NSManaged public var encryptedPassword: Data
    @NSManaged public var encryptedNotes: Data?
    @NSManaged public var category: String
    @NSManaged public var tags: [String]?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var passwordStrengthRaw: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var lastUsedAt: Date?
    @NSManaged public var expiresAt: Date?
    @NSManaged public var icon: String?
    @NSManaged public var has2FA: Bool
    @NSManaged public var twoFactorConfigs: NSSet?
}
```

#### 4.1.2 数据迁移策略

```swift
import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()
    
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "VaultGo")
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data加载失败: \(error.localizedDescription)")
            }
            self.configureSQLCipherEncryption()
        }
        
        return container
    }()
    
    private func configureSQLCipherEncryption() {
        let description = container.persistentStoreDescriptions.first
        let fileManager = FileManager.default
        
        if let storeURL = description?.url {
            // 配置SQLCipher
            let options = [
                NSPersistentStoreFileProtectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            description?.setOption(true as NSNumber, forKey: NSPersistentStoreSQLitePragmasKey)
        }
    }
    
    var context: NSManagedObjectContext {
        container.viewContext
    }
    
    func save() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("保存CoreData保存失败: \(error.localizedDescription)")
            }
        }
    }
}
```

### 4.2 数据加密方案

```swift
class CoreDataSource {
    let coreDataStack: CoreDataStack
    let encryptionService: EncryptionServiceProtocol
    
    init(coreDataStack: CoreDataStack, encryptionService: EncryptionServiceProtocol) {
        self.coreDataStack = coreDataStack
        self.encryptionService = encryptionService
    }
    
    func savePasswordEntry(_ entry: PasswordEntry) throws {
        let cdEntry = CDPasswordEntry(context: coreDataStack.context)
        cdEntry.id = entry.id
        cdEntry.siteName = entry.siteName
        cdEntry.siteURL = entry.siteURL
        cdEntry.username = entry.username
        
        let encryptedPassword = try encryptionService.encrypt(entry.password.data(using: .utf8))
        cdEntry.encryptedPassword = encryptedPassword.combined
        
        if let notes = entry.notes {
            let encryptedNotes = try encryptionService.encrypt(notes.data(using: .utf8))
            cdEntry.encryptedNotes = encryptedNotes.combined
        }
        
        cdEntry.category = entry.category.rawValue
        cdEntry.tags = entry.tags
        cdEntry.isFavorite = entry.isFavorite
        cdEntry.passwordStrengthRaw = Int16(entry.passwordStrength.rawValue)
        cdEntry.createdAt = entry.createdAt
        cdEntry.updatedAt = entry.updatedAt
        cdEntry.lastUsedAt = entry.lastUsedAt
        cdEntry.expiresAt = entry.expiresAt
        cdEntry.icon = entry.icon
        cdEntry.has2FA = entry.has2FA
        
        coreDataStack.save()
    }
}
```

---

## 5. 安全架构实现

### 5.1 加密架构详解

```swift
import CryptoKit

class EncryptionService: EncryptionServiceProtocol {
    enum Error: Swift.Error {
        case invalidKeySize
        case invalidData
        case invalidNonce
        case authenticationFailed
    }
    
    private let keyDerivationService: KeyDerivationServiceProtocol
    
    init(keyDerivationService: KeyDerivationServiceProtocol) {
        self.keyDerivationService = keyDerivationService
    }
    
    func encrypt(_ data: Data, using symmetricKey: SymmetricKey) throws -> EncryptedData {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)
        
        return EncryptedData(
            ciphertext: sealedBox.ciphertext,
            nonce: sealedBox.nonce,
            tag: sealedBox.tag,
            version: "1.0"
        )
    }
    
    func decrypt(_ encryptedData: EncryptedData, using symmetricKey: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(
            nonce: encryptedData.nonce,
            ciphertext: encryptedData.ciphertext,
            tag: encryptedData.tag
        )
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
    
    func deriveKeys(from password: String, salt: Data) throws -> KeySet {
        let masterKey = try keyDerivationService.deriveMasterKey(from: password, salt: salt)
        let keys = try keyDerivationService.deriveSubKeys(from: masterKey)
        
        return keys
    }
}

struct EncryptedData: Codable {
    let ciphertext: Data
    let nonce: AES.GCM.Nonce
    let tag: Data
    let version: String
}
```

### 5.2 密钥管理

```swift
class KeyDerivationService: KeyDerivationServiceProtocol {
    static let pbkdf2Iterations = 600_000
    static let saltSize = 32
    
    func deriveMasterKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.precomposedStringWithCanonicalMapping.data(using: .utf8) else {
            throw CryptoError.invalidPassword
        }
        
        let masterKeyData = try PKCS5.PBKDF2
            .derive(from: passwordData,
                      salt: salt,
                      iterations: Self.pbkdf2Iterations,
                      keyByteCount: 32,
                      using: .sha256)
        
        return SymmetricKey(data: masterKeyData)
    }
    
    func deriveSubKeys(from masterKey: SymmetricKey) throws -> KeySet {
        let dataEncryptionKey = try masterKey.deriveSubKey(
            info: "VaultGo_DEK_Purpose_v1", 
            outputLength: 32
        )
        
        let keyEncryptionKey = try masterKey.deriveSubKey(
            info: "VaultGo_KEK_Purpose_v1", 
            outputLength: 32
        )
        
        let hmacKey = try masterKey.deriveSubKey(
            info: "VaultGo_HMAC_Purpose_v1", 
            outputLength: 32
        )
        
        return KeySet(
            dataEncryptionKey: dataEncryptionKey,
            keyEncryptionKey: keyEncryptionKey,
            hmacKey: hmacKey
        )
    }
}

extension SymmetricKey {
    func deriveSubKey(info: String, outputLength: Int) throws -> SymmetricKey {
        let salt = "VaultGo_HKDF_Salt_v1".data(using: .utf8)!
        let infoData = info.data(using: .utf8)!
        
        let hkdf = HKDF<SHA512>(
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
```

### 5.3 密钥链安全存储

```swift
class KeychainService: KeychainServiceProtocol {
    private let service = "com.vaultgo.app"
    private let accessGroup = "group.com.vaultgo.shared"
    
    func storeKey(_ key: Data, for identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key
        ]
        
        // 删除旧条目
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status: status)
        }
    }
    
    func retrieveKey(for identifier: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let keyData = result as? Data else {
            throw KeychainError.notFound
        }
        
        return keyData
    }
}

enum KeychainError: Error {
    case storeFailed(status: OSStatus)
    case notFound
}
```

### 5.4 Secure Memory

```swift
class SecureBuffer {
    private var bytes: UnsafeMutableRawBufferPointer
    private let count: Int
    private(set) var isDestroyed = false
    
    init(count: Int) {
        self.count = count
        let pageSize = Int(getpagesize())
        let alignedCount = ((count + pageSize - 1) / pageSize * pageSize
        
        bytes = UnsafeMutableRawBufferPointer.allocate(
            byteCount: alignedCount,
            alignment: pageSize
        )
        
        mlock(bytes.baseAddress!, bytes.count)
        
        // 前后保护页
        if let base = bytes.baseAddress {
            mprotect(base, pageSize, PROT_NONE)
            mprotect(base + alignedCount - pageSize, pageSize, PROT_NONE)
        }
    }
    
    func write(_ data: Data, offset: Int = 0) {
        guard !isDestroyed else { return }
        data.withUnsafeBytes { src in
            bytes.baseAddress!.advanced(by: offset)
                .copyMemory(from: src.baseAddress!, byteCount: Swift.min(src.count, count - offset))
        }
    }
    
    func read(offset: Int = 0, length: Int? = nil) -> Data {
        guard !isDestroyed else { return Data() }
        let len = length ?? count - offset
        return Data(bytes: bytes.baseAddress!.advanced(by: offset), count: len)
    }
    
    func destroy() {
        guard !isDestroyed else { return }
        
        let patterns: [UInt8] = [0x00, 0xFF, 0xAA, 0x55, 0x00]
        for pattern in patterns {
            memset_pattern(bytes.baseAddress!, &pattern, 1, count)
            __asm__ __volatile__("" ::: "memory")
        }
        
        munlock(bytes.baseAddress!, bytes.count)
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

---

## 6. 自动填充架构

### 6.1 Credential Provider Extension

```swift
import AuthenticationServices

class CredentialProviderViewController: ASCredentialProviderViewController {
    
    private let assembly = AutoFillAssembly()
    
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        Task { @MainActor in
            let entries = try await assembly.passwordService.fetchMatching(
                for: serviceIdentifiers
            )
            let view = CredentialSelectionView(entries: entries)
            let host = UIHostingController(rootView: view)
            addChild(host)
            view.frame = view.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
        }
    }
    
    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: ASCredentialRequest
    ) {
        // 快速提供凭证（需要快速填充）
    }
    
    override func prepareInterfaceForExtensionConfiguration() {
        // 扩展配置界面
    }
    
    func userSelected(_ credential: ASPasswordCredential) {
        self.extensionContext.completeRequest(returning: credential)
    }
}
```

### 6.2 App Groups数据共享

```swift
// 共享密钥链配置
// 在两个Target的Info.plist配置：
//
//    App Groups:
//      - NSExtensionFileProviderDocumentBrowserViewController
//      - "com.vaultgo.shared"
//

// SharedConstants.swift
class AppGroupConstants {
    static let appGroupIdentifier = "group.com.vaultgo.shared"
    static let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
}
```

---

## 7. 测试策略

### 7.1 单元测试

```swift
import XCTest
import CryptoKit
@testable import VaultGo

final class EncryptionServiceTests: XCTestCase {
    var sut: EncryptionService!
    
    override func setUp() {
        super.setUp()
        let keyDerivation = KeyDerivationService()
        sut = EncryptionService(keyDerivationService: keyDerivation)
    }
    
    func testEncryptionDecryption() throws {
        let testData = "这是要加密的测试数据".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)
        
        let encrypted = try sut.encrypt(testData, using: key)
        let decrypted = try sut.decrypt(encrypted, using: key)
        
        XCTAssertEqual(testData, decrypted)
    }
    
    func testWrongKeyShouldFail() throws {
        let testData = "数据".data(using: .utf8)!
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        
        let encrypted = try sut.encrypt(testData, using: key1)
        
        XCTAssertThrowsError(try sut.decrypt(encrypted, using: key2))
    }
}
```

### 7.2 UI测试

```swift
import XCTest
@testable import VaultGo

class PasswordListViewUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }
    
    func testAddPassword() {
        app.navigationBars["密码库"].buttons["添加"].tap()
        
        let siteField = app.textFields["网站名"]
        siteField.tap()
        siteField.typeText("测试网站")
        
        let userField = app.textFields["用户名"]
        userField.tap()
        userField.typeText("test@test.com")
        
        let pwdField = app.secureTextFields["密码"]
        pwdField.tap()
        pwdField.typeText("StrongPassword123!")
        
        app.buttons["保存"].tap()
        
        XCTAssert(app.staticTexts["测试网站"].exists)
    }
}
```

---

## 8. 性能优化

### 8.1 启动优化

- 延迟加载大型密码列表
- 分页加载密码条目
- 后台索引搜索优化
- 预加载最近使用密码
- 图片缓存

### 8.2 内存管理

- 敏感数据及时清除
- 对象池复用
- 图片异步加载
- 自动释放池管理

---

## 9. 版本兼容性

### 9.1 iOS 版本支持

- iOS 15.0 及以上
- iPhone 6s 及以上
- iPad 及 iPad Pro

### 9.2 屏幕适配

- Auto Layout + Size Classes
- Dynamic Type 支持
- 暗黑模式支持
- VoiceOver 完整支持

---

## 10. CI/CD 部署

### 10.1 持续集成配置

```yaml
# .gitlab-ci.yml 示例
stages:
  - build
  - test
  - archive

build:
  stage: build
  image: macos-latest
  script:
    - xcodebuild -scheme VaultGo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build-for-testing

test:
  stage: test
  image: macos-latest
  script:
    - xcodebuild -scheme VaultGo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' test
```

---

## 附录 A. 关键技术决策记录

| 决策 | 选项 | 选择 | 理由
---|---|---|---
加密算法 | CommonCrypto vs CryptoKit | CryptoKit | 官方推荐，硬件加速
数据持久化 | Realm vs CoreData vs SQLite | CoreData + SQLiteCipher | 系统原生，SQLCipher加密
架构模式 | MVC vs MVVM vs VIPER | MVVM + Clean Arch | 适合SwiftUI，可测试性高
依赖管理 | Cocoapods vs Carthage vs SPM | SPM | 纯Swift，苹果官方支持

---

## 变更记录

| 版本 | 日期 | 变更 | 作者
---|---|---|---
1.0 | 2026-06-03 | 初始版本 | 技术团队
