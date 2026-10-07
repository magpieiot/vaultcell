/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordCategory.swift
/// created on: 21/06/2026
/// ------------------------------------------------------------------

import Foundation
import SwiftUI

struct PasswordCategory: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var hexColor: String
    var isSystem: Bool
    var sortOrder: Int32
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        hexColor: String = "#8E8E93",
        isSystem: Bool = false,
        sortOrder: Int32 = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.hexColor = hexColor
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PasswordCategory {
    /// 系统预置分类：数组顺序即展示顺序，与 sortOrder 保持一致。
    /// 注意：站内多处通过 `systemDefaults[下标]` 引用，插入新分类会使后续下标整体后移，
    /// 需同步更新这些引用（按 4→5、3→4、2→3、1→2 顺序替换，避免重复命中）。
    static let systemDefaults: [PasswordCategory] = [
        PasswordCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        name: "Primary", icon: "star.fill", hexColor: "#007AFF",
                        isSystem: true, sortOrder: 0),
        PasswordCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                        name: "Social", icon: "person.2.fill", hexColor: "#30B0C7",
                        isSystem: true, sortOrder: 1),
        PasswordCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                        name: "Finance", icon: "banknote.fill", hexColor: "#34C759",
                        isSystem: true, sortOrder: 2),
        PasswordCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                        name: "Work", icon: "briefcase.fill", hexColor: "#FF9500",
                        isSystem: true, sortOrder: 3),
        PasswordCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                        name: "Life", icon: "house.fill", hexColor: "#FF2D55",
                        isSystem: true, sortOrder: 4),
        PasswordCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                        name: "Media", icon: "play.rectangle.fill", hexColor: "#AF52DE",
                        isSystem: true, sortOrder: 5)
    ]

    /// 删除自定义分类时，关联密码迁移到的目标分类（Life 作为通用兜底）
    static let defaultCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
}

extension PasswordCategory {
    /// 根据分类名称返回对应的背景色
    var backgroundColor: Color {
        switch name {
        case "Primary": return Color.CategoryBackground.Primary
        case "Social":  return Color.CategoryBackground.Social
        case "Finance": return Color.CategoryBackground.Finance
        case "Work":    return Color.CategoryBackground.Work
        case "Life":    return Color.CategoryBackground.Life
        case "Media":   return Color.CategoryBackground.Media
        default:        return Color(hex: hexColor).opacity(0.15)
        }
    }

    /// 根据分类名称返回对应的前景/Tint色
    var tintColor: Color {
        switch name {
        case "Primary": return Color.CategoryTint.Primary
        case "Social":  return Color.CategoryTint.Social
        case "Finance": return Color.CategoryTint.Finance
        case "Work":    return Color.CategoryTint.Work
        case "Life":    return Color.CategoryTint.Life
        case "Media":   return Color.CategoryTint.Media
        default:        return Color(hex: hexColor)
        }
    }
}

