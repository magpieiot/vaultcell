/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AutoFillIdentityService.swift
/// created on: 2026/09/17
/// ------------------------------------------------------------------
///
/// AutoFill 凭据身份（credential identity）同步服务。
///
/// 系统只认识"注册过"的凭据：键盘 QuickType 建议、文本框自动填充按钮、
/// Safari / 第三方 App 的自动填充入口，都依赖 `ASCredentialIdentityStore`
/// 中存在对应的 `ASPasswordCredentialIdentity`。主 App 若不注册，用户只能
/// 手动点"钥匙 → VaultCell"唤起扩展（CredentialProviderViewController），
/// 快速填充建议永远不出现。
///
/// 同步策略：
/// - 全量 replace，保证与数据库最终一致（覆盖新增、修改、删除、回收站软删）；
/// - 只读取明文元数据（id / siteURL / username），不解密密码，
///   因此同步不依赖密码库解锁状态；
/// - 用户未在"设置 → 通用 → 自动填充与密码"中启用 VaultCell 时，
///   identity store 处于未启用状态，此时静默跳过，不报错也不打扰用户。
/// ------------------------------------------------------------------

import AuthenticationServices
import CoreData
import Foundation

extension Notification.Name {
    /// 密码条目发生增删改（含软删除与回收站物理清理）后发出。
    /// 供 AutoFill 身份同步等下游消费者做最终一致刷新。
    static let passwordEntriesDidChange = Notification.Name("VaultCell.passwordEntriesDidChange")

    /// AutoFill 扩展进程通过「保存密码」流程写入了新条目。
    /// 扩展与主 App 是独立进程，主 App 回到前台比对 App Group 时间戳后发出，
    /// 供密码列表等界面重新加载（列表本身感知不到跨进程写入）。
    static let autoFillDidSaveCredential = Notification.Name("VaultCell.autoFillDidSaveCredential")
}

/// 把所有密码条目注册为系统可识别的自动填充身份（单例）
final class AutoFillIdentityService {

    static let shared = AutoFillIdentityService()

    /// 与系统 identity store 交互的对象
    private let identityStore: ASCredentialIdentityStore
    private let notificationCenter: NotificationCenter

    /// 通知观察者句柄（只注册一次）
    private var changeObserver: NSObjectProtocol?
    /// 防抖中的同步任务（批量导入时合并为一次全量同步）
    private var pendingSyncTask: Task<Void, Never>?

    /// 合并连续写入的等待时间
    private let debounceNanoseconds: UInt64 = 300_000_000

    private init(identityStore: ASCredentialIdentityStore = .shared,
                 notificationCenter: NotificationCenter = .default) {
        self.identityStore = identityStore
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let changeObserver {
            notificationCenter.removeObserver(changeObserver)
        }
        pendingSyncTask?.cancel()
    }

    // MARK: - 订阅

    /// 开始监听密码库变更（幂等，重复调用无副作用）。
    /// 由 AppState 在启动时调用一次；变更后的同步经防抖后全量刷新。
    func startObservingChanges() {
        guard changeObserver == nil else { return }
        changeObserver = notificationCenter.addObserver(
            forName: .passwordEntriesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleSynchronization()
        }
    }

