/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// Tag.swift
/// created on: 13/07/2026
/// ------------------------------------------------------------------

import Foundation
import SwiftUI

/// 标签领域模型（持久化到 Core Data 的 CDTag 实体）
struct Tag: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var hexColor: String
    var sortOrder: Int32
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        hexColor: String? = nil,
        sortOrder: Int32 = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.hexColor = hexColor ?? tagColor(for: name)
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 便捷访问：将十六进制颜色转换为 SwiftUI Color
    var color: Color {
        Color(hex: hexColor)
    }
}

extension Tag {
    /// 系统预置标签（与 Category.systemDefaults 模式一致，使用固定 UUID 便于迁移）
    static let systemDefaults: [Tag] = [
        /*
        Tag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Work", hexColor: "#007AFF", sortOrder: 0),
        Tag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "Personal", hexColor: "#34C759", sortOrder: 1),
        Tag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            name: "Server", hexColor: "#FF9500", sortOrder: 2), 
        Tag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            name: "Bank", hexColor: "#FF2D55", sortOrder: 3),
        Tag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            name: "Social Media", hexColor: "#AF52DE", sortOrder: 4),
        */
    ]
}

// MARK: - Color hex 扩展

extension Color {
    /// 从十六进制字符串创建 Color（支持 "#RRGGBB" / "RRGGBB" 格式）
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    /// 转换为十六进制字符串 "#RRGGBB"
    func toHexString() -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#000000"
        #endif
    }
}
