/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AutoFillSharedKeys.swift
/// ------------------------------------------------------------------
///
/// 主 App 与 AutoFill 扩展通过 App Group 共享的 UserDefaults 键名。
///
/// 扩展是独立进程，读不到主 App 的 `UserDefaults.standard`；两侧各写一份
/// 字符串常量迟早漂移（一边写一边读错键 = 静默失效），因此集中在这里，
/// 由两个 target 共同编译（见 project.yml 的 sources）。

import Foundation

enum AutoFillSharedKeys {
    /// 扩展保存密码后写入的时间戳（`TimeInterval`）。
    /// 主 App 回到前台时比对并刷新列表；用时间戳而非布尔值，
    /// 避免"扩展写了但主 App 恰好没读到"时被下一次读取覆盖掉。
    static let savedCredentialAt = "vaultcell.autoFillSavedAt"
}
