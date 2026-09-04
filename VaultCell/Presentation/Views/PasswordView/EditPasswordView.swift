//
//  EditPasswordView.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/9.
//
import SwiftUI

/// 编辑密码视图
/// 以表单形式提供对密码条目的编辑功能，支持修改基本信息、密码、分类、标签、备注和收藏状态
struct EditPasswordView: View {

    /// 原始条目（用于保留 id、历史记录等不可变/需继承字段）
    let entry: PasswordEntry
    /// 父级 ViewModel，用于提交更新
    @ObservedObject var viewModel: VaultListViewModel

    /// 承载编辑状态的表单模型
    @StateObject private var formModel: PasswordFormModel
    @StateObject private var customFieldModel: CustomFieldModel

    /// TOTP 配置独立管理，便于扫码/重新扫描
    @State private var totpFactorConfig: TwoFactorConfig?
    /// 密码输入框是否显示明文
    @State private var isPasswordVisible = false
    ///
    @State private var isShowRescanQrcode = false
    /// 2FA 扫描器是否显示
    @State private var showingScanner = false
    @State private var scanError: String?
    @State private var currentToast: ToastItem?
    /// 是否备注输入框有内容
    @State private var isNotesNotEmpty = false
    /// 是否备注输入框有焦点
    @FocusState private var isNotesFocused: Bool
    /// 是否已将当前条目的 tags 同步到 SmartTagManager
    @State private var hasSeededSelectedTags = false
    /// OAuth 删除模式：点击 minus 后激活，内容左移并显示 Delete 按钮
    @State private var isOAuthDeleteModeActive = false
    /// 是否显示 OAuth Provider 选择 sheet
    @State private var showingOAuthProviderPicker = false
    /// 外部焦点：用于将焦点设置到 Email AdvancedTextField
    @FocusState private var isEmailFocused: Bool
    /// 最近使用的邮箱和号码历史列表（从 UserDefaults 读取，供下拉补全）
    @State private var recentEmails: [String] = []
    @State private var recentPhoneNumbers: [String] = []
    /// 是否显示删除确认弹窗
    @State private var showDeleteConfirmation = false

    /// 用于关闭当前 sheet 的环境变量
    @Environment(\.dismiss) private var dismiss

    /// 初始化编辑视图，将条目数据回填到 PasswordFormModel
    init(entry: PasswordEntry, viewModel: VaultListViewModel) {
        self.entry = entry
        self.viewModel = viewModel

        _formModel = StateObject(
            wrappedValue: {
                let model = PasswordFormModel()
                model.siteName = entry.siteName
                model.siteURL = entry.siteURL
                model.username = entry.username
                model.password = entry.password
                model.bundleEmailAddress = entry.bundleEmailAddress
                model.bundlePhoneNumber = entry.bundlePhoneNumber
                model.notes = entry.notes
                model.icon = entry.icon
                model.categoryID = entry.categoryID
                model.tagSelection = entry.tags
                model.isFavorite = entry.isFavorite
                model.isPasswordResetEmail = entry.isPasswordResetEmail
                model.isPasswordResetPhone = entry.isPasswordResetPhone
                model.has2FA = entry.has2FA
                model.twoFactorConfigs = entry.twoFactorConfigs?.filter { $0.type != .totp }
                model.oAuthProvider = entry.oAuthProvider
                model.customFields = entry.customFields
                return model
            }())

        let totp = entry.twoFactorConfigs?.first { $0.type == .totp }
        _totpFactorConfig = State(initialValue: totp)
        _customFieldModel = StateObject(
            wrappedValue: CustomFieldModel(customFields: entry.customFields ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                userInfoSection
                oAuthProviderSection
                bindingInfoSection
                if !(formModel.bundleEmailAddress ?? "").isEmpty
                    || !(formModel.bundlePhoneNumber ?? "").isEmpty
                {
                    passwordResetSection
                }
                twoFAInfoSection
                notesSection
                tagsSection
                customFieldSection
                deleteSection
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        savePassword()
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 28, height: 28)
                    }
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                QRCodeScannerView(
                    onScan: { code in
                        handleScanResult(code)
                    },
                    onError: { error in
                        scanError = error.localizedDescription
                        showingScanner = false
                        currentToast = ToastItem(message: error.localizedDescription, style: .error)
                    },
                    onCancel: {
                        showingScanner = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingOAuthProviderPicker) {
            oauthProviderPickerSheet
        }
        .onAppear {
            seedSelectedTagsIfNeeded()
            recentEmails = UserContactStore.recentEmails()
            recentPhoneNumbers = UserContactStore.recentPhoneNumbers()
        }
        .onChange(of: viewModel.tags) { _, _ in
            seedSelectedTagsIfNeeded()
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section {
            AdvancedTextField(
                iconName: "magnifyingglass",
                iconColor: .blue,
                title: String(localized: "Title"),
                keyboardType: .default,
                text: $formModel.siteName
            )

            AdvancedTextField(
                iconName: "link",
                iconColor: .blue,
                title: String(localized: "URL"),
                keyboardType: .URL,
                text: Binding(
                    get: { formModel.siteURL ?? "" },
                    set: { formModel.siteURL = $0.isEmpty ? nil : $0 }
                )
            )

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                Picker("Category", selection: $formModel.categoryID) {
                    ForEach(viewModel.categories) { cat in
                        Text(cat.name).tag(cat.id)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "star")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Toggle("Favorite", isOn: $formModel.isFavorite)
            }
        }
    }

    private var userInfoSection: some View {
        Section {
            AdvancedTextField(
                iconName: "person",
                iconColor: .blue,
                title: String(localized: "Username"),
                keyboardType: .asciiCapable,
                text: $formModel.username
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)

                HStack(alignment: .center, spacing: 8) {
                    if isPasswordVisible {
                        TextField("Password", text: $formModel.password)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Password", text: $formModel.password)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.asciiCapable)
                    }

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                            .foregroundColor(.secondary)
                    }
                }
                .textFieldStyle(LeadingIconTextFieldStyle(systemName: "lock"))
                .padding(.bottom, 12)

                if !formModel.password.isEmpty {
                    PasswordStrengthIndicator(
                        strength: PasswordStrength.calculate(for: formModel.password)
                    )
                    .padding(.horizontal, 32)
                }
            }
        }
    }

