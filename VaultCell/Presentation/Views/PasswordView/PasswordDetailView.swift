/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordDetailView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 密码详情视图
/// 展示单条密码记录的完整信息，包括站点图标、用户名、密码、2FA 配置、
/// 绑定手机号/邮箱、密码找回方式、备注、标签以及创建/更新日期等
struct PasswordDetailView: View {
    /// 当前展示的密码条目（领域模型）。
    /// 使用 @State 持有，编辑保存后通过 onChange(of: viewModel.items) 刷新为最新版本，
    /// 保证修改 tag 等字段后返回详情页能立即生效
    @State private var entry: PasswordEntry
    /// 父级 ViewModel，用于编辑/更新后回传变更
    @ObservedObject var viewModel: VaultListViewModel
    /// 上层已计算好的密码库安全审计结果
    let audit: VaultSecurityAudit
    /// 密码是否明文可见
    @State private var isPasswordVisible = false
    /// 密码是否为空：为空时禁用密码行右侧操作按钮，强度显示全灰
    private var isPasswordEmpty: Bool {
        entry.password.isEmpty
    }
    /// 是否正在展示"已复制"提示
    @State private var showingCopied = false
    /// 是否弹出编辑页
    @State private var showingEditSheet = false
    /// 是否弹出 OAuth 信息
    @State private var showingOAuthInfo = false
    /// 是否展示安全问题
    @State private var showSecurityIssues = false

    /// 初始化：接收条目的初始快照
    init(entry: PasswordEntry, viewModel: VaultListViewModel, audit: VaultSecurityAudit) {
        self._entry = State(initialValue: entry)
        self.viewModel = viewModel
        self.audit = audit
    }

    /// 当前条目的安全评分
    private var entrySecurityScore: Int {
        audit.entryScores[entry.id] ?? 100
    }

    /// 当前条目的扣分项
    private var entrySecurityIssues: [String] {
        audit.entryIssues[entry.id] ?? []
    }

    private var category: PasswordCategory? {
        viewModel.categories.first { $0.id == entry.categoryID }
    }

    var body: some View {
        List {
            // 头部：站点图标 + 名称 + URL
            headerSection
                .listRowBackground(Color.backgroundFor(domain: entry.siteName))

            // 核心信息：用户名 + 密码
            informationSection

            // OAuth 提供商信息（如果有）
            if entry.oAuthProvider != nil && entry.oAuthProvider?.provider != nil {
                oAuthProviderSection
            }

            // 绑定手机号/邮箱
            if entry.bundleEmailAddress != nil || entry.bundlePhoneNumber != nil {
                bindingInfoSection
            }

            // 双因素认证配置（仅当存在时展示）
            if entry.has2FA {
                twoFactorSection
            }

            // 备注
            if let notes = entry.notes, !notes.isEmpty {
                notesSection
            }

            // 自定义字段
            if !(entry.customFields ?? []).isEmpty {
                customFieldSection
            }

            securitySection

            showOtherInfo
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.horizontal, 16)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.siteName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            /*
            ToolbarItem(placement: .principal) {
                Text(entry.siteName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            */
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPasswordView(entry: entry, viewModel: viewModel)
        }
        .sheet(isPresented: $showingOAuthInfo) {
            ShowOAuthInfoVIew(oauthProvider: entry.oAuthProvider ?? OAuthProviderConfig())
                .presentationDetents([.fraction(0.4), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSecurityIssues) {
            ShowSecurityIssuesView(issues: entrySecurityIssues)
                .presentationDetents([.fraction(0.4), .large])
                .presentationDragIndicator(.visible)
        }
        .preference(key: TabBarVisibilityKey.self, value: true)
        // 编辑页保存后（updatePasswordItem 更新了 items），把本地 entry 刷新为最新数据
        .onChange(of: viewModel.items) { _, _ in
            refreshEntryFromItems()
        }
    }

    /// 从 viewModel.items 中查找当前条目的最新版本并同步到本地 entry
    private func refreshEntryFromItems() {
        let allEntries: [PasswordEntry] = viewModel.items.compactMap { item in
            guard case .password(let entry) = item else { return nil }
            return entry
        }
        guard let latest = allEntries.first(where: { $0.id == entry.id }) else {
            return
        }
        entry = latest
    }

    /// 头部区域：站点图标、名称和可点击的 URL 链接
    private var headerSection: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .center, spacing: 16) {
                // 站点图标（优先本地资源 -> 远程加载 -> 分类默认图标）
                iconView
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)

