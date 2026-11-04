//
//  BankcardFormModel.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/25.
//

import SwiftUI

@MainActor
final class BankcardFormModel: ObservableObject {
    enum Mode: Equatable {
        case add
        case edit(BankcardEntry)
    }

    let mode: Mode
    let categories: [PasswordCategory]

    @Published var bankName = ""
    @Published var cardNumber = ""
    @Published var cvv = ""
    @Published var cardholder = ""
    @Published var expiryDate = ""
    @Published var pin = ""
    @Published var issuingChannel = ""
    @Published var onlineBankingPassword = ""
    @Published var cardType: CardType = .debit
    @Published var cardNetworksText = ""
    @Published var notes = ""
    @Published var selectedCategoryID: UUID
    @Published var isFavorite = false

    @Published var tagSelection: TagSelectionViewModel
    @Published var customFields: [CustomField] = []

    /// 银行名称与卡号为必填项，任一为空时保存按钮不可用
    var isEnabledNextButton: Bool {
        let trimmedBank = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCard = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedBank.isEmpty && !trimmedCard.isEmpty
    }

    init(
        mode: Mode = .add,
        categories: [PasswordCategory] = PasswordCategory.systemDefaults,
        referenceData: ReferenceDataService
    ) {
        self.mode = mode
        self.categories = categories
        self.tagSelection = TagSelectionViewModel(referenceData: referenceData)

        let defaultCategory = categories.first ?? PasswordCategory.systemDefaults[0]
        self.selectedCategoryID = defaultCategory.id

        if case let .edit(entry) = mode {
            self.bankName = entry.bankName
            self.cardNumber = entry.cardNumber
            self.cvv = entry.cvv ?? ""
            self.cardholder = entry.cardholder
            self.expiryDate = entry.expiryDate
            self.pin = entry.pin ?? ""
            self.issuingChannel = entry.issuingChannel ?? ""
            self.onlineBankingPassword = entry.onlineBankingPassword ?? ""
            self.cardType = entry.cardType ?? .debit
            self.cardNetworksText = (entry.cardNetworks ?? []).joined(separator: ", ")
            self.notes = entry.notes ?? ""
            self.selectedCategoryID = entry.categoryID
            self.isFavorite = entry.isFavorite
            self.customFields = entry.customFields ?? []
            self.tagSelection.seedSelectedTags(with: entry.tags ?? [])
        }
    }

    func buildDraftEntry() -> BankcardEntry {
        let networks = cardNetworksText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tags = tagSelection.selectedTags.map(\.name)

        switch mode {
        case .add:
            return BankcardEntry(
                bankName: bankName.trimmingCharacters(in: .whitespacesAndNewlines),
                cardNumber: cardNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                cvv: cvv.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                cardholder: cardholder.trimmingCharacters(in: .whitespacesAndNewlines),
                expiryDate: expiryDate.trimmingCharacters(in: .whitespacesAndNewlines),
                pin: pin.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                issuingChannel: issuingChannel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                onlineBankingPassword: onlineBankingPassword.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                cardType: cardType,
                cardNetworks: networks,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                categoryID: selectedCategoryID,
                tags: tags,
                isFavorite: isFavorite,
                customFields: customFields.isEmpty ? nil : customFields,
                isSynced: false
            )
        case let .edit(entry):
            var updatedEntry = entry
            updatedEntry.bankName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedEntry.cardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedEntry.cvv = cvv.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            updatedEntry.cardholder = cardholder.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedEntry.expiryDate = expiryDate.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedEntry.pin = pin.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            updatedEntry.issuingChannel = issuingChannel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            updatedEntry.onlineBankingPassword = onlineBankingPassword.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            updatedEntry.cardType = cardType
            updatedEntry.cardNetworks = networks.isEmpty ? nil : networks
            updatedEntry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            updatedEntry.categoryID = selectedCategoryID
            updatedEntry.isFavorite = isFavorite
            updatedEntry.tags = tags.isEmpty ? nil : tags
            updatedEntry.customFields = customFields.isEmpty ? nil : customFields
            updatedEntry.updatedAt = Date()
            updatedEntry.isSynced = false
            return updatedEntry
        }
    }

    /// 生成已软删除的条目（仅编辑模式下有效）
    func buildSoftDeletedEntry() -> BankcardEntry? {
        guard case let .edit(entry) = mode else { return nil }
        var deletedEntry = entry
        deletedEntry.deletedAt = Date()
        deletedEntry.updatedAt = Date()
        deletedEntry.isSynced = false
        return deletedEntry
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
