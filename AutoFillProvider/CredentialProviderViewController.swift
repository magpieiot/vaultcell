/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CredentialProviderViewController.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import AuthenticationServices
import Darwin
import UIKit
import SwiftUI

/// 扩展进程创建时刻的读取器（诊断用）。
/// 各入口打印"距进程启动 X 秒"，用于把「系统侧冷启动（进程 spawn → 首个回调）」
/// 与「扩展代码内耗时」区分开：若入口日志就已是数秒，瓶颈在冷启动而非代码逻辑。
private enum ExtensionProcessClock {
    /// 进程创建时刻（sysctl KERN_PROC 读取，首次访问时计算一次）
    private static let processStartTime: Date? = {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        // kp_proc.p_un 是 union，Swift 直接点取 p_starttime 有未对齐风险，
        // 按字节偏移安全读取（受控实验验证过读取的就是进程创建时刻）
        guard let unOffset = MemoryLayout<kinfo_proc>.offset(of: \kinfo_proc.kp_proc.p_un) else { return nil }
        return withUnsafeBytes(of: info) { raw in
            guard let base = raw.baseAddress else { return nil }
            let tv = base.loadUnaligned(fromByteOffset: unOffset, as: timeval.self)
            return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
        }
    }()

    /// 距扩展进程创建的秒数（读取失败时为 0，仅失去诊断精度）
    static var secondsSinceProcessStart: Double {
        guard let processStartTime else { return 0 }
        return Date().timeIntervalSince(processStartTime)
    }
}

@available(iOS 17.0, *)
class CredentialProviderViewController: ASCredentialProviderViewController {

    private let credentialStore = AutoFillCredentialStore.shared

    private var hostingController: UIHostingController<AnyView>?

    /// 展示密码选择列表：用户在第三方登录界面点击"钥匙"并选择 VaultCell 后进入。
    /// 流程：生物识别解锁（系统弹出 Face ID / Touch ID）→ 读取共享密码库 → 展示列表。
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // 语言覆盖 swizzle 必须在任何本地化文案解析前安装
        ExtensionLanguage.activate()
        // 共享数据库的首次打开与"解锁 + 列表加载"并行，不占关键路径
        credentialStore.warmUpDatabase()
        NSLog("AutoFill: 进入 prepareCredentialList（距进程启动 %.2fs）",
              ExtensionProcessClock.secondsSinceProcessStart)
        // 诊断：系统实际下发的标识决定 QuickType 能否命中，控制台可见
        NSLog("AutoFill: serviceIdentifiers = %@", serviceIdentifiers.map { "\($0.type == .domain ? "domain" : "url")|\($0.identifier)" })