    private var oAuthProviderSection: some View {
        Section {
            // 仅当存在 OAuth 绑定时显示内容行；删除后隐藏
            if formModel.oAuthProvider != nil {
                HStack(spacing: 8) {
                    // 左侧 minus 按钮：仅当未激活删除模式时显示
                    if !isOAuthDeleteModeActive {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isOAuthDeleteModeActive = true
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.body.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.red))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        // 删除模式下点击内容区：仅退出删除模式，恢复原状
                        if isOAuthDeleteModeActive {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isOAuthDeleteModeActive = false
                            }
                            return
                        }
                        // 正常点击：打开 OAuth Provider 选择 sheet，可更换绑定
                        showingOAuthProviderPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)

                            Text(formModel.oAuthProvider?.boundValue ?? "")
                                .font(.body)

                            Spacer()

                            Image(formModel.oAuthProvider?.provider ?? "")
                                .resizable()
                                .frame(width: 24, height: 24)

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 右侧 Delete 按钮：删除模式激活后显示，点击执行 onDeleteOAuth
                    if isOAuthDeleteModeActive {
                        Button(action: onDeleteOAuth) {
                            Text("Delete")
                                .font(.body.weight(.regular))
                                .foregroundColor(.white)
                                .frame(width: 76, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red))
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // 删除模式下点击其他区域：退出删除模式，恢复原状
                    if isOAuthDeleteModeActive {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isOAuthDeleteModeActive = false
                        }
                    }
                }
            }
        } header: {
            Text("OAuth")
        } footer: {
            // 无 OAuth 绑定时提供新增入口
            if formModel.oAuthProvider == nil {
                Button {
                    showingOAuthProviderPicker = true
                } label: {
                    addNewLable
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var bindingInfoSection: some View {
        Section {
            if formModel.bundleEmailAddress != nil {
                AdvancedTextField(
                    iconName: "mail",
                    iconColor: .blue,
                    title: String(localized: "Email"),
                    keyboardType: .emailAddress,
                    isItemDeleteEnabled: true,
                    onDeleteItem: {
                        print("delete email")
                        formModel.bundleEmailAddress = nil
                        formModel.isPasswordResetEmail = false
                    },
                    trailingAccessory: recentEmails.isEmpty
                        ? nil
                        : {
                            AnyView(
                                recentSuggestionsMenu(
                                    values: recentEmails,
                                    onSelect: {
                                        formModel.bundleEmailAddress = $0
                                    }))
                        },
                    text: Binding(
                        get: { formModel.bundleEmailAddress ?? "" },
                        set: { formModel.bundleEmailAddress = $0 }
                    ),
                    externalFocus: $isEmailFocused
                )

            }

            if formModel.bundlePhoneNumber != nil {
                AdvancedTextField(
                    iconName: "phone",
                    iconColor: .blue,
                    title: String(localized: "Phone"),
                    keyboardType: .numberPad,
                    isItemDeleteEnabled: true,
                    onDeleteItem: {
                        print("delete phone")
                        formModel.bundlePhoneNumber = nil
                        formModel.isPasswordResetPhone = false
                    },
                    trailingAccessory: recentPhoneNumbers.isEmpty
                        ? nil
                        : {
                            AnyView(
                                recentSuggestionsMenu(
                                    values: recentPhoneNumbers,
                                    onSelect: {
                                        formModel.bundlePhoneNumber = $0
                                    }))
                        },
                    text: Binding(
                        get: { formModel.bundlePhoneNumber ?? "" },
                        set: { formModel.bundlePhoneNumber = $0 }
                    )
                )
            }
        } header: {
            Text("Binding")
        } footer: {
            if formModel.bundlePhoneNumber == nil && formModel.bundleEmailAddress == nil {
                Menu {
                    Button {
                        formModel.bundleEmailAddress = ""
                        // 延迟到下一个 RunLoop 确保 AdvancedTextField 已渲染，再设置焦点
                        DispatchQueue.main.async { isEmailFocused = true }
                    } label: {
                        HStack {
                            Image(systemName: "mail")
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)
                            Text("Email")
                            Spacer()
                        }
                    }

                    Button {
                        formModel.bundlePhoneNumber = ""
                    } label: {
                        HStack {
                            Image(systemName: "phone")
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)
                            Text("Phone")
                            Spacer()
                        }
                    }
                } label: {
                    addNewLable
                        .padding(.bottom, 12)
                }
            }

            if formModel.bundleEmailAddress == nil {
                Button {
                    formModel.bundleEmailAddress = ""
                    DispatchQueue.main.async { isEmailFocused = true }
                } label: {
                    addNewLable
                        .padding(.bottom, 12)
                }
            }

            if formModel.bundlePhoneNumber == nil {
                Button {
                    formModel.bundlePhoneNumber = ""
                } label: {
                    addNewLable
                        .padding(.bottom, 12)
                }
            }
        }
    }

    ///
    private var passwordResetSection: some View {
        Section("Password Reset") {
            if !(formModel.bundleEmailAddress ?? "").isEmpty {
                Toggle(isOn: $formModel.isPasswordResetEmail) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "mail")
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        Text("By Email")
                    }
                }
            }

            if !(formModel.bundlePhoneNumber ?? "").isEmpty {
                Toggle(isOn: $formModel.isPasswordResetPhone) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "phone")
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        Text("By Phone")
                    }
                }
            }
        }
    }

    /// TOTP 相关
    private var twoFAInfoSection: some View {

        Section {
            HStack {
                ///
                if !isShowRescanQrcode && totpFactorConfig?.secret != nil {
                    minusButton
                }

                Image(systemName: "key.viewfinder")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                Text("TOTP")
                Spacer()
                if totpFactorConfig?.secret == nil {
                    Button {
                        showingScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text(totpFactorConfig?.secret == nil ? "Scan QR Code" : "Rescan")
                        }
                    }
                } else {
                    TOTPCodeView(config: totpFactorConfig!)
                    if isShowRescanQrcode {
                        //@@
                        rescanQrcodeButton
                    }
                }

            }
            .padding(.leading, isShowRescanQrcode ? -64 : 0)
            // 点击 Rescan 按钮左侧区域时收起 Rescan 按钮（不触发扫码）
            .contentShape(Rectangle())
            .onTapGesture {
                guard isShowRescanQrcode else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isShowRescanQrcode = false
                }
            }

            ForEach(Array((formModel.twoFactorConfigs ?? []).enumerated()), id: \.element.id) {
                index, config in
                AdvancedTextField(
                    iconName: config.type.icon,
                    iconColor: .blue,
                    title: config.type.rawValue,
                    isItemDeleteEnabled: true,
                    onDeleteItem: {
                        formModel.twoFactorConfigs?.remove(at: index)
                    },
                    text: Binding(
                        get: { config.boundValue ?? "" },
                        set: {
                            formModel.twoFactorConfigs?[index].boundValue = $0
                        }
                    )
                )

            }
        } header: {
            Text("Two-Factor Authentication")
        } footer: {
            Menu {
                ForEach(TwoFactorType.allCases, id: \.self) { type in
                    if type == .totp || ((type == .sms) && (formModel.bundlePhoneNumber == nil))
                        || ((type == .email) && (formModel.bundleEmailAddress == nil))
                    {

                    } else {
                        Button {
                            var config = TwoFactorConfig(
                                type: type, createdAt: Date(), expiresAt: Date())

                            switch type {
                            case .email:
                                config.boundValue = formModel.bundleEmailAddress
                            case .sms:
                                config.boundValue = formModel.bundlePhoneNumber
                            case .hardware:
                                config.boundValue = "Hardware Key"
                            case .push:
                                config.boundValue = "Device Name"
                            default:
                                break
                            }

                            formModel.twoFactorConfigs?.append(config)
                        } label: {
                            Label(type.rawValue, systemImage: type.icon)
                        }
                    }
                }
            } label: {
                addNewLable
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            ZStack(alignment: .topLeading) {
                if !isNotesNotEmpty && !isNotesFocused {
                    addNewLable
                }

                TextEditor(
                    text: Binding(
                        get: { formModel.notes ?? "" },
                        set: { formModel.notes = $0.isEmpty ? nil : $0 }
                    )
                )
                .focused($isNotesFocused)
                .multilineTextAlignment(.leading)
                .onChange(of: formModel.notes) { _, newValue in
                    isNotesNotEmpty = !(newValue ?? "").isEmpty
                }
            }
        }
        .onAppear {
            isNotesNotEmpty = !(formModel.notes ?? "").isEmpty
        }
    }

    private var tagsSection: some View {
        Section {
            SmartTagManager(viewModel: viewModel.tagSelection)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Tags")
        } footer: {
            Text("Add tags. Click to pick existing ones, or type & press Enter to create new.")
                .font(.caption)
        }
    }

    // MARK: - Custom Fields
    private var customFieldSection: some View {
        Section {
            CustomFieldManager(model: customFieldModel)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(model: customFieldModel)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Move to Trash")
                    Spacer()
                }
            }
            .alert("Move to Trash?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Move to Trash", role: .destructive) {
                    Task { await softDelete() }
                }
            } message: {
                Text("This item will be moved to the Trash and kept for 30 days.")
            }
        }
    }

    // MARK: - Rescan QRCode

    private var minusButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowRescanQrcode = true
                //setFocus(false)
            }
        } label: {
            Image(systemName: "minus")
                .font(.body.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    private var rescanQrcodeButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowRescanQrcode = false
            }
            showingScanner = true
        }) {
            Label("Rescan", systemImage: "qrcode.viewfinder")

                .font(.body.weight(.regular))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Helpers

    /// 删除 OAuth 绑定：清除 formModel 中的 oAuthProvider 并退出删除模式
    private func onDeleteOAuth() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isOAuthDeleteModeActive = false
        }
        formModel.oAuthProvider = nil
    }

    /// 潜在的 OAuth Provider 条目
    /// 从密码库中筛选出 siteName 命中已知 OAuth Provider 列表的条目（与 AddPasswordDetailView 逻辑一致）
    /// 并排除当前已选中的绑定（providerID 即来源条目的 id）
    private var oauthRelatedEntries: [PasswordEntry] {
        let normalizedProviders = oauthProviders.map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return viewModel.passwordEntriesForAudit.filter { entry in
            guard entry.id != formModel.oAuthProvider?.providerID else { return false }
            return normalizedProviders.contains(
                entry.siteName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// OAuth Provider 选择 sheet
    /// 列出所有潜在的 OAuth Provider 条目，点击其中一个即设置为当前 OAuth 绑定并关闭 sheet
    private var oauthProviderPickerSheet: some View {
        NavigationStack {
            List {
                if oauthRelatedEntries.isEmpty {
                    Text("No OAuth-related accounts found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(oauthRelatedEntries) { entry in
                        Button {
                            formModel.oAuthProvider = OAuthProviderConfig(
                                providerID: entry.id,
                                provider: entry.siteName,
                                boundValue: entry.username
                            )
                            showingOAuthProviderPicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(entry.siteName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)

                                Text(entry.siteName)
                                    .font(.body)

                                Spacer()

                                Text(entry.username)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose OAuth Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingOAuthProviderPicker = false
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                }
            }
        }
    }

    /// 最近输入项下拉补全菜单（复用于 Email / Phone）
    @ViewBuilder
    private func recentSuggestionsMenu(values: [String], onSelect: @escaping (String) -> Void)
        -> some View
    {
        Menu {
            ForEach(values, id: \.self) { value in
                Button(value) { onSelect(value) }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    private func handleScanResult(_ code: String) {
        totpFactorConfig = TwoFactorConfig(type: .totp)

        if let result = TOTPService.shared.parseOTPAuthURI(code) {
            totpFactorConfig?.secret = result.config.secret
            totpFactorConfig?.issuer = result.issuer ?? ""
            totpFactorConfig?.boundValue = result.account ?? ""
            totpFactorConfig?.isEnabled = true
            totpFactorConfig?.createdAt = Date()
            totpFactorConfig?.lastVerifiedAt = Date()
            showingScanner = false
            currentToast = ToastItem(message: String(localized: "TOTP key detected"), style: .success)
        } else if !code.isEmpty {
            totpFactorConfig?.secret = code
            totpFactorConfig?.issuer = formModel.siteName
            totpFactorConfig?.boundValue = formModel.username
            showingScanner = false
            currentToast = ToastItem(message: String(localized: "TOTP key detected"), style: .success)
        } else {
            showingScanner = false
            currentToast = ToastItem(message: String(localized: "Unable to recognize QR code"), style: .error)
        }
    }

    private func seedSelectedTagsIfNeeded() {
        guard !hasSeededSelectedTags else { return }
        viewModel.tagSelection.seedSelectedTags(with: entry.tags ?? [])
        hasSeededSelectedTags = true
    }

    private func savePassword() {
        let trimmedSiteURL = (formModel.siteURL ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let trimmedEmail = (formModel.bundleEmailAddress ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let trimmedPhone = (formModel.bundlePhoneNumber ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let trimmedNotes = (formModel.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var updatedEntry = entry
        updatedEntry.siteName = formModel.siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedEntry.siteURL = trimmedSiteURL.isEmpty ? nil : trimmedSiteURL
        updatedEntry.username = formModel.username.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedEntry.bundleEmailAddress = trimmedEmail.isEmpty ? nil : trimmedEmail
        updatedEntry.bundlePhoneNumber = trimmedPhone.isEmpty ? nil : trimmedPhone
        updatedEntry.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        updatedEntry.categoryID = formModel.categoryID
        updatedEntry.isFavorite = formModel.isFavorite
        updatedEntry.isPasswordResetEmail = formModel.isPasswordResetEmail
        updatedEntry.isPasswordResetPhone = formModel.isPasswordResetPhone
        updatedEntry.oAuthProvider = formModel.oAuthProvider
        updatedEntry.customFields =
            customFieldModel.customFields.isEmpty ? nil : customFieldModel.customFields
        updatedEntry.tags = viewModel.tagSelection.selectedTags.map(\.name)
        updatedEntry.updatedAt = Date()

        if formModel.password != entry.password {
            updatedEntry.updatePassword(formModel.password)
        }

        var allTwoFactorConfigs = (formModel.twoFactorConfigs ?? []).filter { $0.type != .totp }
        if let totp = totpFactorConfig {
            allTwoFactorConfigs.append(totp)
        }
        updatedEntry.twoFactorConfigs = allTwoFactorConfigs.isEmpty ? nil : allTwoFactorConfigs
        updatedEntry.has2FA = !allTwoFactorConfigs.isEmpty

        Task {
            UserContactStore.addEmail(updatedEntry.bundleEmailAddress)
            UserContactStore.addPhoneNumber(updatedEntry.bundlePhoneNumber)
            TagStore.addTags(updatedEntry.tags ?? [])
            await viewModel.updatePasswordItem(updatedEntry)
            dismiss()
        }
    }

    /// 软删除：将当前条目移入回收站（保留 30 天），成功后关闭编辑页
    private func softDelete() async {
        await viewModel.deletePasswordItem(entry)
        await MainActor.run { dismiss() }
    }

    private var addNewLable: some View {
        HStack {
            Image(systemName: "plus")
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            Text("Add New")
            Spacer()
        }
    }
}
