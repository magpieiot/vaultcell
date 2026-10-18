/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// KeychainUnlockThrottleStore.swift
/// created on: 18/10/2026
/// ------------------------------------------------------------------

import Foundation

/// 限流状态的 Keychain 持久化
///
/// 复用 `KeychainService.store(_:for:)` 的 `WhenUnlockedThisDeviceOnly`：不进备份、不跨设备同步。
/// 不叠加生物识别 access control——否则每记一次失败都要弹认证。
/// 设备锁定期间读不到时按"从未失败"处理：宁可放行，也不误伤正常用户。
final class KeychainUnlockThrottleStore: UnlockThrottleStore {
    private let keychain: KeychainServiceProtocol

    init(keychain: KeychainServiceProtocol = KeychainService()) {
        self.keychain = keychain
    }

    func load() -> UnlockThrottleState? {
        try? keychain.retrieve(UnlockThrottleState.self, for: VaultKey.unlockThrottle)
    }

    func save(_ state: UnlockThrottleState?) {
        guard let state else {
            try? keychain.deleteKey(for: VaultKey.unlockThrottle)
            return
        }
        try? keychain.store(state, for: VaultKey.unlockThrottle)
    }
}
