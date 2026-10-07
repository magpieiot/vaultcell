//
//  AddBankcardItemView.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/25.
//

import SwiftUI

enum BankCardNetwork: String, CaseIterable {
    case visa = "Visa"
    case mastercard = "Mastercard"
    case amex = "American Express"
    case discover = "Discover"
    case jcb = "JCB"
    case unionPay = "UnionPay"

    var iconName: String {
        switch self {
            case .visa: return "visa"
            case .mastercard: return "mastercard"
            case .amex: return "americanexpress"
            case .discover: return "discover"
            case .jcb: return "jcb"
            case .unionPay: return "unionpay"
        }
    }

    var iconColor: Color {
        switch self {
            case .visa: return .blue
            case .mastercard: return .red
            case .amex: return .orange
            case .discover: return .purple
            case .jcb: return .green
            case .unionPay: return .yellow
        }
    }

    var cardFaceColor: Color {
        switch self {
            case .visa, .mastercard, .amex, .discover, .jcb, .unionPay: return .white
            //default: return .black
        }
    }

    /// Asset catalog 中对应的图标资源名（注意 amex 的资源名为 "amex"）
    var assetName: String {
        switch self {
            case .visa: return "visa"
            case .mastercard: return "mastercard"
            case .amex: return "amex"
            case .discover: return "discover"
            case .jcb: return "jcb"
            case .unionPay: return "unionpay"
        }
    }

    /// 卡片面背景渐变色（基于品牌 logo 主色设计：深色底 + 品牌色高光，
    /// 保证白色文字与 logo 清晰可见，营造高级质感）
    var faceBackgroundColors: [Color] {
        switch self {
            // Visa: #0E4595 蓝 + #F2AE14 金 → 深海蓝渐变
            case .visa:
                return [
                    Color(red: 0.02, green: 0.07, blue: 0.15),   // #061226
                    Color(red: 0.05, green: 0.27, blue: 0.58),   // #0E4595
                    Color(red: 0.18, green: 0.50, blue: 0.82)    // 提亮蓝
                ]
            // Mastercard: #EB001B 红 + #F79E1B 橙 → 酒红橙渐变
            case .mastercard:
                return [
                    Color(red: 0.17, green: 0.02, blue: 0.06),   // #2B0410
                    Color(red: 0.92, green: 0.00, blue: 0.11),   // #EB001B
                    Color(red: 0.97, green: 0.62, blue: 0.11)    // #F79E1B
                ]
            // Amex: #006FCF 蓝 → 深海蓝渐变
            case .amex:
                return [
                    Color(red: 0.00, green: 0.16, blue: 0.30),   // #00284D
                    Color(red: 0.00, green: 0.44, blue: 0.81)    // #006FCF
                ]
            // Discover: logo 自带 #99291E → #E4521D → #F59314 橙红渐变
            case .discover:
                return [
                    Color(red: 0.60, green: 0.16, blue: 0.12),   // #99291E
                    Color(red: 0.89, green: 0.32, blue: 0.11),   // #E4521D
                    Color(red: 0.96, green: 0.58, blue: 0.08)    // #F59314
                ]
            // JCB: 蓝 #0066B1 + 绿 #00873F（三色标志中取蓝→绿）
            case .jcb:
                return [
                    Color(red: 0.06, green: 0.10, blue: 0.25),   // #101A3F
                    Color(red: 0.00, green: 0.40, blue: 0.69),   // #0066B1
                    Color(red: 0.00, green: 0.53, blue: 0.25)    // #00873F
                ]
            // UnionPay: #022E64 深蓝 + #D10429 红 → 藏蓝红渐变
            case .unionPay:
                return [
                    Color(red: 0.00, green: 0.09, blue: 0.19),   // #011730
                    Color(red: 0.01, green: 0.18, blue: 0.39),   // #022E64
                    Color(red: 0.82, green: 0.02, blue: 0.16)    // #D10429
                ]
        }
    }