    /// 防抖后触发一次全量同步
    private func scheduleSynchronization() {
        NSLog("AutoFill: 收到条目变更通知，准备防抖同步")
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            guard let self else { return }
            let delay = self.debounceNanoseconds
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self.synchronize()
        }
    }

    // MARK: - 同步

    /// 自动填充扩展是否已由用户启用（未启用时 identity store 拒绝写入）
    func isAutoFillEnabled() async -> Bool {
        let state = await identityStore.state()
        return state.isEnabled
    }

    /// 用当前密码库内容全量替换系统 identity。
    /// - Returns: 是否成功写入（未启用或被系统拒绝时为 false）
    @discardableResult
    func synchronize() async -> Bool {
        let enabled = await isAutoFillEnabled()
        // NSLog 写 stderr，不经 Xcode 启动时也能进系统日志；print 只会写 stdout，控制台抓不到
        NSLog("AutoFill: identity store isEnabled = %@", enabled ? "true" : "false")

        guard enabled else {
            // 用户在系统设置里没勾选 VaultCell：写入必然失败，静默跳过
            NSLog("AutoFill: identity store 未启用（设置 → 通用 → 自动填充与密码 → VaultCell），跳过同步")
            await record(SyncReport(date: Date(), isEnabled: false,
                                    entryCount: 0, count: 0,
                                    budget: Self.identityBudget(), droppedEntryCount: 0,
                                    errorMessage: "系统未启用 VaultCell 自动填充"))
            return false
        }

        let plan = await Self.makeIdentityPlan()
        NSLog("AutoFill: 待注册 %d 条（%d 个条目），样例：%@",
              plan.identities.count, plan.entryCount,
              plan.identities.prefix(8).map { "\($0.serviceIdentifier.identifier) (\($0.serviceIdentifier.type == .domain ? "domain" : "url"))" })

        do {
            // 全量替换（幂等）：store 中已删除的条目会被一并清除
            try await identityStore.replaceCredentialIdentities(plan.identities)
            NSLog("AutoFill: 已同步 %d 条 credential identity", plan.identities.count)
            await record(SyncReport(date: Date(), isEnabled: true,
                                    entryCount: plan.entryCount, count: plan.identities.count,
                                    budget: plan.budget, droppedEntryCount: plan.droppedEntryCount,
                                    errorMessage: nil))
            return true
        } catch {
            NSLog("AutoFill: credential identity 同步失败：%@", String(describing: error))
            await record(SyncReport(date: Date(), isEnabled: true,
                                    entryCount: plan.entryCount, count: 0,
                                    budget: plan.budget, droppedEntryCount: plan.droppedEntryCount,
                                    errorMessage: error.localizedDescription))
            return false
        }
    }

    /// 主线程记录最近一次同步结果
    private func record(_ report: SyncReport) async {
        await MainActor.run { AutoFillIdentityService.lastSyncReport = report }
    }

    /// 最近一次同步结果，供设置页诊断展示
    struct SyncReport {
        let date: Date
        /// 自动填充是否已在系统设置中启用
        let isEnabled: Bool
        /// 实际参与同步的条目数
        let entryCount: Int
        /// 实际写入系统的身份数（写入失败时为 0）
        let count: Int
        /// 当前身份预算
        let budget: Int
        /// 因超预算被整组丢弃的条目数
        let droppedEntryCount: Int
        let errorMessage: String?
    }

    /// 最近一次同步结果（主线程读写）
    @MainActor static var lastSyncReport: SyncReport?

    // MARK: - 身份构造

    /// 一次同步的产物：身份列表 + 供设置页诊断展示的统计
    struct IdentityPlan {
        let identities: [ASPasswordCredentialIdentity]
        /// 实际参与同步的条目数（被预算丢弃的不计入）
        let entryCount: Int
        let budget: Int
        /// 因超预算被整组丢弃的条目数
        let droppedEntryCount: Int
    }

    /// 身份预算。
    ///
    /// 系统对单个提供者的身份条数没有公开数字，但批量写入是**原子**的：
    /// 超额会让整批被拒绝（一条都不写，QuickType 建议整体消失）。因此这里留出保守余量，
    /// 默认 5000；可用 UserDefaults 键 `AutoFillIdentityBudget` 覆盖（便于压测与调整）。
    private static func identityBudget() -> Int {
        let stored = UserDefaults.standard.integer(forKey: "AutoFillIdentityBudget")
        return stored > 0 ? stored : 5000
    }

    /// 从密码库读取可注册的条目并构造身份，同时给出预算相关统计。
    /// 在私有队列后台上下文执行：大库（数千条目 × 每条最多 4 条身份）下
    /// 构造上万条 ASPasswordCredentialIdentity 不再阻塞主线程。
    private static func makeIdentityPlan() async -> IdentityPlan {
        let budget = identityBudget()
        let context = CoreDataStack.shared.newBackgroundContext()

        return await withCheckedContinuation { continuation in
            context.perform {
                // 托管对象只允许在其所属上下文的队列上访问，构造全程留在 perform 内
                continuation.resume(returning: Self.buildIdentityPlan(in: context, budget: budget))
            }
        }
    }

    private static func buildIdentityPlan(in context: NSManagedObjectContext, budget: Int) -> IdentityPlan {
        let request: NSFetchRequest<CDPasswordEntry> = CDPasswordEntry.fetchRequest()
        // 与列表一致：回收站中的条目不再提供自动填充
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "siteName", ascending: true)]
        request.fetchBatchSize = 200

        guard let entries = try? context.fetch(request) else {
            NSLog("AutoFill: 读取密码库失败，跳过本次 identity 同步")
            return IdentityPlan(identities: [], entryCount: 0, budget: budget, droppedEntryCount: 0)
        }

        /// 一个条目展开出的整组身份：预算不足时按组取舍，避免半个条目的身份被写进去
        struct EntryGroup {
            let entry: CDPasswordEntry
            let identities: [ASPasswordCredentialIdentity]
        }

        var groups: [EntryGroup] = []
        for entry in entries {
            let username = entry.username.trimmingCharacters(in: .whitespacesAndNewlines)
            // 无用户名或无站点 URL 的条目系统无法匹配，跳过
            guard !username.isEmpty else { continue }
            // 身份构造走两端共享的实现：扩展保存密码后补登身份用的是同一份逻辑
            let identities = AutoFillCredentialIdentityFactory.identities(
                entryID: entry.id,
                username: username,
                siteURL: entry.siteURL
            )
            guard !identities.isEmpty else { continue }

            groups.append(EntryGroup(entry: entry, identities: identities))
        }

        let totalCount = groups.reduce(0) { $0 + $1.identities.count }
        var droppedEntryCount = 0
        var selected = groups

        if totalCount > budget {
            // 超预算：按「收藏 > 最近使用 > 最近更新」**整组**保留。
            // 旧实现按 siteName 排序砍尾，会让尾部站点完全失去建议且用户毫无感知。
            let ordered = groups.sorted { lhs, rhs in
                if lhs.entry.isFavorite != rhs.entry.isFavorite {
                    return lhs.entry.isFavorite
                }
                let lhsDate = lhs.entry.lastUsedAt ?? lhs.entry.updatedAt
                let rhsDate = rhs.entry.lastUsedAt ?? rhs.entry.updatedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.entry.siteName.localizedCaseInsensitiveCompare(rhs.entry.siteName) == .orderedAscending
            }

            var kept: [EntryGroup] = []
            var used = 0
            for group in ordered {
                if used + group.identities.count > budget { break }
                used += group.identities.count
                kept.append(group)
            }
            droppedEntryCount = groups.count - kept.count
            NSLog("AutoFill: 身份数 %d 超过预算 %d，已按「收藏 > 最近使用 > 最近更新」保留 %d 个条目（%d 条身份），丢弃 %d 个条目",
                  totalCount, budget, kept.count, used, droppedEntryCount)
            // 恢复站点名顺序，保持 dump 与列表的可读性
            selected = kept.sorted {
                $0.entry.siteName.localizedCaseInsensitiveCompare($1.entry.siteName) == .orderedAscending
            }
        }

        var identities: [ASPasswordCredentialIdentity] = []
        identities.reserveCapacity(min(totalCount, budget))
        for group in selected {
            identities.append(contentsOf: group.identities)
        }

        // 诊断：分批输出最终写入的全部标识，便于在控制台按站点检索（如搜 ctrip）
        // 排查「QuickType 建议不出现」时临时打开：数据量大会拖慢同步，平时保持关闭
        // 小库默认输出；大库用启动参数 -AutoFillDumpIdentities 显式打开
        if ProcessInfo.processInfo.arguments.contains("-AutoFillDumpIdentities") || identities.count <= 500 {
            for chunk in stride(from: 0, to: identities.count, by: 10) {
                let end = min(chunk + 10, identities.count)
                let line = identities[chunk..<end].map { identity in
                    "\(identity.serviceIdentifier.identifier)(\(identity.serviceIdentifier.type == .domain ? "d" : "u"))"
                }.joined(separator: " ")
                NSLog("AutoFill: identities[\(chunk)..<\(end)] = %@", line)
            }
        }

        return IdentityPlan(identities: identities, entryCount: selected.count,
                            budget: budget, droppedEntryCount: droppedEntryCount)
    }

    // serviceIdentifier 的推导统一使用两端共享的 AutoFillCredentialIdentityFactory
    // （与扩展侧保存密码后补登身份同源），避免注册端与匹配端推导不一致导致键盘建议错位。
}
