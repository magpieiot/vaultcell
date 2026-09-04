/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CredentialProviderViewController.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import AuthenticationServices
import UIKit
import SwiftUI

@available(iOS 17.0, *)
class CredentialProviderViewController: ASCredentialProviderViewController {

    private let credentialStore = AutoFillCredentialStore.shared

    private var hostingController: UIHostingController<CredentialListView>?

    /// 展示密码选择列表：用户在第三方登录界面点击"钥匙"并选择 VaultCell 后进入。
    /// 流程：生物识别解锁（系统弹出 Face ID / Touch ID）→ 读取共享密码库 → 展示列表。
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let rootView = CredentialListView(
            serviceIdentifiers: serviceIdentifiers,
            store: credentialStore,
            onSelect: { [weak self] credential in
                self?.provideCredential(credential)
            },
            onCancel: { [weak self] in
                self?.cancelUserRequest()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        guard let hostView = hostingController.view else {
            return
        }
        hostView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: view.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    /// 键盘快速类型（无用户交互）快速填充入口。
    /// 无 UI 上下文中无法完成生物识别解锁（userPresence 读取会立即失败），
    /// 因此回退为"需要用户交互"，由系统转入交互流程。
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        do {
            // 快速路径不允许弹认证 UI：unlock 内部会抛出认证失败
            try credentialStore.unlock()
            guard let credential = try findCredential(for: credentialRequest) else {
                extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
                return
            }
            provideCredential(credential)
        } catch {
            extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
        }
    }

    /// 用户在快速类型中选择某条建议后的入口：此时允许展示生物识别认证界面
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        Task {
            do {
                try await unlockCredentialStore()
                guard let credential = try findCredential(for: credentialRequest) else {
                    extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
                    return
                }
                provideCredential(credential)
            } catch {
                extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
            }
        }
    }

    override func prepareInterfaceForExtensionConfiguration() {
        // 配置界面无需实现
    }

    // MARK: - Private

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
    /// 用户名精确匹配优先，其次参考服务标识（域名/URL）匹配。
    private func findCredential(for request: ASCredentialRequest) throws -> ASPasswordCredential? {
        // 取请求关联的用户名与服务标识
        let identity = (request as? ASPasswordCredentialRequest)?.credentialIdentity
        let username = identity?.user
        let serviceIdentifier = identity?.serviceIdentifier.identifier

        guard username != nil || serviceIdentifier != nil else {
            return nil
        }

        let items = try credentialStore.fetchCredentials()

        // 1. 先按用户名过滤（无用户名要求时保留全部）
        let candidates = items.filter { item in
            guard let username else { return true }
            return item.username.caseInsensitiveCompare(username) == .orderedSame
        }
        // 2. 在候选中优先匹配服务标识
        let matched: CredentialItem?
        if let serviceIdentifier {
            matched = candidates.first {
                AutoFillCredentialStore.matches(service: serviceIdentifier, siteURL: $0.siteURL)
            } ?? candidates.first
        } else {
            matched = candidates.first
        }

        guard let matched else { return nil }
        return ASPasswordCredential(user: matched.username, password: matched.password)
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
    @State private var credentials: [CredentialItem] = []
    @State private var searchText = ""
    @State private var retryToken = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("选择密码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") {
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
                Text("正在验证身份…")
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
                Button("重试") {
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
                    Text(credentials.isEmpty ? "暂无可用密码" : "没有匹配的密码")
                        .font(.headline)
                    Text("请先在 VaultCell 中保存密码")
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
                .searchable(text: $searchText, prompt: "搜索密码")
            }
        }
    }

    private var filteredCredentials: [CredentialItem] {
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
        do {
            // 1. 生物识别解锁（后台线程触发系统认证 UI）
            try await unlockCredentialStore()
            // 2. 主线程读取共享数据库并解密（viewContext 绑定主线程）
            let items = try store.fetchCredentials()
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
            phase = .failed("身份验证失败，请重试")
        case .vaultLocked:
            phase = .failed("密码库已锁定，请重试")
        case .databaseUnavailable, .invalidData:
            phase = .failed(error.localizedDescription)
        }
    }

    /// 将匹配当前站点的条目置顶（不隐藏其它条目，用户仍可搜索选择）
    private func prioritized(_ items: [CredentialItem]) -> [CredentialItem] {
        guard !serviceIdentifiers.isEmpty else {
            return items
        }
        let serviceIDs = serviceIdentifiers.compactMap { $0.identifier }
        guard !serviceIDs.isEmpty else {
            return items
        }

        func score(_ item: CredentialItem) -> Int {
            serviceIDs.contains {
                AutoFillCredentialStore.matches(service: $0, siteURL: item.siteURL)
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

    private func selectCredential(_ credential: CredentialItem) {
        let passwordCredential = ASPasswordCredential(
            user: credential.username,
            password: credential.password
        )
        onSelect(passwordCredential)
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

struct CredentialItem: Identifiable, Codable {
    let id: UUID
    let siteName: String
    let siteURL: String
    let username: String
    let password: String
}
