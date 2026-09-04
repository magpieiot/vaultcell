import CoreData
import Foundation

@objc(CDBankcardEntry)
public class CDBankcardEntry: NSManagedObject {
    
}

extension CDBankcardEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDBankcardEntry> {
        NSFetchRequest<CDBankcardEntry>(entityName: "CDBankcardEntry")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var bankName: String
    @NSManaged public var encryptedCardNumber: Data
    @NSManaged public var encryptedCvv: Data?
    @NSManaged public var cardholder: String
    @NSManaged public var expiryDate: String
    @NSManaged public var encryptedPin: Data?
    @NSManaged public var issuingChannel: String?
    @NSManaged public var encryptedOnlineBankingPassword: Data?
    @NSManaged public var cardTypeRaw: Int16
    @NSManaged public var cardNetworks: String?
    @NSManaged public var encryptedNotes: Data?
    @NSManaged public var categoryID: UUID
    @NSManaged public var tags: String?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var encryptedCustomFields: Data?
    @NSManaged public var version: Int64
    @NSManaged public var isSynced: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var lastUsedAt: Date?
    @NSManaged public var expiresAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var icon: String?
    @NSManaged public var dataSourceRaw: Int16
    @NSManaged public var tagsRelationship: NSSet?
}

extension CDBankcardEntry: Identifiable {
    
}