                // 站点 URL（可点击跳转）
                if let url = entry.siteURL, !url.isEmpty {
                    Link(destination: URL(string: url)!) {
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)

            HStack {
                Text(category?.name ?? "Other")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .symbolRenderingMode(.hierarchical)
                    .background(category?.backgroundColor ?? Color.secondary.opacity(0.12))
                    .foregroundColor(category?.tintColor ?? Color.secondary)
                    .clipShape(Capsule())

                Spacer()

                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 24, height: 24)
                }
            }
        }
    }

    /// 核心信息区：用户名行 + 密码行
    private var informationSection: some View {
        Section {
            // 用户名行：显示并支持复制
            DetailRow(
                title: String(localized: "Username"), value: entry.username, leadingIcon: "person",
                trailingIcon: "doc.on.doc",
                onTap: {
                    copyToClipboard(entry.username)
                })
            // 密码行：可切换明文/密文，支持复制
            VStack(spacing: 12) {
                passwordRow2
                PasswordStrengthIndicator(strength: entry.passwordStrength ?? .medium, isEnabled: !isPasswordEmpty)
                    .padding(.horizontal, 32)
            }

        } header: {
            if let tags = entry.tags, !tags.isEmpty {
                TagListView(tags: tags)
            }
        }
    }
    //.background(Color(.systemBackground))
    // .cornerRadius(16)
    // .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

    private var securitySection: some View {
        let hue = 0.33 * (Double(entrySecurityScore) / 100)
        let scoreColor = Color(hue: hue, saturation: 0.72, brightness: 0.68)

        return Section("Security") {
            VStack {
                HStack {
                    Image(systemName: "flag.pattern.checkered")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Score")
                    Spacer()
                    Text("\(entrySecurityScore)")
                        .fontWeight(.semibold)
                        .foregroundColor(scoreColor)
                    Button {
                        showSecurityIssues = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                    }

                }

                ProgressView(value: Double(entrySecurityScore), total: 100)
                    .tint(scoreColor)
            }
        }
    }

    /// OAuth 提供商信息
    /// 包含 OAuth 绑定值（如果有）
    private var oAuthProviderSection: some View {
        Section("OAuth") {
            DetailRow(
                title: String(localized: "OAuth"), value: entry.oAuthProvider?.boundValue ?? String(localized: "None"),
                leadingIcon: "Custom.Oauth",
                trailingIcon: entry.oAuthProvider?.provider ?? "Custom.Oauth",
                onTap: {
                    showingOAuthInfo = true
                })
        }
    }

    /// 绑定信息
    /// 包含 Email、手机号、OAuth 绑定值（如果有）
    private var bindingInfoSection: some View {
        Section("Binding") {
            // Email 行：显示并支持复制
            if entry.bundleEmailAddress != nil {
                DetailRow(
                    title: String(localized: "Email"),
                    value: entry.bundleEmailAddress ?? String(localized: "None"),
                    leadingIcon: "mail",
                    trailingIcon: entry.isPasswordResetEmail ? "Custom.Recycle" : nil
                )
            }

            // 手机号行：显示并支持复制
            if entry.bundlePhoneNumber != nil {
                DetailRow(
                    title: String(localized: "Phone"),
                    value: entry.bundlePhoneNumber ?? String(localized: "None"),
                    leadingIcon: "phone",
                    trailingIcon: entry.isPasswordResetPhone ? "Custom.Recycle" : nil,
                )
            }

        }
    }

    /// 密码行：显示密码掩码或明文，附带强度指示器、显示/隐藏切换和复制按钮
    private var passwordRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题栏：密码标签 + 强度指示器
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                    //.foregroundColor(.blue)

                    // 密码内容：明文或掩码（最多 12 个圆点）
                    if isPasswordVisible {
                        Text(entry.password)
                            .font(.system(.title3, design: .monospaced))
                    } else {
                        Text(String(repeating: "•", count: min(entry.password.count, 12)))
                            .font(.system(.title2, design: .monospaced))
                    }
                }

                Spacer()

                Button(action: {
                    isPasswordVisible.toggle()
                }) {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundColor(.blue)
                }

                // 复制密码按钮
                Button(action: {
                    copyToClipboard(entry.password)
                }) {
                    Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(showingCopied ? .green : .blue)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Spacer()
                PasswordStrengthIndicator(strength: entry.passwordStrength ?? .medium)
                    .frame(width: 120)
                Spacer()
            }
        }
        //.padding(.top, 16)
    }

    /// 密码行：显示密码掩码或明文，附带强度指示器、显示/隐藏切换和复制按钮
    private var passwordRow2: some View {

        // 标题栏：密码标签 + 强度指示器
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "key.shield")
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 密码内容：明文或掩码（最多 12 个圆点）
                if isPasswordVisible {
                    PasswordText(entry.password)
                        .font(.system(.headline, design: .monospaced))
                        .letterColor(.primary)
                        .digitColor(.green)
                        .symbolColor(.orange)
                    /*
                    Text(entry.password)
                        .font(.system(.headline, design: .monospaced))
                    */
                } else {
                    Text(String(repeating: "•", count: min(entry.password.count, 16)))
                        .font(.system(.headline, design: .monospaced))
                }

            }

            Spacer()

            Button(action: {
                isPasswordVisible.toggle()
                //print("@@@DEBUG: Toggle Password Visible!")
            }) {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundColor(isPasswordEmpty ? Color.secondary : .blue)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 4)
            .disabled(isPasswordEmpty)

            // 复制密码按钮
            Button(action: {
                copyToClipboard(entry.password)
                //print("@@@DEBUG: Copy To Cliboard!")
            }) {
                Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(isPasswordEmpty ? Color.secondary : (showingCopied ? .green : .blue))
            }
            .buttonStyle(.borderless)
            .disabled(isPasswordEmpty)
        }
    }

    /// 双因素认证区域
    /// 遍历所有 twoFactorConfigs，展示每种 2FA 的类型、标签和启用/禁用状态
    private var twoFactorSection: some View {

        Section("2FA") {

            ForEach(entry.twoFactorConfigs ?? [], id: \.type) { config in

                HStack(alignment: .center, spacing: 8) {
                    // 2FA 类型图标（例如 TOTP / SMS）
                    Image(systemName: config.type.icon)
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)

                    // 类型名（如 "TOTP"、"SMS"）
                    Text(config.type.rawValue)
                    //.font(.subheadline)
                    Spacer()

                    if config.type == .totp {
                        TOTPCodeView(config: config)
                    } else {
                        if let boundValue = config.boundValue {
                            Text(boundValue)
                            //.font(.caption)
                            //.foregroundColor(.secondary)
                        }
                        // 启用/禁用状态图标
                        /*
                        Image(systemName: config.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(config.isEnabled ? .green : .red)
                        */
                    }
                }
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 附加信息区域
    /// 按顺序展示：标签、手机号、邮箱、密码找回方式、备注、创建/更新日期
    private var additionalInfoSection: some View {
        //VStack(alignment: .leading, spacing: 12) {
        Section("Additional Info") {
            // 绑定邮箱（仅在非空时展示）
            if let bundleEmail = entry.bundleEmailAddress {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "mail")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)

                    Text("Email")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(bundleEmail)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                //.padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            // 绑定手机号（始终展示，允许为空）
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "phone")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                Text("Phone")
                    //.font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.bundlePhoneNumber ?? "")
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            //.padding()
            .cornerRadius(12)

            HStack(alignment: .center, spacing: 8) {
                Image("Custom.Recycle")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)

                Text("Password Reset")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()

                if entry.isPasswordResetEmail {
                    Image(systemName: "mail")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                }
                if entry.isPasswordResetPhone {
                    Image(systemName: "phone")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                }

            }

            // 数据来源
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: (entry.dataSource ?? .manual).iconName)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                Text("Source")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text((entry.dataSource ?? .manual).displayName)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 标签和备注区域
    private var notesSection: some View {
        Section {
            // 备注信息（仅在非空时展示）
            if let notes = entry.notes, !notes.isEmpty {

                Text(notes)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }
        } header: {
            Text("Notes")
        }
    }

    private var customFieldSection: some View {
        Section {
            ForEach(entry.customFields ?? [], id: \.name) { field in
                //CustomLabel(leadingIcon: "info.circle.fill", text: field.name, value: field.value)
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(field.value)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Custom Fields")
        }
    }

    private var showOtherInfo: some View {
        // 创建和更新日期
        VStack(alignment: .leading, spacing: 2) {
            Text("Data Source: \((entry.dataSource ?? .manual).displayName)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(
                "Created: \((entry.createdAt ?? Date()).formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text(
                "Updated: \((entry.updatedAt ?? Date()).formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 站点图标视图
    /// 显示优先级统一由 IconResolver 决定：内置图标 → 缓存 → 字母图块 → 远程抓取
    /// （entry.icon 非空时视为"用户手动指定的图源"，按该地址精确抓取）
    private var iconView: some View {
        CachedIconView(
            request: IconRequest(
                title: entry.siteName,
                siteURL: entry.siteURL,
                manualIconURL: entry.icon
            ),
            fallbackSystemName: viewModel.category(for: entry.categoryID)?.icon ?? "folder.fill",
            placeholderColor: viewModel.category(for: entry.categoryID)?.tintColor ?? .blue,
            placeholderFont: .largeTitle
        )
    }

    /// 复制文本到系统剪贴板
    /// - 参数 text: 要复制的文本内容
    /// - 副作用: 设置 showingCopied 为 true，2 秒后自动恢复；触发轻量触觉反馈
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        showingCopied = true

        // 2 秒后隐藏"已复制"标识
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopied = false
        }

        // 轻量触觉反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// OAuth 信息视图
    private func showOAuthInfo() {
        if entry.oAuthProvider != nil {
            showingOAuthInfo = true
        }
    }
}

/// 详情行通用组件
/// 用于展示一条"标题-值"型信息行，左侧图标 + 标题/值上下排列，右侧可选复制按钮
struct DetailRow: View {
    /// 行标题（如 "用户名"）
    let title: String
    /// 行内容值（如 "octocat"）
    let value: String
    /// SF Symbol 图标名
    let leadingIcon: String
    /// 右侧图标名（如 "doc.on.doc"）
    let trailingIcon: String?
    /// 复制操作回调，为 nil 时不显示复制按钮
    var onTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧图标
            // 约定：以 Custom 开头的图标名为自定义资源，其余视为 SF Symbol。
            let isSystemIcon = !leadingIcon.hasPrefix("Custom")
            // 根据图标类型加载：系统图标使用Image(systemName:)，自定义图标使用普通Image初始化
            if isSystemIcon {
                Image(systemName: leadingIcon)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                //.font(.title3)
            } else {
                Image(leadingIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)
            }

            // 中间标题和值，上下排列
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.body)
            }

            Spacer()

            // 可选复制按钮
            if let trailingIcon = trailingIcon {
                Button(action: { onTap?() }) {
                    if UIImage(named: trailingIcon) != nil {
                        Image(trailingIcon)
                            .resizable()
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: trailingIcon)
                            //.resizable()
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                    }

                }
            }
        }
    }
}