        present(CredentialListView(
            serviceIdentifiers: serviceIdentifiers,
            store: credentialStore,
            onSelect: { [weak self] credential in
                self?.provideCredential(credential)
            },
            onCancel: { [weak self] in
                self?.cancelUserRequest()
            }
        ))
    }

    /// 键盘快速类型（无用户交互）快速填充入口。
    /// 无 UI 上下文中无法完成生物识别解锁（userPresence 读取会立即失败），
    /// 因此回退为"需要用户交互"，由系统转入交互流程。
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        ExtensionLanguage.activate()
        // 共享数据库的首次打开与本方法内的 Keychain 读取/查找并行：
        // 免交互路径若成功则直接命中就绪容器；若回落交互路径，容器也已就绪
        credentialStore.warmUpDatabase()
        NSLog("AutoFill: 进入免交互路径（距进程启动 %.2fs）",
              ExtensionProcessClock.secondsSinceProcessStart)
        let start = Date()
        do {
            // 快速路径不允许弹认证 UI：只复用近期已有的认证，取不到就立刻回落交互流程。
            // 绝不能在这里用普通 unlock()（会弹出被系统立即取消的 Face ID，导致交互路径第一次必失败）
            try credentialStore.unlockWithoutUserInteraction()
            guard let credential = try findCredential(for: credentialRequest) else {
                // 不能再回 credentialIdentityNotFound：该错误系统不会弹任何 UI，
                // 用户看到的就是"点了密码建议毫无反应"。统一回落到交互流程。
                NSLog("AutoFill: 免交互路径未定位到条目，回落交互流程（%.2fs）", Date().timeIntervalSince(start))
                extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
                return
            }
            NSLog("AutoFill: 免交互路径直接填充成功（%.2fs）", Date().timeIntervalSince(start))
            provideCredential(credential)
        } catch {
            // 含"快速路径不允许认证"的正常回落
            NSLog("AutoFill: 免交互路径不可用（%@），回落交互流程", String(describing: error))
            extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
        }
    }

    /// 用户在快速类型中选择某条建议后的入口：此时允许展示生物识别认证界面。
    ///
    /// 这里必须给出真实的界面：旧实现在失败时以 `userInteractionRequired` 再次取消，
    /// 系统随后收起扩展面板，表现为"闪一下空白列表又缩回、什么都没填"。
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        ExtensionLanguage.activate()
        // 关键优化：共享数据库的首次打开（模型加载 + 迁移检查 + WAL 恢复）
        // 在此立刻后台触发，与"系统呈现扩展面板 + Face ID 认证"完全并行，
        // 解锁成功后的单条读取直接命中就绪容器
        credentialStore.warmUpDatabase()
        NSLog("AutoFill: 进入交互路径（距进程启动 %.2fs）",
              ExtensionProcessClock.secondsSinceProcessStart)
        present(CredentialUnlockView(
            load: { [weak self] in
                guard let self else { return }
                let start = Date()
                // 扩展界面由系统在 prepareInterfaceToProvideCredential 返回后才呈现，
                // 过早发起生物识别会被系统立即取消（表现为"第一次必失败、点重试才行"）。
                try? await Task.sleep(nanoseconds: 350_000_000)
                try await self.unlockCredentialStore()
                let unlockCost = Date().timeIntervalSince(start)

                guard let credential = try self.findCredential(for: credentialRequest) else {
                    throw CredentialLookupError()
                }
                NSLog("AutoFill: 交互路径填充成功（解锁 %.2fs，合计 %.2fs）",
                      unlockCost, Date().timeIntervalSince(start))
                self.provideCredential(credential)
            },
            onCancel: { [weak self] in
                self?.cancelUserRequest()
            }
        ))
    }

    override func prepareInterfaceForExtensionConfiguration() {
        // 配置界面无需实现
    }

    // MARK: - 保存密码（iOS 26.2+）

    /// 免交互保存入口（系统在处理保存请求时优先尝试）。
    ///
    /// 调用时扩展界面**不在屏幕上**：既不能发起生物识别（Face ID 会被系统立即取消），
    /// 也不能展示"是否保存"的确认界面。直接入库等于替用户做了决定，因此一律回
    /// `userInteractionRequired`，让系统转入交互流程由用户显式确认。
    @available(iOS 26.2, *)
    override func performWithoutUserInteractionIfPossible(savePasswordRequest request: ASSavePasswordRequest) {
        ExtensionLanguage.activate()
        NSLog("AutoFill: 收到免交互保存请求（site=%@ user=%@），回落交互确认",
              request.serviceIdentifier.identifier, request.credential.user)
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }

    /// 保存密码的交互入口：展示"是否保存到 VaultCell"的确认界面。
    ///
    /// 系统在 Safari / App 里检测到登录表单提交后调用；确认保存后必须调用
    /// `completeSavePasswordRequest`，取消则回 `userCanceled`。
    @available(iOS 26.2, *)
    override func prepareInterface(for savePasswordRequest: ASSavePasswordRequest) {
        ExtensionLanguage.activate()
        // 数据库打开与"系统呈现面板 + Face ID"并行，解锁后写入直接命中就绪容器
        credentialStore.warmUpDatabase()
        let draft = Self.draft(from: savePasswordRequest)
        NSLog("AutoFill: 进入保存密码流程（site=%@ user=%@）",
              draft.siteURL ?? "-", draft.username)

        present(SavePasswordView(
            draft: draft,
            store: credentialStore,
            onSave: { [weak self] in
                self?.extensionContext.completeSavePasswordRequest()
            },
            onCancel: { [weak self] in
                self?.cancelUserRequest()
            }
        ))
    }

    /// 把系统保存请求映射为待写入凭据。
    /// - 站点 URL：统一存 `https://host`（与主 App 条目一致，`AutoFillDomainMatcher` 可解析）；
    /// - 站点名：优先用系统给的页面标题，缺失时退化为可注册域名的首字母大写。
    @available(iOS 26.2, *)
    private static func draft(from request: ASSavePasswordRequest) -> CredentialSaveDraft {
        let identifier = request.serviceIdentifier.identifier
        let host = AutoFillDomainMatcher.hostname(from: identifier)
        let siteURL = host.map { "https://\($0)" } ?? (identifier.isEmpty ? nil : identifier)

        let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteName: String
        if let title, !title.isEmpty {
            siteName = title
        } else if let host {
            let domain = AutoFillDomainMatcher.registrableDomain(of: host) ?? host
            // "ctrip.com" → "Ctrip"：去掉 TLD 后首字母大写，作为可读的站点名
            let name = domain.split(separator: ".").first.map(String.init) ?? domain
            siteName = name.prefix(1).uppercased() + name.dropFirst()
        } else {
            siteName = identifier
        }

        return CredentialSaveDraft(
            siteName: siteName,
            siteURL: siteURL,
            username: request.credential.user,
            password: request.credential.password
        )
    }

    // MARK: - Private

    /// 把 SwiftUI 视图装进扩展视图控制器（扩展只有这一块展示区域）
    private func present(_ rootView: some View) {
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let hosting = UIHostingController(rootView: AnyView(rootView))
        hostingController = hosting

        addChild(hosting)
        guard let hostView = hosting.view else { return }
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.backgroundColor = .clear
        view.addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: view.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hosting.didMove(toParent: self)
    }

    private func cancelUserRequest() {
        extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
    }

    private func provideCredential(_ credential: ASPasswordCredential) {
        extensionContext.completeRequest(withSelectedCredential: credential)
    }

    /// 在后台线程完成 Keychain 生物识别解锁，避免阻塞主线程 UI
    private func unlockCredentialStore() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result<Void, Error> {
                    try self.credentialStore.unlock()
                })
            }
        }
    }

    /// 根据系统请求在已解锁凭据中定位一条记录：
    /// 记录标识精确匹配优先，其次用户名精确匹配，最后参考服务标识（域名/URL）匹配。
    /// 全程只解密命中的那一条，代价与密码库大小无关。
    private func findCredential(for request: ASCredentialRequest) throws -> ASPasswordCredential? {
        // 取请求关联的用户名、服务标识与记录标识
        let identity = (request as? ASPasswordCredentialRequest)?.credentialIdentity
        NSLog("AutoFill: request identity = %@", identity.map { "\($0.serviceIdentifier.type == .domain ? "domain" : "url")|\($0.serviceIdentifier.identifier) user=\($0.user) record=\($0.recordIdentifier ?? "-")" } ?? "nil")
        let username = identity?.user
        let serviceIdentifier = identity?.serviceIdentifier.identifier
        // 主 App 为同一条目注册多条身份时会加 "#序号" 后缀保证唯一，这里还原条目 ID
        let recordIdentifier = identity?.recordIdentifier?.components(separatedBy: "#").first

        // 0. 主 App 注册 identity 时写入了条目 ID，命中即单行取回，
        //    避免"同一用户名存在于多个站点"时填错密码
        if let recordIdentifier, let id = UUID(uuidString: recordIdentifier),
           let resolved = try credentialStore.credential(for: id) {
            return ASPasswordCredential(user: resolved.username, password: resolved.password)
        }

        guard username != nil || serviceIdentifier != nil else {
            return nil
        }

        // 1. 读取元数据（不解密）后按用户名过滤（无用户名要求时保留全部）
        let summaries = try credentialStore.fetchCredentialSummaries()
        let candidates = summaries.filter { item in
            guard let username else { return true }
            return item.username.caseInsensitiveCompare(username) == .orderedSame
        }
        // 2. 在候选中匹配服务标识。
        //    安全取舍：用户名相同但站点不匹配时**不做兜底**——宁可不填，
        //    也不能把另一个站点的密码静默填进当前输入框；
        //    免交互路径返回 nil 后系统会回落交互流程，用户仍可手动选择。
        let matched: CredentialSummary?
        if let serviceIdentifier {
            matched = candidates.first {
                AutoFillDomainMatcher.matches(service: serviceIdentifier, siteURL: $0.siteURL)
            }
        } else {
            matched = candidates.first
        }

        guard let matched, let resolved = try credentialStore.credential(for: matched.id) else {
            return nil
        }
        return ASPasswordCredential(user: resolved.username, password: resolved.password)
    }
}

