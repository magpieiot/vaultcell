/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AutoFillCoreDataModel.swift
/// ------------------------------------------------------------------
///
/// AutoFill 扩展侧的 Core Data 实体声明，与主 App 共享的
/// `VaultCell.xcdatamodeld`（当前版本 VaultCell_v5）保持一致。
///
/// 扩展进程与主 App 进程相互独立，各自注册一套 `@objc(CDxxx)` 类，
/// Objective-C 运行时不会冲突。
/// 扩展只会实际读取 `CDPasswordEntry`，其余实体仅提供空壳类以满足
/// Core Data 模型加载时的类名解析。

import CoreData
import Foundation

@objc(CDPasswordEntry)
public class CDPasswordEntry: NSManagedObject {}

extension CDPasswordEntry {
    /// 主键：与主 App `PasswordEntry.id` 一致，用于回填定位
    @NSManaged public var id: UUID

    /// 站点/应用名称（明文存储）
    @NSManaged public var siteName: String

    /// 站点 URL（可选，明文存储）
    @NSManaged public var siteURL: String?

    /// 用户名/邮箱/账号（明文存储）
    @NSManaged public var username: String

    /// 加密后的密码正文（AES-GCM 密文，格式为 nonce+tag+ciphertext）
    @NSManaged public var encryptedPassword: Data

    /// 软删除时间戳（nil 表示正常条目，非 nil 表示位于回收站）
    @NSManaged public var deletedAt: Date?
}

// MARK: - 以下实体类仅供模型加载完成类名解析，扩展内不会被实例化

@objc(CDPincodeEntry)
public class CDPincodeEntry: NSManagedObject {}

@objc(CDBankcardEntry)
public class CDBankcardEntry: NSManagedObject {}

@objc(CDPasswordCategory)
public class CDPasswordCategory: NSManagedObject {}

@objc(CDTag)
public class CDTag: NSManagedObject {}

@objc(CDTwoFactorConfig)
public class CDTwoFactorConfig: NSManagedObject {}

@objc(CDOAuthProvider)
public class CDOAuthProvider: NSManagedObject {}

@objc(CDSafeNote)
public class CDSafeNote: NSManagedObject {}

@objc(CDSafeNoteAsset)
public class CDSafeNoteAsset: NSManagedObject {}
