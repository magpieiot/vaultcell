import Foundation

enum VaultItemType: String, CaseIterable, Codable {
    case password
    case pincode
    case bankcard
}

enum VaultSortMode: String, CaseIterable, Codable {
    case favoriteThenUpdatedAt
    case updatedAtDescending
    case titleAscending
    case createdAtDescending
}

/// 排序字段：创建时间 / 更新时间 / 标题
enum VaultSortField: String, CaseIterable, Codable {
    case createdAt
    case updatedAt
    case title
}

enum VaultDestination: Hashable {
    case passwordDetail(UUID)
    case pincodeDetail(UUID)
    case bankcardDetail(UUID)
}

enum VaultItem: Identifiable, Equatable {
    case password(PasswordEntry)
    case pincode(PincodeEntry)
    case bankcard(BankcardEntry)

    var id: UUID {
        switch self {
        case let .password(entry):
            entry.id
        case let .pincode(entry):
            entry.id
        case let .bankcard(entry):
            entry.id
        }
    }

    var type: VaultItemType {
        switch self {
        case .password:
            .password
        case .pincode:
            .pincode
        case .bankcard:
            .bankcard
        }
    }

    var title: String {
        switch self {
        case let .password(entry):
            entry.siteName
        case let .pincode(entry):
            entry.title
        case let .bankcard(entry):
            entry.bankName
        }
    }

    var subtitle: String? {
        switch self {
        case let .password(entry):
            return Self.nonEmpty(entry.username) ?? Self.nonEmpty(entry.siteURL)
        case .pincode:
            return "Pincode"
        case let .bankcard(entry):
            let cardholder = Self.nonEmpty(entry.cardholder)
            let last4 = Self.nonEmpty(Self.maskedLast4(from: entry.cardNumber))

            switch (cardholder, last4) {
            case let (.some(cardholder), .some(last4)):
                return "\(cardholder) | \(last4)"
            case let (.some(cardholder), .none):
                return cardholder
            case let (.none, .some(last4)):
                return last4
            case (.none, .none):
                return nil
            }
        }
    }

    var categoryID: UUID {
        switch self {
        case let .password(entry):
            entry.categoryID
        case let .pincode(entry):
            entry.categoryID
        case let .bankcard(entry):
            entry.categoryID
        }
    }

    var tags: [String] {
        switch self {
        case let .password(entry):
            entry.tags ?? []
        case let .pincode(entry):
            entry.tags ?? []
        case let .bankcard(entry):
            entry.tags ?? []
        }
    }

    var isFavorite: Bool {
        switch self {
        case let .password(entry):
            entry.isFavorite
        case let .pincode(entry):
            entry.isFavorite
        case let .bankcard(entry):
            entry.isFavorite
        }
    }

    var icon: String? {
        switch self {
        case let .password(entry):
            entry.icon
        case let .pincode(entry):
            entry.icon
        case let .bankcard(entry):
            entry.icon
        }
    }

    /// 站点 URL（仅密码条目持有；icon 为空时作为 favicon 抓取种子）
    var siteURL: String? {
        switch self {
        case let .password(entry):
            entry.siteURL
        case .pincode, .bankcard:
            nil
        }
    }

    var createdAt: Date? {
        switch self {
        case let .password(entry):
            entry.createdAt
        case let .pincode(entry):
            entry.createdAt
        case let .bankcard(entry):
            entry.createdAt
        }
    }

    var updatedAt: Date? {
        switch self {
        case let .password(entry):
            entry.updatedAt
        case let .pincode(entry):
            entry.updatedAt
        case let .bankcard(entry):
            entry.updatedAt
        }
    }

    var lastUsedAt: Date? {
        switch self {
        case let .password(entry):
            entry.lastUsedAt
        case let .pincode(entry):
            entry.lastUsedAt
        case let .bankcard(entry):
            entry.lastUsedAt
        }
    }

    var displayDate: Date {
        updatedAt ?? createdAt ?? .distantPast
    }

    /// 软删除时间戳：nil 表示未删除，非 nil 表示该条目在回收站中
    var deletedDate: Date? {
        switch self {
        case let .password(entry):
            entry.deletedAt
        case let .pincode(entry):
            entry.deletedAt
        case let .bankcard(entry):
            entry.deletedAt
        }
    }

    var searchableText: String {
        let fields: [String]

        switch self {
        case let .password(entry):
            fields = [
                entry.siteName,
                entry.siteURL,
                entry.username,
                entry.bundleEmailAddress,
                entry.bundlePhoneNumber,
                entry.notes,
                (entry.tags ?? []).joined(separator: " ")
            ].compactMap(Self.nonEmpty)
        case let .pincode(entry):
            fields = [
                entry.title,
                entry.notes,
                (entry.tags ?? []).joined(separator: " ")
            ].compactMap(Self.nonEmpty)
        case let .bankcard(entry):
            fields = [
                entry.bankName,
                entry.cardholder,
                entry.issuingChannel,
                entry.notes,
                Self.last4(from: entry.cardNumber),
                (entry.cardNetworks ?? []).joined(separator: " "),
                (entry.tags ?? []).joined(separator: " ")
            ].compactMap(Self.nonEmpty)
        }

        return fields.joined(separator: "\n")
    }

    func matches(categoryID: UUID?) -> Bool {
        guard let categoryID else { return true }
        return self.categoryID == categoryID
    }

    func matches(tags selectedTags: [Tag]) -> Bool {
        guard !selectedTags.isEmpty else { return true }

        let ownTags = Set(tags.map { $0.lowercased() })
        return selectedTags.allSatisfy { ownTags.contains($0.name.lowercased()) }
    }

    func matches(types selectedTypes: Set<VaultItemType>) -> Bool {
        guard !selectedTypes.isEmpty else { return true }
        return selectedTypes.contains(type)
    }

    var destination: VaultDestination {
        switch self {
        case .password:
            .passwordDetail(id)
        case .pincode:
            .pincodeDetail(id)
        case .bankcard:
            .bankcardDetail(id)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func last4(from cardNumber: String) -> String? {
        let digits = cardNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(4))
    }

    private static func maskedLast4(from cardNumber: String) -> String? {
        guard let last4 = last4(from: cardNumber) else { return nil }
        return "**** \(last4)"
    }
}
