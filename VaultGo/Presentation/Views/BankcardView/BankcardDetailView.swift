//
//  BankcardDetailView.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/25.
//

import SwiftUI

/// Bank Card 详情视图
/// 展示单条 BankcardEntry 的完整信息，包括银行、卡号、CVV、持卡人、有效期、PIN、网银密码等
struct BankcardDetailView: View {
    let entry: BankcardEntry
    let categories: [PasswordCategory]
    var onUpdate: ((BankcardEntry) async -> Void)?
    var onDelete: ((BankcardEntry) async -> Void)?
    let referenceData: ReferenceDataService

    @State private var isCardNumberVisible = false
    @State private var showingEditSheet = false

    var body: some View {
        List {
            headerSection
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            
            //cardInfoSection

            securitySection

            if let notes = entry.notes, !notes.isEmpty {
                notesSection
            }

            if !(entry.customFields ?? []).isEmpty {
                customFieldSection
            }

            otherInfoSection
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.horizontal, 16)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.bankName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            /// 编辑按钮
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddBankcardView(
                formModel: BankcardFormModel(mode: .edit(entry), referenceData: referenceData),
                onSave: { updatedEntry in
                    await onUpdate?(updatedEntry)
                },
                onSoftDelete: { deletedEntry in
                    await onDelete?(deletedEntry)
                }
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        //VStack(alignment: .leading, spacing: 12) {
        Section {
            BankcardFaceView(
                bankName: entry.bankName,
                cardNumber: entry.cardNumber,
                cardholder: entry.cardholder,
                expiryDate: entry.expiryDate,
                cardNetworks: entry.cardNetworks ?? []
            )
        } header: {
            HStack {
                Text(categoryName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
                Spacer()
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
            }

        } footer: {
            if let tags = entry.tags, !tags.isEmpty {
                TagListView(tags: tags)
            }
        }
    }
            
    // MARK: - Security

    private var securitySection: some View {
        Section("Security") {
            // CVV
            if let cvv = entry.cvv, !cvv.isEmpty {
                SecureRow(title: "CVV", value: cvv, icon: "lock.shield.fill")
            }

            // PIN
            if let pin = entry.pin, !pin.isEmpty {
                SecureRow(title: "Pincode", value: pin, icon: "lock.fill")
            }

            // Online Banking Password
            if let pwd = entry.onlineBankingPassword, !pwd.isEmpty {
                SecureRow(title: "Online Banking Password", value: pwd, icon: "key.fill")
            }

            // Issuing Channel
            if let channel = entry.issuingChannel, !channel.isEmpty {
                DetailRow(
                    title: "Issuing Channel",
                    value: channel,
                    leadingIcon: "shippingbox.fill",
                    trailingIcon: nil
                )
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            Text(entry.notes ?? "")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Custom Fields

    private var customFieldSection: some View {
        Section("Custom Fields") {
            ForEach(entry.customFields ?? [], id: \.name) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(field.value)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Other Info

    private var otherInfoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Source: \((entry.dataSource ?? .manual).displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Created: \((entry.createdAt ?? Date()).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Updated: \((entry.updatedAt ?? Date()).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var categoryName: String {
        categories.first { $0.id == entry.categoryID }?.name ?? "Other"
    }

    private func cardTypeDisplayName(_ type: CardType) -> String {
        switch type {
        case .debit: return String(localized: "Debit")
        case .credit: return String(localized: "Credit")
        case .quasiCredit: return String(localized: "Quasi-Credit")
        }
    }
}

// MARK: - Secure Row

private struct SecureRow: View {
    let title: String
    let value: String
    let icon: String

    @State private var isVisible = false
    @State private var showingCopied = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isVisible {
                    PasswordText(value)
                        .font(.system(.headline, design: .monospaced))
                        .letterColor(.primary)
                        .digitColor(.green)
                        .symbolColor(.orange)
                } else {
                    Text(String(repeating: "•", count: min(value.count, 16)))
                        .font(.system(.headline, design: .monospaced))
                }
            }

            Spacer()

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 4)

            Copy2ClipboardButton(text: value)
        }
    }
}

private struct BankcardFaceView: View {
    let bankName: String
    let cardNumber: String
    let cardholder: String
    let expiryDate: String
    let cardNetworks: [String]

    @State private var showingCardNumberCopied = false

    var body: some View {
        
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bank Name")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                    Text(bankName)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()

                if networkAssets.isEmpty {
                    Image(systemName: "creditcard.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.9))
                } else {
                    HStack(spacing: 8) {
                        ForEach(networkAssets, id: \.self) { asset in
                            Image(asset)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 56)
                        }
                    }
                }
            }

            Image(systemName: "creditcard.fill")
                .font(.title)
                .foregroundColor(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 8) {
                HStack{
                    Text("Card Number")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()

                    Copy2ClipboardButton(text: cardNumber, backgroundLight: false)
                }
                
                Text(formattedCardNumber)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(2)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Holder")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                    Text(displayCardholder)
                        .font(.headline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Expiry")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                    Text(displayExpiryDate)
                        .font(.headline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(faceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(faceBorder)
        //.shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var networkAssets: [String] {
        cardNetworks.compactMap { BankCardNetwork.from($0)?.assetName }
    }

    private static let defaultFaceColors: [Color] = [
        Color(red: 0.04, green: 0.10, blue: 0.22),
        Color(red: 0.08, green: 0.32, blue: 0.50),
        Color(red: 0.13, green: 0.62, blue: 0.52)
    ]

    /// 根据首个可解析的网络选择品牌渐变，无网络时回退默认渐变
    private var faceGradient: LinearGradient {
        let colors: [Color]
        if let network = cardNetworks.lazy.compactMap({ BankCardNetwork.from($0) }).first {
            colors = network.faceBackgroundColors
        } else {
            colors = Self.defaultFaceColors
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 渐变底 + 顶部高光（iOS 26 上叠加液态玻璃效果，旧系统回退纯渐变）
    private var faceBackground: some View {
        #if swift(>=6.2)
        if #available(iOS 26.0, *) {
            baseFaceBackground.glassEffect()
        } else {
            baseFaceBackground
        }
        #else
        baseFaceBackground
        #endif
    }

    private var baseFaceBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(faceGradient)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.03),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var faceBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
    }

    private var formattedCardNumber: String {
        let digits = cardNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return "0000 0000 0000 0000" }

        return stride(from: 0, to: digits.count, by: 4).map { index in
            let start = digits.index(digits.startIndex, offsetBy: index)
            let end = digits.index(start, offsetBy: min(4, digits.count - index), limitedBy: digits.endIndex) ?? digits.endIndex
            return String(digits[start..<end])
        }
        .joined(separator: " ")
    }

    private var displayCardholder: String {
        let trimmed = cardholder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "CARD HOLDER" : trimmed.uppercased()
    }

    private var displayExpiryDate: String {
        let trimmed = expiryDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "MM/YY" : trimmed
    }
}

#Preview {
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
        cardNetworks: ["Visa"],
        notes: "工商银行储蓄卡",
        categoryID: PasswordCategory.systemDefaults[1].id,
        tags: ["bank", "finance", "seed"],
        isFavorite: true
    )

    NavigationStack {
        BankcardDetailView(
            entry: entry,
            categories: PasswordCategory.systemDefaults,
            referenceData: ReferenceDataService()
        )
    }
}
