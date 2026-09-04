/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CDPasswordCategory.swift
/// created on: 21/06/2026
/// ------------------------------------------------------------------

import Foundation
import CoreData

@objc(CDPasswordCategory)
public class CDPasswordCategory: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var icon: String
    @NSManaged public var hexColor: String
    @NSManaged public var isSystem: Bool
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

extension CDPasswordCategory {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPasswordCategory> {
        NSFetchRequest<CDPasswordCategory>(entityName: "CDPasswordCategory")
    }
}

extension CDPasswordCategory: Identifiable {

}
