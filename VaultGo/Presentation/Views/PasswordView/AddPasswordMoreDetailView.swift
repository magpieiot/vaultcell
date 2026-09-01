/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// AddPasswordMoreDetailView.swift
/// created on: 11/06/2026
/// ------------------------------------------------------------------

import SwiftUI

struct AddPasswordMoreDetailView: View {

    @ObservedObject var formModel: PasswordFormModel
    @ObservedObject var viewModel: VaultListViewModel
    @StateObject private var customFieldModel: CustomFieldModel = CustomFieldModel()
    
    let categories: [PasswordCategory] = PasswordCategory.systemDefaults
    
    @State private var recentEmails: [String] = []
    @State private var recentPhoneNumbers: [String] = []
    @State private var totpFactorConfig: TwoFactorConfig?
    @State private var showingScanner = false
    @State private var scanError: String?
    @State private var currentToast: ToastItem?
    @State private var isSaving = false
    @State private var hasSeededSelectedTags = false
    @State private var isNotesNotEmpty = false
    
    @FocusState private var isFocused: Bool
    @FocusState private var isNotesFocused: Bool

    private let socialColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        Form {
                /// 绑定信息
                bindingInfoSection
                /// 密码恢复信息
                recoveryInfoSection
                /// 2FA 配置信息
                twoFAInfoSection
                /// 分类选择器
                //categorySection
                /// 备注输入框
                notesSection
                /// 标签管理器
                tagsSection
                /// 自定义字段管理器
                customFieldsSection
            }
            .navigationTitle(formModel.siteName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button{
                        // 保存密码
                        savePassword()
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .onAppear {
                recentEmails = UserContactStore.recentEmails()
                recentPhoneNumbers = UserContactStore.recentPhoneNumbers()
                viewModel.tagSelection.inputText = ""
                viewModel.tagSelection.selectedTags = []
                hasSeededSelectedTags = false
                /*
                Task {
                    await viewModel.reloadTags()
                    seedSelectedTagsIfNeeded()
                }
                */
            }
            .onChange(of: viewModel.tags) { _, _ in
                //seedSelectedTagsIfNeeded()
            }
            .onChange(of: customFieldModel.customFields) { _, newValue in
                formModel.customFields = newValue
            }
        .toast($currentToast)
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
    }

    /// 绑定信息
    /// 显示当前密码的绑定信息，包括邮箱、手机号等
    private var bindingInfoSection: some View {
        Section("Binding") {

            HStack (spacing: 12) {
                Image(systemName: "mail")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField(
                    "Email",
                    text: Binding(
                        get: { formModel.bundleEmailAddress ?? "" },
                        set: { formModel.bundleEmailAddress = $0.isEmpty ? nil : $0 }
                    )
                )
                    .focused($isFocused)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.trailing, recentEmails.isEmpty ? 12 : 36)
                    
                
                if !recentEmails.isEmpty {
                    Menu {
                        ForEach(recentEmails, id: \.self) { value in
                            Button(value) {
                                formModel.bundleEmailAddress = value
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                            .padding(.trailing, 12)
                    }
                }
                
            }
            
            /// 手机号输入框
            HStack (spacing: 12) {
                Image(systemName: "phone")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField(
                    "Phone",
                    text: Binding(
                        get: { formModel.bundlePhoneNumber ?? "" },
                        set: { formModel.bundlePhoneNumber = $0.isEmpty ? nil : $0 }
                    )
                )
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.trailing, recentPhoneNumbers.isEmpty ? 12 : 36)
                    //.clipShape(RoundedRectangle(cornerRadius: 12))
                
                if !recentPhoneNumbers.isEmpty {
                    Menu {
                        ForEach(recentPhoneNumbers, id: \.self) { value in
                            Button(value) {
                                formModel.bundlePhoneNumber = value
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                            .padding(.trailing, 12)
                    }
                }
            }
        }
    }

    /// 密码恢复信息
    /// 显示当前密码的密码恢复信息，包括邮箱、手机号等
    private var recoveryInfoSection: some View {
        Section("Password Reset") {
            HStack {
                Image(systemName: "mail")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Toggle("Email", isOn: $formModel.isPasswordResetEmail)
                    .disabled((formModel.bundleEmailAddress ?? "").isEmpty)
            }
            HStack {
                Image(systemName: "phone")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Toggle("Phone", isOn: $formModel.isPasswordResetPhone)
                    .disabled((formModel.bundlePhoneNumber ?? "").isEmpty)
            }
        }
    }

    /// 显示当前密码的 2FA 配置信息，包括 TOTP、硬件密钥等
    private var twoFAInfoSection: some View {
        Section {
            /// TOTP 2FA
            HStack {
                Image(systemName: "lock")
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
                }
            }

            /// 显示其他 2FA
            ForEach(formModel.twoFactorConfigs ?? [], id: \.type) { config in
                //Label(config.type.rawValue, systemImage: config.type.icon)
                HStack{
                    Image(systemName: config.type.icon)
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text(config.type.rawValue)
                    Spacer()
                    Text(config.boundValue ?? "")
                    Button {
                        // 点击按钮删除此配置
                        if let index = formModel.twoFactorConfigs?.firstIndex(where: { $0.id == config.id }) {
                            formModel.twoFactorConfigs?.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                }
            }

        } header: {
            Text("2FA")
        } footer: {
            Menu {
                ForEach(TwoFactorType.allCases, id: \.self) { type in
                    if type != .totp {
                        //Text(type.rawValue).tag(type)
                        Button {
                            var config = TwoFactorConfig(type: type, createdAt: Date(), expiresAt: Date())
                            
                            switch type {
                                case .email:
                                    config.boundValue = formModel.bundleEmailAddress
                                case .sms:
                                    config.boundValue = formModel.bundlePhoneNumber
                                case .hardware:
                                    config.boundValue = "Hardware Key"
                                case .push:
                                    config.boundValue = "Push Code To Device"
                                default:
                                    config.boundValue = ""
                            }
                            // 添加到数组
                            formModel.twoFactorConfigs?.append(config)

                        } label: {
                            Label(type.rawValue, systemImage: type.icon)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Add New")
                    Spacer()
                }
            }
        }
    }

    /// 分类选择器
    /// 显示当前密码的分类选择器，包括所有分类
    private var categorySection: some View {
        /// 分类
        Section {
            Picker(selection: $formModel.categoryID) {
                ForEach(categories, id: \.id) { category in
                    Text(category.name).tag(category.id)
                }
            } label: {
                HStack(alignment: .center, spacing: 12){
                    Image(systemName: "folder")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Category")
                }       
            }
            //.padding(.horizontal, 12)

            Toggle(isOn: $formModel.isFavorite) {
                HStack(alignment: .center, spacing: 12){
                    Image(systemName: "heart.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Favorite")
                }
            }
        }
    }

    /// 备注输入框
    /// 显示当前密码的备注输入框，用于输入额外信息
    private var notesSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if !isNotesNotEmpty && !isNotesFocused {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        Text("Add Notes")
                            .foregroundColor(.secondary)
                    }
                }

                TextEditor(
                    text: Binding(
                        get: { formModel.notes ?? "" },
                        set: { formModel.notes = $0.isEmpty ? nil : $0 }
                    )
                )
                    .focused($isNotesFocused)
                    .multilineTextAlignment(.leading)
                    .onChange(of: formModel.notes) { oldValue, newValue in
                        if !(newValue ?? "").isEmpty {
                            isNotesNotEmpty = true
                        } else {
                            isNotesNotEmpty = false
                        }
                    }
                    //.padding(.horizontal, 12)
            }
        } header: {
            Text("Notes")
        } footer: {
            Text("Add notes. Click to add new ones.")
                .font(.caption)
        }
    }

    /// Tags 区：标签
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


    /// 自定义字段管理器
    /// 显示当前密码的自定义字段管理器，用于添加额外的字段
    /// 每个字段包含名称和值
    private var customFieldsSection: some View {
        Section {
            CustomFieldManager(model: customFieldModel)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            
        } header: {
            Text("Custom Fields")
        } footer: {
            Text("Add custom fields. Click to add new ones.")
                .font(.caption)
        }
    }

    /// 从VaultItem模型中填充选中的标签
    /// 如果标签选择器未被填充，从密码模型中获取标签并填充到选择器中
    /*
    private func seedSelectedTagsIfNeeded() {
        guard !hasSeededSelectedTags else { return }

        //viewModel.tagSelection.seedSelectedTags(with: formModel.tags ?? [])
        viewModel.tagSelection.suggestedTags = formModel.tags ?? []
        hasSeededSelectedTags = true
    }
    */

    /// 处理扫描结果
    /// 解析扫描到的二维码，更新 TOTP 配置
    private func handleScanResult(_ code: String) {
        totpFactorConfig = TwoFactorConfig(type: .totp)
        /// 解析 TOTP 密钥
        if let result = TOTPService.shared.parseOTPAuthURI(code) {
            //is2FAbyTOTP = true
            /// 解析成功，更新 TOTP 配置
            /// 1. 从解析结果中提取密钥、发行方、账户
            /// 2. 更新 TOTP 配置
            
            totpFactorConfig?.secret = result.config.secret
            totpFactorConfig?.issuer = result.issuer ?? ""
            totpFactorConfig?.boundValue = result.account ?? ""
            totpFactorConfig?.isEnabled = true
            totpFactorConfig?.createdAt = Date()
            totpFactorConfig?.lastVerifiedAt = Date()
            showingScanner = false
            currentToast = ToastItem(message: String(localized: "TOTP secret recognized"), style: .success)
        } else if !code.isEmpty {
            //is2FAbyTOTP = true
            totpFactorConfig?.secret = code
            totpFactorConfig?.issuer = formModel.siteName
            totpFactorConfig?.boundValue = formModel.username
            showingScanner = false
            currentToast = ToastItem(message: String(localized: "TOTP secret recognized"), style: .success)
        } else {
            showingScanner = false
            currentToast = ToastItem(message: String(localized: "Unable to recognize QR code"), style: .error)
        }
    }

    private func savePassword() {
        guard !isSaving else { return }

        formModel.tagSelection = viewModel.tagSelection.selectedTags.map(\.name)
        formModel.has2FA = totpFactorConfig?.secret != nil || !(formModel.twoFactorConfigs ?? []).isEmpty
        formModel.customFields = customFieldModel.customFields

        var entry = formModel.buildDraftEntry()

        // Merge TOTP config into twoFactorConfigs
        var allTwoFactorConfigs = entry.twoFactorConfigs ?? []
        allTwoFactorConfigs.removeAll { $0.type == .totp }
        if let config = totpFactorConfig {
            allTwoFactorConfigs.append(config)
        }
        entry.twoFactorConfigs = allTwoFactorConfigs.isEmpty ? nil : allTwoFactorConfigs
        entry.has2FA = !allTwoFactorConfigs.isEmpty

        isSaving = true

        Task {
            defer { isSaving = false }
            do {
                let service = PasswordVaultService()
                try await service.addPasswordOrThrow(entry)

                UserContactStore.addEmail(entry.bundleEmailAddress)
                UserContactStore.addPhoneNumber(entry.bundlePhoneNumber)
                TagStore.addTags(entry.tags ?? [])

                toastCenter.toast = ToastItem(message: "Password saved successfully", style: .success)
                // 刷新列表数据（此处 service 是新实例，不会自动同步到 viewModel）
                await viewModel.loadItems()
                // 关闭整个新增流程，直接返回列表页
                viewModel.isPresentingAddFlow = false
            } catch {
                currentToast = ToastItem(message: error.localizedDescription, style: .error)
            }
        }
    }
}

/// 预览 AddPasswordMoreDetailView

#Preview {
    @Previewable @State var formModel = PasswordFormModel()
    let referenceDataService = ReferenceDataService()
    AddPasswordMoreDetailView(formModel: formModel, viewModel: VaultListViewModel(referenceData: referenceDataService))
}
