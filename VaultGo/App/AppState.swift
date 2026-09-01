/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// AppState.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import Combine
import UIKit

/// 应用全局状态管理类
/// 负责管理认证状态、锁定状态、保险库的创建/解锁/锁定等核心业务逻辑，
/// 以及应用前后台切换时的自动锁定检测。
@MainActor
class AppState: ObservableObject {
    
    // MARK: - 公开属性（发布给UI订阅）
    
    /// 当前用户是否已通过认证（登录成功）
    @Published var isAuthenticated: Bool = false
    
    /// 当前保险库是否处于锁定状态，默认锁定
    @Published var isLocked: Bool = true
    
    /// 最后一次用户活动的时间，用于自动锁定超时计算
    @Published var lastActiveTime: Date?
    
    /// 当前用户唯一标识，首次启动时生成并持久化
    @Published var userID: String?
    
    /// 应用目录，启动时从 bundle 的 JSON 文件加载到内存
    @Published var apps: [AppInfo] = []
    
    // MARK: - 私有服务依赖
    
    /// 保险库锁定服务，负责加密/解密和锁定相关操作
    private let lockService: AppLockService
    
    /// 钥匙串服务，用于安全存储敏感凭据
    private let keychainService: KeychainServiceProtocol
    
    /// CloudKit 登录上报服务，用于记录登录时间、设备及系统信息
    private let cloudKitLoginService: CloudKitLoginServiceProtocol
    
    /// 应用目录服务，负责从 bundle 加载应用元数据
    private let appCatalogService: AppCatalogServiceProtocol
    
    // MARK: - 初始化
    