/// 交互路径中未能定位到条目时的用户可见错误。
/// 注意：这里刻意不使用 ASExtensionError(.userInteractionRequired)——
/// 在交互路径上再次回该错误会让系统直接收起面板，用户什么都看不到。
private struct CredentialLookupError: LocalizedError {
    var errorDescription: String? {
        String(localized: "No password found for this site. Make sure the item is saved in VaultCell and has a username.")
    }
}

@available(iOS 17.0, *)
struct CredentialListView: View {
    /// 当前页面加载/解锁状态
    private enum LoadPhase {
        case unlocking      // 等待生物识别或读取数据
        case loaded
        case failed(String) // 错误信息，可重试
    }

    let serviceIdentifiers: [ASCredentialServiceIdentifier]
    let store: AutoFillCredentialStore
    let onSelect: (ASPasswordCredential) -> Void
    let onCancel: () -> Void

    @State private var phase: LoadPhase = .unlocking
    @State private var credentials: [CredentialSummary] = []
    @State private var searchText = ""
    @State private var retryToken = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Select Password")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            onCancel()
                        }
                    }
                }
        }
        .task(id: retryToken) {
            await loadCredentials()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .unlocking:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Verifying identity…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") {
                    retryToken += 1
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

        case .loaded:
            if filteredCredentials.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(credentials.isEmpty
                         ? String(localized: "No passwords available")
                         : String(localized: "No matching passwords"))
                        .font(.headline)
                    Text("Save a password in VaultCell first")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(filteredCredentials) { credential in
                    Button(action: {
                        selectCredential(credential)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(credential.siteName)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(credential.username)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search passwords")
            }
        }
    }

    private var filteredCredentials: [CredentialSummary] {
        guard !searchText.isEmpty else {
            return credentials
        }
        return credentials.filter { credential in
            credential.siteName.localizedCaseInsensitiveContains(searchText) ||
            credential.username.localizedCaseInsensitiveContains(searchText) ||
            credential.siteURL.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - 加载

    private func loadCredentials() async {
        phase = .unlocking
        let start = Date()
        do {
            // 1. 生物识别解锁（后台线程触发系统认证 UI）
            // 等系统把扩展界面呈现出来再发起，过早会被立即取消
            try? await Task.sleep(nanoseconds: 350_000_000)
            try await unlockCredentialStore()
            let unlockCost = Date().timeIntervalSince(start)
            // 2. 后台线程读取元数据（不解密整库；密码在选中某条时才单条解密）
            let items = try await loadSummaries()
            NSLog("AutoFill: 列表加载完成 解锁 %.2fs 读取 %d 条 %.2fs",
                  unlockCost, items.count, Date().timeIntervalSince(start) - unlockCost)
            credentials = prioritized(items)
            phase = .loaded
        } catch let error as AutoFillCredentialStoreError {
            handleLoadFailure(error)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func handleLoadFailure(_ error: AutoFillCredentialStoreError) {
        switch error {
        case .vaultNotConfigured:
            // 尚无密码库：进入空态引导用户先在 VaultCell 中保存密码
            credentials = []
            phase = .loaded
        case .authenticationFailed:
            phase = .failed(String(localized: "Authentication failed. Please try again."))
        case .vaultLocked:
            phase = .failed(String(localized: "The vault is locked. Please try again."))
        case .databaseUnavailable, .invalidData:
            phase = .failed(error.localizedDescription)
        }
    }

    /// 将匹配当前站点的条目置顶（不隐藏其它条目，用户仍可搜索选择）
    private func prioritized(_ items: [CredentialSummary]) -> [CredentialSummary] {
        guard !serviceIdentifiers.isEmpty else {
            return items
        }
        let serviceIDs = serviceIdentifiers.compactMap { $0.identifier }
        guard !serviceIDs.isEmpty else {
            return items
        }

        func score(_ item: CredentialSummary) -> Int {
            serviceIDs.contains {
                AutoFillDomainMatcher.matches(service: $0, siteURL: item.siteURL)
            } ? 1 : 0
        }

        return items.sorted { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.siteName.localizedCaseInsensitiveCompare(rhs.siteName) == .orderedAscending
        }
    }

    /// 选中某条：此刻才按 ID 单条解密（列表加载阶段完全不碰密文）
    private func selectCredential(_ credential: CredentialSummary) {
        Task {
            do {
                guard let resolved = try await resolveCredential(credential.id) else {
                    phase = .failed(String(localized: "Couldn't read this item's password. It may have been deleted or moved in VaultCell."))
                    return
                }
                onSelect(ASPasswordCredential(user: resolved.username, password: resolved.password))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 在后台线程单条解密（Core Data 读取走私有队列上下文，不阻塞主线程）
    private func resolveCredential(_ id: UUID) async throws -> (username: String, password: String)? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try self.store.credential(for: id) })
            }
        }
    }

    /// 在后台线程读取列表元数据（不解密，库再大也很快）
    private func loadSummaries() async throws -> [CredentialSummary] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try self.store.fetchCredentialSummaries() })
            }
        }
    }

    private func unlockCredentialStore() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result<Void, Error> {
                    try self.store.unlock()
                })
            }
        }
    }
}

