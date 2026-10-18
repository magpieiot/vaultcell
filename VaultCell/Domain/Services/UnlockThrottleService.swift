/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// UnlockThrottleService.swift
/// created on: 18/10/2026
/// ------------------------------------------------------------------

import Foundation

// MARK: - 持久化状态

/// 解锁失败限流状态
struct UnlockThrottleState: Codable, Equatable {
    /// 连续失败次数（成功后归零，超过衰减窗口也归零）
    var failureCount: Int = 0
    /// 最后一次失败的时间，用于衰减窗口判定
    var lastFailureAt: Date?
    /// 冷却结束时间
    var cooldownUntil: Date?
}

/// 限流状态的存储
protocol UnlockThrottleStore {
    func load() -> UnlockThrottleState?
    /// 保存状态；传 nil 表示清除记录
    func save(_ state: UnlockThrottleState?)
}

/// 冷却期内的解锁尝试：在 PBKDF2 派生之前被拦下
struct UnlockThrottledError: Error {}

// MARK: - 限流服务

/// 主密码解锁失败限流：连续失败后按阶梯退避，冷却期内直接挡在密钥派生之前
///
/// 防的是 A 类威胁——拿到已开机但未解锁的手机、靠反复试密码猜主密码。
/// 对 B 类（物理取证后离线爆破）无效：那时本计数器形同虚设，只能靠 KDF 成本与主密码强度，
/// 因此这里不为"防篡改计数器"引入额外复杂度。
///
/// 时钟与存储均可注入，便于脱离 Keychain / UIKit 做单元测试。
struct UnlockThrottleService {
    /// 免罚次数：正常用户偶尔输错不该被惩罚
    static let graceFailures = 4
    /// 衰减窗口：距上次失败超过该时长，视为新的一轮（避免"很久以前输错几次"累积惩罚）
    static let decayWindow: TimeInterval = 24 * 60 * 60
    /// 退避阶梯（秒）：第 5 次起依次取值，超出范围取最后一档
    static let backoffSteps: [TimeInterval] = [30, 60, 120, 300, 900, 1800]

    private let store: UnlockThrottleStore
    private let now: () -> Date
    private var state: UnlockThrottleState

    init(store: UnlockThrottleStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        self.state = Self.decayed(store.load() ?? UnlockThrottleState(), now: now())
    }

    /// 冷却剩余秒数，> 0 表示界面应冻结输入
    var remainingCooldown: TimeInterval {
        guard let until = state.cooldownUntil else { return 0 }
        return max(0, until.timeIntervalSince(now()))
    }

    /// 记录一次失败，返回本次新增的冷却时长（0 表示尚未进入冷却）
    @discardableResult
    mutating func recordFailure() -> TimeInterval {
        var state = Self.decayed(self.state, now: now())
        state.failureCount += 1
        state.lastFailureAt = now()

        let step = state.failureCount - Self.graceFailures - 1
        guard step >= 0 else {
            self.state = state
            store.save(state)
            return 0
        }

        let delay = Self.backoffSteps[min(step, Self.backoffSteps.count - 1)]
        state.cooldownUntil = now().addingTimeInterval(delay)
        self.state = state
        store.save(state)
        return delay
    }

    /// 证明身份成功（密码解锁 / 生物识别 / 二次验证通过）后清零计数与冷却
    mutating func recordSuccess() {
        state = UnlockThrottleState()
        store.save(nil)
    }

    /// 距上次失败已超过衰减窗口时视为新的一轮
    private static func decayed(_ state: UnlockThrottleState, now: Date) -> UnlockThrottleState {
        guard let last = state.lastFailureAt, now.timeIntervalSince(last) > decayWindow else { return state }
        return UnlockThrottleState()
    }
}
