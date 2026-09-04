/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// BankcardEntry.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation

struct BankcardEntry: Identifiable, Codable, Equatable {
    
    let id: UUID
    var bankName: String
    var cardNumber: String
    var cvv: String?
    var cardholder: String
    var expiryDate: String
    var pin: String?
    var issuingChannel: String?
    var onlineBankingPassword: String?
    var cardType: CardType?
    var cardNetworks: [String]?
    
    var notes: String?
    var categoryID: UUID
    var tags: [String]?
    var isFavorite: Bool = false
    var customFields: [CustomField]?
    
    var version: Int64 = 1
    var isSynced: Bool = false
    var createdAt: Date?
    var updatedAt: Date?
    var lastUsedAt: Date?
    var expiresAt: Date?
    var deletedAt: Date?
    var icon: String?
    var dataSource: PasswordDataSource?
    
    init(
        id: UUID = UUID(),
        bankName: String,
        cardNumber: String,
        cvv: String? = nil,
        cardholder: String,
        expiryDate: String,
        pin: String? = nil,
        issuingChannel: String? = nil,
        onlineBankingPassword: String? = nil,
        cardType: CardType? = nil,
        cardNetworks: [String] = [],
        notes: String? = nil,
        categoryID: UUID = PasswordCategory.systemDefaults[0].id,
        tags: [String] = [],
        isFavorite: Bool = false,
        customFields: [CustomField]? = [],
        version: Int64 = 1,
        isSynced: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        expiresAt: Date? = nil,
        deletedAt: Date? = nil,
        icon: String? = nil,
        dataSource: PasswordDataSource? = .manual
    ) {
        self.id = id
        self.bankName = bankName
        self.cardNumber = cardNumber
        self.cvv = cvv
        self.cardholder = cardholder
        self.expiryDate = expiryDate
        self.pin = pin
        self.issuingChannel = issuingChannel
        self.onlineBankingPassword = onlineBankingPassword
        self.cardType = cardType
        self.cardNetworks = cardNetworks
        self.notes = notes
        self.categoryID = categoryID
        self.tags = tags
        self.isFavorite = isFavorite
        self.customFields = customFields
        self.version = version
        self.isSynced = isSynced
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt
        self.deletedAt = deletedAt
        self.icon = icon
        self.dataSource = dataSource
    }
    
    func isValidPin() -> Bool {
        guard let pin else { return true }
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }
}

enum CardType: Int, Codable, CaseIterable {
    case debit = 0
    case credit = 1
    case quasiCredit = 2
}