    /// 初始化应用状态
    /// - Parameters:
    ///   - lockService: 锁定服务实例，默认为 AppLockService()
    ///   - keychainService: 钥匙串服务实例，默认为 KeychainService()
    ///   - cloudKitLoginService: CloudKit 登录上报服务实例，默认为 CloudKitLoginService()
    ///   - appCatalogService: 应用目录服务实例，默认为 AppCatalogService()
    init(
        lockService: AppLockService = AppLockService(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        cloudKitLoginService: CloudKitLoginServiceProtocol = CloudKitLoginService(),
        appCatalogService: AppCatalogServiceProtocol = AppCatalogService()
    ) {
        self.lockService = lockService
        self.keychainService = keychainService
        self.cloudKitLoginService = cloudKitLoginService
        self.appCatalogService = appCatalogService
        
        // 启动时检查是否存在已有保险库
        checkExistingVault()
        // 确保首次启动时已生成用户唯一标识
        ensureUserID()
        // 异步加载应用目录到内存
        loadAppCatalog()
    }
    
    // MARK: - 计算属性
    
    /// 是否已存在保险库（已设置主密码）
    var hasExistingVault: Bool {
        lockService.hasExistingVault()
    }
    
    // MARK: - 公开方法 - 认证
    
    /// 标记用户已认证成功，解除锁定状态，并向 CloudKit 上报登录事件
    func authenticate() {
        isAuthenticated = true
        isLocked = false
        lastActiveTime = Date()
        
        // 异步上报登录信息；失败不影响登录流程
        Task {
            let event = LoginEvent(
                timestamp: Date(),
                iosVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.modelName,
                userID: UserDefaults.userID
            )
            await cloudKitLoginService.reportLogin(event: event)
        }
    }
    
    // MARK: - 公开方法 - 保险库操作
    
    /// 使用主密码创建新的保险库
    ///
    /// 在主线程外执行加密操作，避免阻塞UI。
    /// 创建成功后自动将状态设置为已认证且已解锁。
    ///
    /// - Parameter masterPassword: 用户设置的主密码
    func createVault(with masterPassword: String) async throws {
        let lockService = self.lockService
        print("@@@DEBUG: Appstate.createVault")
        
        // 使用 continuation 将同步回调封装为 async/await 风格
        try await withCheckedThrowingContinuation { continuation in
            // 在后台线程执行耗时的加密和创建操作
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try lockService.createVault(with: masterPassword)
                    // 回到主线程更新UI状态并上报登录事件
                    DispatchQueue.main.async { @MainActor in
                        self.authenticate()
                        continuation.resume()
                        print("@@@DEBUG: Appstate.createVault success")
                    }
                } catch {
                    // 回到主线程抛出错误
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                        print("@@@DEBUG: Appstate.createVault error: \(error)")
                    }
                }
            }

        }
    }
    
    /// 使用主密码解锁保险库
    ///
    /// 在主线程外执行解密验证操作，避免阻塞UI。
    /// 解锁成功后自动将状态设置为已认证且已解锁。
    ///
    /// - Parameter masterPassword: 用户输入的主密码
    func unlockVault(with masterPassword: String) async throws {
        let lockService = self.lockService
        
        // 使用 continuation 将同步回调封装为 async/await 风格
        try await withCheckedThrowingContinuation { continuation in
            // 在后台线程执行耗时的解密验证操作
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try lockService.unlockVault(with: masterPassword)
                    // 回到主线程更新UI状态并上报登录事件
                    DispatchQueue.main.async { @MainActor in
                        self.authenticate()
                        continuation.resume()
                    }
                } catch {
                    // 回到主线程抛出错误
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// 仅验证主密码是否正确，不改变认证状态
    ///
    /// 用于需要确认身份的破坏性操作（如重置保险库）。
    /// 验证成功仅返回，不会调用 `authenticate()` 改变解锁状态。
    ///
    /// - Parameter masterPassword: 用户输入的主密码
    /// - Throws: 主密码错误或解密失败时抛出对应错误
    func verifyMasterPassword(_ masterPassword: String) async throws {
        let lockService = self.lockService

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try lockService.unlockVault(with: masterPassword)
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// 使用生物识别（Face ID / Touch ID）解锁保险库
    ///
    /// 首先检查设备是否支持生物识别，然后调用锁定服务进行验证。
    ///
    /// - Throws: 如果生物识别不可用或验证失败，抛出对应错误
    func unlockWithBiometrics() async throws {
        // 检查生物识别是否可用
        guard BiometricService.shared.isBiometricAvailable else {
            throw NSError(domain: "VaultGo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Biometric authentication unavailable"])
        }

        // 调用锁定服务进行生物识别验证
        try lockService.unlockWithBiometrics()

        // 更新状态并上报登录事件
        authenticate()
    }
    
    // MARK: - 公开方法 - 锁定与注销
    
    /// 锁定保险库
    ///
    /// 记录锁定时间并清除敏感数据（剪贴板内容、加密密钥等）。
    func lock() {
        lastActiveTime = Date()
        isLocked = true
        clearSensitiveData()
    }
    
    /// 注销当前用户
    ///
    /// 重置认证状态为未登录，并清除敏感数据。
    func logout() {
        isAuthenticated = false
        isLocked = true
        clearSensitiveData()
    }
    
    // MARK: - 公开方法 - 应用生命周期
    
    /// 是否正处于后台，用于区分"从后台恢复"与"应用内短暂非活跃"
    private var isInBackground = false
    
    /// 应用从后台恢复激活时的处理
    ///
    /// 检查是否需要自动锁定（根据超时间隔判断）。
    func handleAppBecameActive() {
        isInBackground = false
        checkAutoLock()
    }
    
    /// 应用即将进入非活跃状态时的处理
    ///
    /// 记录当前时间作为最后一次活动时间。
    /// 注意：从后台恢复时系统也会先经过 .inactive，此时不能重置
    /// "最后活动时间"，否则 checkAutoLock 计算出的时间差恒为 0，
    /// 自动锁定将永远无法触发。
    func handleAppBecameInactive() {
        guard !isInBackground else { return }
        lastActiveTime = Date()
    }
    
    /// 应用进入后台时的处理
    ///
    /// 记录当前时间作为最后一次活动时间。
    func handleAppEnteredBackground() {
        isInBackground = true
        lastActiveTime = Date()
    }
    
    // MARK: - 私有方法
    
    /// 检查是否已存在保险库
    ///
    /// 如果已有保险库，设置为未认证状态并保持最新锁定状态；
    /// 否则提示需要创建新保险库。
    private func checkExistingVault() {
        isAuthenticated = false
        isLocked = !hasExistingVault
    }
    
    /// 确保用户唯一标识已生成并持久化
    ///
    /// 首次启动时 UserDefaults 中不存在 userID，则生成新的 UUID 并保存；
    /// 后续启动直接读取已有值。
    private func ensureUserID() {
        if let existingID = UserDefaults.userID, !existingID.isEmpty {
            userID = existingID
        } else {
            let newID = UUID().uuidString
            UserDefaults.userID = newID
            userID = newID
        }
    }
    
    /// 异步加载应用目录到内存
    ///
    /// 启动时从 bundle 的 JSON 文件读取应用元数据，加载失败仅打印日志。
    private func loadAppCatalog() {
        Task {
            do {
                let loadedApps = try await appCatalogService.loadApps()
                await MainActor.run {
                    self.apps = loadedApps
                }
            } catch {
                print("Failed to load app catalog: \(error)")
            }
        }
    }
    
    /// 检查是否需要自动锁定
    ///
    /// 根据 "最后活动时间" 与 "用户设置的自动锁定间隔" 判断是否需要执行自动锁定。
    /// 如果超出设定间隔，则自动锁定保险库；间隔为 0 表示永不自动锁定。
    private func checkAutoLock() {
        guard let lastActive = lastActiveTime else {
            return
        }
        
        // 获取用户设置的自动锁定时间间隔
        let autoLockInterval = UserDefaults.autoLockInterval
        
        // 间隔为 0 表示永不自动锁定
        guard autoLockInterval > 0 else {
            return
        }
        
        // 计算自上次活动以来的时间差
        let elapsed = Date().timeIntervalSince(lastActive)
        
        // 超时则自动锁定
        if elapsed > autoLockInterval {
            lock()
        }
    }
    
    /// 清除敏感数据
    ///
    /// 清除系统剪贴板内容，并移除内存中的加密密钥，
    /// 确保锁定后敏感信息不会残留在内存或剪贴板中。
    private func clearSensitiveData() {
        // 清空系统剪贴板
        UIPasteboard.general.items = []
        // 清除内存中的加密密钥
        EncryptionService.shared.clearEncryptionKey()
    }
}
