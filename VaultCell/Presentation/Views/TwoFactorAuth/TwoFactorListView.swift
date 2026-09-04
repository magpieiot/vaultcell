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

    var body: some View {
        NavigationStack {
            Group {
                if totpEntries.isEmpty {
                    emptyView
                } else {
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
                TOTPCodeView(config: config)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        //.padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - 站点图标
    /// 与 PasswordDetailView.iconView 一致的显示优先级：
    /// 1. 本地预制资源（通过站点名做大小写不敏感匹配）
    /// 2. 远程 URL 加载（entry.icon 指向的图片地址）
    /// 3. 分类默认 SF Symbol 图标
    private var iconView: some View {
        Group {
            if let bundledIconName = bundledIconName {
                Image(bundledIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // 缓存优先：本地缓存 → 远程加载并落盘 → 分类图标占位
                CachedIconView(
                    urlString: entry.icon ?? entry.siteURL,
                    placeholderSystemName: category?.icon ?? "folder.fill",
                    placeholderColor: category?.tintColor ?? .blue
                )
            }
        }
        .frame(width: 36, height: 36)
        .cornerRadius(8)
    }

    private var bundledIconName: String? {
        famousApps.first(where: { $0.title.caseInsensitiveCompare(entry.siteName) == .orderedSame }
        )?
        .icon
            ?? famousAppsCn.first(where: {
                $0.title.caseInsensitiveCompare(entry.siteName) == .orderedSame
            })?
            .icon
    }
}