/// OAuth 信息视图
///
struct ShowOAuthInfoVIew: View {
    @Environment(\.dismiss) private var dismiss
    let oauthProvider: OAuthProviderConfig

    var body: some View {
        List {
            Section("OAuth Info") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider: \(oauthProvider.provider ?? "")")
                    Text("Bound Value: \(oauthProvider.boundValue ?? "")")
                    Text("Enabled: \(oauthProvider.isEnabled ? "Yes" : "No")")
                    //Text("Last Verified At: \(oauthProvider.lastVerifiedAt?.formattedDate(.dateTime) ?? "") ?? "")")
                    Text("Expires At: \(oauthProvider.expiresAt?.formatted(.dateTime) ?? "")")
                    Text("Notes: \(oauthProvider.notes ?? "")")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}

/// 安全问题视图
/// 用于展示密码条目的安全问题，如 "密码包含特殊字符"、"密码长度不足" 等
struct ShowSecurityIssuesView: View {
    @Environment(\.dismiss) private var dismiss
    let issues: [String]

    var body: some View {
        List {
            Section {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle")
                }
            } header: {
                Text("Security Issues")
                    .font(.title3)
            }
        }
        .padding(.vertical, 16)
    }
}

private struct PasswordDetailPreviewContainer: View {
    @StateObject private var viewModel: VaultListViewModel