    /// 根据网络名称字符串（大小写不敏感、忽略首尾空白）解析对应的枚举 case
    static func from(_ string: String) -> BankCardNetwork? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first {
            $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}

/// 新增/编辑银行卡的统一表单视图
struct AddBankcardView: View {
    @ObservedObject var formModel: BankcardFormModel
    var onSave: (BankcardEntry) async throws -> Void
    var onSoftDelete: ((BankcardEntry) async throws -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    /// 自定义字段「有值但缺名称」时是否显示阻止保存提示
    @State private var showFieldNameRequiredPrompt = false

    private var isEditMode: Bool {
        if case .edit = formModel.mode { return true }
        return false
    }

    var body: some View {
        Group {
            if isEditMode {
                NavigationStack {
                    formContent
                        .navigationTitle("Edit Bank Card")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { editToolbar }
                }
            } else {
                formContent
            }
        }
        .customFieldNameRequiredAlert(isPresented: $showFieldNameRequiredPrompt)
    }

    private var formContent: some View {
        Form {
            cardInfoSection
            securitySection
            extraInfoSection
            notesSection
            tagsSection
            customFieldSection
            if isEditMode {
                deleteSection
            }
        }
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
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
                Task { await save() }
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 28, height: 28)
            }
            .disabled(!formModel.isEnabledNextButton || isSaving)
        }
    }

    // MARK: - Card Info

    private var cardInfoSection: some View {
        Section {
            // Bank Name
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Bank Name", text: $formModel.bankName)
                    .autocorrectionDisabled()
            }

            // Card Number
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Card Number", text: $formModel.cardNumber)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
            }

            // Cardholder
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Card holder", text: $formModel.cardholder)
                    .autocorrectionDisabled()
            }

            // Expiry Date (MM/YY)
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Expiry Date (MM/YY)", text: $formModel.expiryDate)
                    .autocorrectionDisabled()
            }

            // Card Type
            Picker(selection: $formModel.cardType) {
                ForEach(CardType.allCases, id: \.self) { type in
                    Text(cardTypeDisplayName(type)).tag(type)
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "creditcard")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Card Type")
                }
            }
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section {
            // CVV
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                SecureField("CVV", text: $formModel.cvv)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
            }

            // PIN (digits only)
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                SecureField("PIN (digits only)", text: $formModel.pin)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
            }

            // Online Banking Password
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                SecureField("Online Banking Password", text: $formModel.onlineBankingPassword)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Security")
        } footer: {
            Text("PIN must be digits only.")
                .font(.caption)
        }
    }

    // MARK: - Extra Info

    private var extraInfoSection: some View {
        Section {
            // Issuing Channel
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Issuing Channel", text: $formModel.issuingChannel)
                    .autocorrectionDisabled()
            }

            // Card Networks
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Card Networks (comma separated)", text: $formModel.cardNetworksText)
                    .autocorrectionDisabled()

                Menu {
                    ForEach(BankCardNetwork.allCases, id: \.self) { network in
                        Button {
                            appendCardNetwork(network)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(network.iconColor)
                                    .frame(width: 10, height: 10)
                                Text(network.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.blue)
                }
            }

            // Category
            Picker(selection: $formModel.selectedCategoryID) {
                ForEach(formModel.categories, id: \.id) { category in
                    Text(category.name).tag(category.id)
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Category")
                }
            }

            // Favorite
            Toggle(isOn: $formModel.isFavorite) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Favorite")
                }
            }
        } header: {
            Text("Extra Info")
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        NotesSectionView(text: $formModel.notes, iconColor: .blue)
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section {
            SmartTagManager(viewModel: formModel.tagSelection)
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
            CustomFieldSection(customFields: $formModel.customFields)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(customFields: $formModel.customFields)
        }
    }

    // MARK: - Soft Delete

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

    // MARK: - Helpers

    private func appendCardNetwork(_ network: BankCardNetwork) {
        var existing = formModel.cardNetworksText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !existing.contains(network.rawValue) else { return }
        existing.append(network.rawValue)
        formModel.cardNetworksText = existing.joined(separator: ", ")
    }

    private func cardTypeDisplayName(_ type: CardType) -> String {
        switch type {
        case .debit:
            return "Debit"
        case .credit:
            return "Credit"
        case .quasiCredit:
            return "Quasi-Credit"
        }
    }

    private func save() async {
        guard formModel.isEnabledNextButton else { return }
        // 自定义字段：丢弃 name/value 均为空的新增行；
        // 若存在「有值但缺名称」的字段，提示并阻止保存
        if formModel.customFields.sanitizeForSave() {
            showFieldNameRequiredPrompt = true
            return
        }
        isSaving = true
        defer { isSaving = false }

        let entry = formModel.buildDraftEntry()

        do {
            try await onSave(entry)
            await MainActor.run { dismiss() }
        } catch {
            print("Failed to save bankcard: \(error)")
        }
    }

    private func softDelete() async {
        guard let entry = formModel.buildSoftDeletedEntry() else { return }

        do {
            try await onSoftDelete?(entry)
            await MainActor.run { dismiss() }
        } catch {
            print("Failed to soft delete bankcard: \(error)")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Add Mode") {
    let referenceData = ReferenceDataService()
    AddBankcardView(formModel: BankcardFormModel(referenceData: referenceData)) { _ in }
}

#Preview("Edit Mode") {
    let entry = BankcardEntry(
        bankName: "ICBC",
        cardNumber: "6222021234567890123",
        cvv: "123",
        cardholder: "WANG GAVAN",
        expiryDate: "08/28",
        pin: "918273",
        issuingChannel: "Branch",
        onlineBankingPassword: "ICBC@2026!Secure",
        cardType: .debit,
        cardNetworks: ["UnionPay"],
        notes: "工商银行储蓄卡",
        categoryID: PasswordCategory.systemDefaults[2].id,
        tags: ["bank", "finance"],
        isFavorite: true
    )

    let referenceData = ReferenceDataService()
    AddBankcardView(
        formModel: BankcardFormModel(mode: .edit(entry), referenceData: referenceData),
        onSave: { _ in },
        onSoftDelete: { _ in }
    )
}
#endif
