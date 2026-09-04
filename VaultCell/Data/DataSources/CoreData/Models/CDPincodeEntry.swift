import CoreData
import Foundation

@objc(CDPincodeEntry)
public class CDPincodeEntry: NSManagedObject {
    
}

extension CDPincodeEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPincodeEntry> {
        NSFetchRequest<CDPincodeEntry>(entityName: "CDPincodeEntry")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var encryptedPincode: Data
    @NSManaged public var encryptedNotes: Data?
    @NSManaged public var categoryID: UUID
    @NSManaged public var tags: String?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var isNumericOnly: Bool
    @NSManaged public var encryptedPincodeHistory: Data?
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

extension CDPincodeEntry: Identifiable {
    
}