/// 点击某条自动填充建议后的交互界面（蓝牙/键盘上方建议 → 需要验证身份时展示）。
///
/// 旧实现在这个入口不搭任何界面：认证失败或没找到条目时直接以
/// `userInteractionRequired` / `credentialIdentityNotFound` 取消，系统随即收起面板，
/// 用户看到的就是"闪一下空白列表又缩回、什么都没填"。这里改为把过程与失败原因
/// 都显示出来，并允许重试。
@available(iOS 17.0, *)
struct CredentialUnlockView: View {
    /// 执行一次填充尝试：成功时内部会 completeRequest，界面随请求结束消失
    let load: () async throws -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?
    @State private var retryToken = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let errorMessage {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    Button("Retry") {
                        retryToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text("Verifying identity…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("VaultCell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .task(id: retryToken) {
            errorMessage = nil
            do {
                try await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 保存密码确认界面（iOS 26.2+ 的保存流程，由 `prepareInterface(for:)` 呈现）。
///
/// 确认之前既不解锁也不解密：只展示系统给的站点 / 用户名 / 密码，
/// 用户点保存后才发起生物识别并写入共享密码库。
@available(iOS 17.0, *)
struct SavePasswordView: View {
    let draft: CredentialSaveDraft
    let store: AutoFillCredentialStore
    /// 保存成功后调用（由外层完成系统请求）
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsPassword = false
    /// 库中已存在同站点 + 同用户名的条目：保存会覆盖其密码
    @State private var existingEntryExists = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "lock.square.stack")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    Text("Save this password to VaultCell?")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    row(title: String(localized: "Website"), value: draft.siteName)
                    row(title: String(localized: "Username"), value: draft.username)
                    passwordRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                if existingEntryExists {
                    Text("An item for this site and username already exists. Its password will be updated.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button(action: { Task { await save() } }) {
                        Text(isSaving ? String(localized: "Saving…") : String(localized: "Save Password"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Button(action: onCancel) {
                        Text("Not Now")
                    }
                }
            }
            .padding()
            .navigationTitle("Save Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 系统要求：必须始终提供取消途径
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .task { await checkExistingEntry() }
    }

    @ViewBuilder
    private func row(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .lineLimit(2)
        }
    }

    private var passwordRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Password"))
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                // 默认遮蔽：扩展界面可能被系统截图，避免明文常驻屏幕
                Text(showsPassword ? draft.password : String(repeating: "•", count: min(draft.password.count, 12)))
                    .font(.subheadline.monospaced())
                    .lineLimit(1)
                Button(action: { showsPassword.toggle() }) {
                    Image(systemName: showsPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 加载与保存

    /// 预先判断是新建还是覆盖（只读元数据，不需要解锁）
    private func checkExistingEntry() async {
        let existing = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: (try? self.store.existingEntryID(for: self.draft)) != nil)
            }
        }
        existingEntryExists = existing
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            // 与交互填充路径同因：等系统把扩展界面呈现出来再发起生物识别
            try? await Task.sleep(nanoseconds: 350_000_000)
            try await unlockStore()
            let outcome = try await writeCredential()
            await registerIdentities(entryID: outcome.entryID)
            NSLog("AutoFill: 保存密码完成（id=%@ site=%@ url=%@ user=%@）",
                  outcome.entryID.uuidString, draft.siteName, draft.siteURL ?? "-", draft.username)
            onSave()
        } catch let error as AutoFillCredentialStoreError {
            NSLog("AutoFill: 保存密码失败（store）：%@", String(describing: error))
            errorMessage = error.localizedDescription
        } catch {
            // Core Data 层的错误（NSError）不走上面的分支，必须打到日志里，
            // 否则现场只会看到一句"请重试"而无从判断原因
            NSLog("AutoFill: 保存密码失败：%@", String(describing: error))
            errorMessage = String(localized: "Couldn't save the password. Please try again.")
                + "\n(\(error.localizedDescription))"
        }
    }

    private func unlockStore() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result<Void, Error> { try self.store.unlock() })
            }
        }
    }

    private func writeCredential() async throws -> CredentialSaveOutcome {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try self.store.saveCredential(self.draft) })
            }
        }
    }

    /// 保存后登记身份。
    ///
    /// Apple 要求扩展在保存完成后自行更新 `ASCredentialIdentityStore`，否则键盘
    /// QuickType 不会给出刚保存的条目；用户在系统设置里没启用 VaultCell 时写入
    /// 会被拒绝，这里静默忽略（主 App 下次同步仍会全量补上）。
    private func registerIdentities(entryID: UUID) async {
        let identities = AutoFillCredentialIdentityFactory.identities(
            entryID: entryID,
            username: draft.username,
            siteURL: draft.siteURL
        )
        guard !identities.isEmpty else { return }
        do {
            try await ASCredentialIdentityStore.shared.saveCredentialIdentities(identities)
        } catch {
            NSLog("AutoFill: 保存后身份登记失败：%@", String(describing: error))
        }
    }
}
