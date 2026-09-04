import Foundation

struct PincodeEntry: Identifiable, Codable, Equatable {
    
    static let numericOnlyMinLength = 4
    static let numericOnlyMaxLength = 12
    
    let id: UUID
    var title: String
    var pincode: String
    var pincodeHistory: [PincodeHistoryEntry]?
    var notes: String?
    var categoryID: UUID
    var tags: [String]?
    var isFavorite: Bool = false
    var isNumericOnly: Bool = false
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
        title: String,
        pincode: String,
        isNumericOnly: Bool = false,
        pincodeHistory: [PincodeHistoryEntry]? = [],
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
        self.title = title
        self.pincode = pincode
        self.isNumericOnly = isNumericOnly
        self.pincodeHistory = pincodeHistory
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
    
    func isValidPincode() -> Bool {
        let trimmed = pincode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        guard isNumericOnly else { return true }
        guard trimmed.count >= Self.numericOnlyMinLength, trimmed.count <= Self.numericOnlyMaxLength else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }
    
    mutating func updatePincode(_ newPincode: String) {
        let oldEntry = PincodeHistoryEntry(pincode: self.pincode, changedAt: self.updatedAt ?? Date())
        self.pincodeHistory?.append(oldEntry)
        self.pincode = newPincode
        self.updatedAt = Date()
        self.version += 1
        self.isSynced = false
    }
}

struct PincodeHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let pincode: String
    let changedAt: Date
    
    init(id: UUID = UUID(), pincode: String, changedAt: Date) {
        self.id = id
        self.pincode = pincode
        self.changedAt = changedAt
    }
}