    private let previewEntries: [PasswordEntry]
    private let previewAudit: VaultSecurityAudit

    init() {
        let referenceData = ReferenceDataService()
        let primaryEntry = PasswordEntry(
            siteName: "GitHub",
            siteURL: "https://github.com",
            username: "octocat@example.com",
            password: "GitHub#2026Dev",
            oAuthProvider: OAuthProviderConfig(
                provider: "Google", boundValue: "octocat@example.com"),
            bundlePhoneNumber: "1861234567890",
            bundleEmailAddress: "octocat@example.com",
            notes: "公司代码托管，已配置 SSH Key",
            categoryID: PasswordCategory.defaultCategoryID,
            tags: ["dev", "code"],
            isFavorite: true,
            isPasswordResetEmail: true,
            isPasswordResetPhone: true,
            has2FA: true,
            customFields: [
                CustomField(name: "Custom Field 1", value: "Value 1"),
                CustomField(name: "Custom Field 2", value: "Value 2"),
            ],
            twoFactorConfigs: [
                TwoFactorConfig(type: .totp, issuer: "GitHub"),
                TwoFactorConfig(type: .sms, issuer: "Github", boundValue: "12710801286"),
            ]
        )
        let reusedEntry = PasswordEntry(
            siteName: "Notion",
            siteURL: "https://notion.so",
            username: "notes@example.com",
            password: "GitHub#2026Dev",
            bundleEmailAddress: "notes@example.com",
            notes: "用于预览安全评分的重复密码样本",
            categoryID: PasswordCategory.defaultCategoryID,
            tags: ["work"],
            has2FA: false,
            breachStatus: .unknown
        )
        let entries = [primaryEntry, reusedEntry]

        _viewModel = StateObject(wrappedValue: VaultListViewModel(referenceData: referenceData))
        previewEntries = entries
        previewAudit = VaultSecurityAuditService().calculate(entries: entries)
    }

    var body: some View {
        NavigationStack {
            PasswordDetailView(
                entry: previewEntries[0],
                viewModel: viewModel,
                audit: previewAudit
            )
        }
        .task {
            viewModel.items = previewEntries.map { .password($0) }
        }
    }
}

/// Xcode 预览
#Preview {
    PasswordDetailPreviewContainer()
}
