/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// UnlockThrottleServiceTests.swift
/// 覆盖解锁失败限流的退避阶梯、冷却窗口与持久化，防止"杀进程即可绕过"这类漏网之鱼。
/// ------------------------------------------------------------------

import Testing
import Foundation

/// 内存版存储：测试不碰 Keychain（测试 target 无 host app，读写 Keychain 会失败）
private final class MemoryThrottleStore: UnlockThrottleStore {
    var state: UnlockThrottleState?

    func load() -> UnlockThrottleState? { state }

    func save(_ state: UnlockThrottleState?) { self.state = state }
}

/// 可推进的时钟：限流完全由"当前时间"驱动，测试必须能控制它
private final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

@Suite("UnlockThrottleService")
struct UnlockThrottleServiceTests {

    private func makeService(store: MemoryThrottleStore, clock: TestClock) -> UnlockThrottleService {
        UnlockThrottleService(store: store, now: { clock.now })
    }

    /// 先消耗掉免罚次数，回到"下一次失败就要进冷却"的起点
    private func exhaustGraceFailures(_ service: inout UnlockThrottleService) {
        for _ in 0..<UnlockThrottleService.graceFailures { service.recordFailure() }
    }

    @Test("免罚次数内不进入冷却")
    func graceFailuresAreFree() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var service = makeService(store: store, clock: clock)

        for _ in 0..<UnlockThrottleService.graceFailures {
            #expect(service.recordFailure() == 0, "免罚次数内不该产生冷却")
            #expect(service.remainingCooldown == 0)
        }
    }

    @Test("第 5 次起按退避阶梯逐级延长")
    func backoffEscalatesBySteps() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var service = makeService(store: store, clock: clock)
        exhaustGraceFailures(&service)

        for (index, step) in UnlockThrottleService.backoffSteps.enumerated() {
            #expect(service.recordFailure() == step, "第 \(UnlockThrottleService.graceFailures + index + 1) 次失败应冷却 \(step)s")
        }
    }

    @Test("超出阶梯上限后维持最长冷却")
    func cooldownCapsAtLastStep() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var service = makeService(store: store, clock: clock)
        exhaustGraceFailures(&service)

        for _ in 0..<(UnlockThrottleService.backoffSteps.count + 3) { service.recordFailure() }

        let longest = UnlockThrottleService.backoffSteps.last ?? 0
        #expect(service.recordFailure() == longest, "退避应封顶在最后一档 \(longest)s")
        #expect(service.remainingCooldown == longest)
    }

    @Test("冷却期内不放行，时间走完后自动解除")
    func cooldownExpiresWithTime() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var service = makeService(store: store, clock: clock)
        exhaustGraceFailures(&service)

        let first = service.recordFailure()
        #expect(first == 30)

        clock.advance(10)
        #expect(service.remainingCooldown == 20, "冷却应随真实时间递减")

        clock.advance(25)
        #expect(service.remainingCooldown == 0, "到期后必须放行")
    }

    @Test("成功后计数与冷却一并清零")
    func successResetsEverything() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var service = makeService(store: store, clock: clock)
        exhaustGraceFailures(&service)
        service.recordFailure()
        #expect(service.remainingCooldown == 30)

        service.recordSuccess()
        #expect(service.remainingCooldown == 0)

        // 清零后应重新回到免罚区，而不是接着上一次的阶梯
        for attempt in 0..<UnlockThrottleService.graceFailures {
            #expect(service.recordFailure() == 0, "清零后第 \(attempt + 1) 次失败仍应免罚")
        }
    }

    @Test("计数跨实例存活：杀进程不能绕过限流")
    func stateSurvivesReinstantiation() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var first = makeService(store: store, clock: clock)
        exhaustGraceFailures(&first)
        first.recordFailure()

        let second = makeService(store: store, clock: clock)
        #expect(second.remainingCooldown == 30, "重建实例后仍应处于冷却中")
    }

    @Test("超过衰减窗口后视为新的一轮")
    func decaysAfterWindow() {
        let store = MemoryThrottleStore()
        let clock = TestClock()
        var first = makeService(store: store, clock: clock)
        exhaustGraceFailures(&first)
        first.recordFailure()

        clock.advance(UnlockThrottleService.decayWindow + 1)
        var second = makeService(store: store, clock: clock)
        #expect(second.remainingCooldown == 0, "超过衰减窗口不该继续惩罚")
        #expect(second.recordFailure() == 0, "新一轮应重新从免罚次数开始")
    }
}
