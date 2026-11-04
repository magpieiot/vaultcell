/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// NetworkReachability.swift
/// ------------------------------------------------------------------
///
/// 一次性网络可达性判断。
///
/// 使用场景很窄：点击「隐私政策 / 服务条款」这类要在系统浏览器打开的外链之前，
/// 先判断当前是否在线，离线时由 App 给出提示——而不是把用户丢到 Safari 的错误页。
///
/// 刻意不复用 `NWPathMonitor` 长驻实例：这里只需要一次瞬时结果，
/// 长驻监听会带来额外线程与状态同步成本。
///
/// 超时兜底：`NWPathMonitor` 通常几十毫秒内给出首次路径更新；
/// 若 0.5s 内仍无回调（系统异常等情况），按「在线」处理并放行，
/// 宁可交给浏览器，也不要误报离线把用户挡住。
/// ------------------------------------------------------------------

import Foundation
import Network

enum NetworkReachability {

    /// 当前是否有可用网络。返回 `true` 表示可以尝试打开外链。
    static func isOnline(timeout: DispatchTimeInterval = .milliseconds(500)) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.magpie.vaultcell.reachability")
            let once = SingleResume()

            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: true)
            }
        }
    }
}

/// 保证 continuation 只被 resume 一次（路径回调与超时回调存在竞争）
private final class SingleResume: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
