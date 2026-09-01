/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// CDTag.swift
/// created on: 13/07/2026
/// ------------------------------------------------------------------

import Foundation
import CoreData

@objc(CDTag)
public class CDTag: NSManagedObject {

}

extension CDTag {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTag> {
        NSFetchRequest<CDTag>(entityName: "CDTag")
    }

    /// 主键
    @NSManaged public var id: UUID

    /// 标签名称（唯一）
    @NSManaged public var name: String

    /// 颜色（十六进制字符串，如 "#007AFF"）
    @NSManaged public var hexColor: String

    /// 排序权重
    @NSManaged public var sortOrder: Int32

    /// 创建时间
    @NSManaged public var createdAt: Date

    /// 更新时间
    @NSManaged public var updatedAt: Date

    /// 关联的密码条目（多对多关系的反向）
    @NSManaged public var passwordEntries: NSSet?
    
    @NSManaged public var pincodeEntries: NSSet?

    @NSManaged public var bankcardEntries: NSSet?
}

extension CDTag: Identifiable {

}
