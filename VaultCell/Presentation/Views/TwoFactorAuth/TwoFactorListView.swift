/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TwoFactorListView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 密码库中带有 TOTP（TOTP）字段的记录列表
/// 每条记录一行：
/// 1）站点图标
/// 2）名称、账号名
/// 3）TOTP code
/// 4）倒计时显示
/// 点击进入密码详情页。
struct TwoFactorListView: View {
    @ObservedObject var viewModel: VaultListViewModel
    @ObservedObject var twoFactorService: TwoFactorService

    private let securityAuditService = VaultSecurityAuditService()

    /// 仅保留带有 TOTP 配置的密码条目
    private var totpEntries: [PasswordEntry] {
        viewModel.items.compactMap {
            guard case .password(let entry) = $0 else { return nil }
            guard let configs = entry.twoFactorConfigs,
                configs.contains(where: { $0.type == .totp })
            else { return nil }
            return entry
        }
    }

    /// 进入详情页所需的密码库安全审计结果（与 VaultListView 一致）
    private var securityAudit: VaultSecurityAudit {
        securityAuditService.calculate(entries: viewModel.passwordEntriesForAudit)
    }

    /// 所有 TOTP 条目共用同一时间步长，取第一条配置即可；无配置时回退默认值 30 秒。
    private var sharedTOTPPPeriod: Int {
        totpEntries.first?.twoFactorConfigs?.first { $0.type == .totp }?.period ?? 30
    }

    var body: some View {
        NavigationStack {
            Group {
                if totpEntries.isEmpty {
                    emptyView
                } else {
                    VStack(spacing: 0) {
                        TOTPSharedProgressView(period: sharedTOTPPPeriod)

                        List {
                            Section {
                                ForEach(totpEntries) { entry in
                                    Button {
                                        viewModel.selectedDestination = .passwordDetail(entry.id)
                                    } label: {
                                        TOTPEntryRow(
                                            entry: entry,
                                            category: viewModel.category(for: entry.categoryID)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // 底部空行，避免最后一条记录被 CustomTabBar 遮挡
                            Section {
                                Color.clear
                                    .frame(height: 60)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("TOTP")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $viewModel.selectedDestination) { destination in
                switch destination {
                case .passwordDetail(let id):
                    if let entry = totpEntries.first(where: { $0.id == id }) {
                        PasswordDetailView(entry: entry, viewModel: viewModel, audit: securityAudit)
                    }
                case .pincodeDetail, .bankcardDetail:
                    EmptyView()
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No TOTP Accounts")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Accounts with a TOTP key configured will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - 共享 TOTP 刷新指示器

/// 所有验证码按同一周期刷新，用一个顶部线性指示器替代每行重复的倒计时环。
private struct TOTPSharedProgressView: View {
    let period: Int

    var body: some View {
        TimelineView(.animation) { context in
            let step = TOTPService.shared.currentTimeStep(period: period, at: context.date)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Spacer(minLength: 0)
                    Text("All codes refresh in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(step.remainingSeconds)s")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(progressColor(for: step.remainingSeconds))
                    //Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(progressColor(for: step.remainingSeconds))
                            .frame(width: proxy.size.width * CGFloat(1 - step.progress))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .background(Color(.systemBackground))
    }

    /// 剩余时间的强调色，进度条与秒数共用；最后 5 秒切换为语义色提醒。
    private func progressColor(for remainingSeconds: Int) -> Color {
        remainingSeconds > 0 && remainingSeconds <= 5
            ? Color.errorColor
            : Color.appAccent
    }
}

// MARK: - 单条 TOTP 记录行

struct TOTPEntryRow: View {
    let entry: PasswordEntry
    let category: PasswordCategory?

    /// 取第一条 TOTP 配置用于生成动态验证码
    private var totpConfig: TwoFactorConfig? {
        entry.twoFactorConfigs?.first { $0.type == .totp }
    }

    var body: some View {
        HStack(spacing: 12) {
            iconView

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.siteName)
                    .font(.headline)
                    .lineLimit(1)

                Text(entry.username)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            if let config = totpConfig {
                TOTPCodeView(config: config, showsProgressRing: false)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        //.padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - 站点图标
    /// 与 PasswordDetailView.iconView 一致：显示优先级统一由 IconResolver 决定
    private var iconView: some View {
        CachedIconView(
            request: IconRequest(
                title: entry.siteName,
                siteURL: entry.siteURL,
                manualIconURL: entry.icon
            ),
            fallbackSystemName: category?.icon ?? "folder.fill",
            placeholderColor: category?.tintColor ?? .blue
        )
        .frame(width: 36, height: 36)
        .cornerRadius(8)
    }
}
