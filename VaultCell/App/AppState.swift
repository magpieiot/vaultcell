/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
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
    
    /// 应用目录，启动时从 bundle 的统一目录 JSON 加载到内存
    @Published var apps: [AppCatalogEntry] = []

    /// 是否需要显示快照保护遮罩
    ///
    /// App 进入非活跃状态时置为 `true`，在界面上覆盖半透明遮罩，
    /// 防止系统截取的后台快照暴露敏感信息；回到活跃状态时置为 `false`。
    @Published var shouldShowPrivacyOverlay: Bool = false

    /// 解锁冷却剩余秒数（> 0 表示界面应冻结输入）
    ///
    /// 平行于 `isLocked`：冻结的是"试密码"这件事，不是保险库的锁定状态，
    /// 因此不会触发 `clearSensitiveData()`。由冷却计时器每秒刷新。
    @Published var unlockCooldownRemaining: TimeInterval = 0

    // MARK: - 私有服务依赖

    /// 主密码解锁失败限流：连续输错后的阶梯退避
    private var unlockThrottle: UnlockThrottleService

    /// 冷却倒计时的驱动任务
    private var cooldownTicker: Task<Void, Never>?
    
    /// 保险库锁定服务，负责加密/解密和锁定相关操作
    private let lockService: AppLockService
    
    /// 钥匙串服务，用于安全存储敏感凭据
    private let keychainService: KeychainServiceProtocol
    
    /// 应用目录服务，负责从 bundle 加载应用元数据
    private let appCatalogService: AppCatalogServiceProtocol

    /// 是否正在进行生物识别验证
    ///
    /// Face ID / Touch ID 系统弹窗会使 App 进入 `.inactive` 状态，
    /// 此标志位用于在该期间跳过快照保护遮罩，避免遮罩遮挡验证弹窗。
    private var isPerformingBiometricAuth: Bool = false
    
    // MARK: - 初始化
    
    /// 初始化应用状态
    /// - Parameters:
    ///   - lockService: 锁定服务实例，默认为 AppLockService()
    ///   - keychainService: 钥匙串服务实例，默认为 KeychainService()
    ///   - appCatalogService: 应用目录服务实例，默认为 AppCatalogService()
    init(
        lockService: AppLockService = AppLockService(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        appCatalogService: AppCatalogServiceProtocol = AppCatalogService()
    ) {
        self.lockService = lockService
        self.keychainService = keychainService
        self.appCatalogService = appCatalogService
        self.unlockThrottle = UnlockThrottleService(
            store: KeychainUnlockThrottleStore(keychain: keychainService)
        )

        // 恢复上次遗留的冷却：杀掉进程不该绕过限流
        unlockCooldownRemaining = unlockThrottle.remainingCooldown
        startCooldownTicker()

        // 启动时检查是否存在已有保险库
        checkExistingVault()
        // 订阅密码条目变更，驱动 AutoFill 凭据身份同步（自动填充建议的前置条件）
        AutoFillIdentityService.shared.startObservingChanges()
        // 异步加载应用目录到内存
        loadAppCatalog()
        // 图标抓取的启动准备：清 v2 旧缓存 + 首启按 App Store 地区落盘开关默认值（幂等）
        Task { await IconPreferences.prepareOnLaunch() }
    }
    
    // MARK: - 计算属性
    
    /// 是否已存在保险库（已设置主密码）
    var hasExistingVault: Bool {
        lockService.hasExistingVault()
    }
    
    // MARK: - 公开方法 - 认证
    
    /// 标记用户已认证成功，解除锁定状态
    func authenticate() {
        isAuthenticated = true
        isLocked = false
        lastActiveTime = Date()
        // 解锁后刷新系统侧的自动填充身份
        synchronizeAutoFillIdentities()
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
        // 限流闸门：冷却期内直接挡下，不再白烧一次 PBKDF2
        try throwIfUnlockThrottled()

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
                        self.noteUnlockSucceeded()
                        continuation.resume()
                    }
                } catch {
                    // 回到主线程抛出错误
                    DispatchQueue.main.async { @MainActor in
                        self.noteUnlockFailed()
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
        // 与解锁共用同一道闸门：否则二次验证界面就是一条免费的重试通道
        try throwIfUnlockThrottled()

        let lockService = self.lockService

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try lockService.unlockVault(with: masterPassword)
                    DispatchQueue.main.async { @MainActor in
                        self.noteUnlockSucceeded()
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async { @MainActor in
                        self.noteUnlockFailed()
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
        // 冷却期内同样不放行：否则冻住主密码输入后仍可改走生物识别
        try throwIfUnlockThrottled()

        // 检查生物识别是否可用
        guard BiometricService.shared.isBiometricAvailable else {
            throw NSError(domain: "VaultCell", code: -1, userInfo: [NSLocalizedDescriptionKey: "Biometric authentication unavailable"])
        }

        // 标记生物识别验证开始，期间系统弹窗触发 .inactive 时不显示快照遮罩。
        // 不在此处用 defer 清除——keychainService.retrieveKey 是同步阻塞调用，
        // FaceID 弹窗期间的 .inactive 通知在调用返回后才被 RunLoop 处理，
        // 若提前清除标志位会导致排队的 .inactive 回调误触发遮罩。
        // 标志位在 handleAppBecameActive() 中清除。
        isPerformingBiometricAuth = true

        // 调用锁定服务进行生物识别验证
        // 失败不计入限流：Face ID 的尝试次数由系统自己管着，重复计数只会误伤
        try lockService.unlockWithBiometrics()

        // 更新状态并上报登录事件
        authenticate()
        noteUnlockSucceeded()
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
    
    // MARK: - 解锁限流（防暴力破解）

    /// 冷却期内的统一拦截点：三条校验链（密码解锁 / 二次验证 / 生物识别）都先过这道闸
    private func throwIfUnlockThrottled() throws {
        guard unlockThrottle.remainingCooldown <= 0 else { throw UnlockThrottledError() }
    }

    /// 证明身份成功：清零失败计数与冷却
    private func noteUnlockSucceeded() {
        unlockThrottle.recordSuccess()
        stopCooldownTicker()
        unlockCooldownRemaining = 0
    }

    /// 记录一次失败，并进入（或延长）冷却
    private func noteUnlockFailed() {
        unlockCooldownRemaining = unlockThrottle.recordFailure()
        startCooldownTicker()
    }

    /// 每秒刷新 `unlockCooldownRemaining`，让界面上的倒计时自己走完
    private func startCooldownTicker() {
        guard unlockCooldownRemaining > 0, cooldownTicker == nil else { return }
        cooldownTicker = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let remaining = self.unlockThrottle.remainingCooldown
                self.unlockCooldownRemaining = remaining
                if remaining <= 0 { break }
            }
            self?.stopCooldownTicker()
        }
    }

    private func stopCooldownTicker() {
        cooldownTicker?.cancel()
        cooldownTicker = nil
    }
    
    // MARK: - 公开方法 - 应用生命周期
    
    /// 是否正处于后台，用于区分"从后台恢复"与"应用内短暂非活跃"
    private var isInBackground = false
    
    /// 应用从后台恢复激活时的处理
    ///
    /// 检查是否需要自动锁定（根据超时间隔判断）。
    func handleAppBecameActive() {
        isInBackground = false
        shouldShowPrivacyOverlay = false
        // 清除生物识别验证标志位——FaceID 弹窗引发的 .inactive → .active
        // 场景切换在此时完成，后续的 .inactive 可正常触发快照遮罩
        isPerformingBiometricAuth = false
        checkAutoLock()
        // 后台期间时钟照走，回到前台按当前时间重算冷却
        unlockCooldownRemaining = unlockThrottle.remainingCooldown
        startCooldownTicker()
        consumeAutoFillSavePing()
        // 兜底同步：系统可能在重装、恢复备份或用户切换自动填充开关后清空 identity
        if isAuthenticated && !isLocked {
            synchronizeAutoFillIdentities()
        }
    }

    /// 消费「AutoFill 扩展保存过密码」的标记。
    ///
    /// 扩展在 Safari / App 的登录流程里保存密码时直接写共享数据库，主 App 的
    /// 列表不会自动感知；这里在回到前台时比对 App Group 里的时间戳，发现新写入
    /// 就广播一次变更（列表重载 + 身份同步）。未解锁时同样要广播列表重载，
    /// 否则用户解锁后看到的仍是旧列表。
    private func consumeAutoFillSavePing() {
        let defaults = UserDefaults.standard
        let shared = UserDefaults(suiteName: Self.appGroupIdentifier)
        let savedAt = shared?.double(forKey: AutoFillSharedKeys.savedCredentialAt) ?? 0
        let consumedAt = defaults.double(forKey: VaultKey.consumedAutoFillSaveAt)

        guard savedAt > consumedAt else { return }
        defaults.set(savedAt, forKey: VaultKey.consumedAutoFillSaveAt)
        NSLog("AutoFill: 检测到扩展保存的新密码，刷新列表与身份同步")
        NotificationCenter.default.post(name: .autoFillDidSaveCredential, object: nil)
        NotificationCenter.default.post(name: .passwordEntriesDidChange, object: nil)
    }

    /// 当前构建变体对应的 App Group（与扩展侧 AutoFillCredentialStore 保持一致）
    private static var appGroupIdentifier: String {
        #if CN
        return "group.com.magpie.vaultcell.cn.shared"
        #else
        return "group.com.magpie.vaultcell.shared"
        #endif
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
        // 生物识别验证期间不显示遮罩；仅在已认证且未锁定时覆盖敏感界面
        guard !isPerformingBiometricAuth, isAuthenticated, !isLocked else { return }
        shouldShowPrivacyOverlay = true
    }
    
    /// 应用进入后台时的处理
    ///
    /// 记录当前时间作为最后一次活动时间。
    func handleAppEnteredBackground() {
        isInBackground = true
        lastActiveTime = Date()
    }
    
    // MARK: - 私有方法

    /// 触发一次自动填充身份全量同步（幂等；失败由服务内部记录日志，不影响主流程）
    private func synchronizeAutoFillIdentities() {
        NSLog("AutoFill: 触发身份同步（已认证=%@ 未锁定=%@）",
              isAuthenticated ? "Y" : "N",
              isLocked ? "N" : "Y")
        Task {
            await AutoFillIdentityService.shared.synchronize()
        }
    }
    
    /// 检查是否已存在保险库
    ///
    /// 如果已有保险库，设置为未认证状态并保持最新锁定状态；
    /// 否则提示需要创建新保险库。
    private func checkExistingVault() {
        isAuthenticated = false
        isLocked = !hasExistingVault
    }
    
    /// 异步加载应用目录到内存
    ///
    /// 启动时从 bundle 的统一目录读取应用元数据，供标题联想使用。
    private func loadAppCatalog() {
        Task {
            let loadedApps = await appCatalogService.loadApps()
            await MainActor.run {
                self.apps = loadedApps
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
