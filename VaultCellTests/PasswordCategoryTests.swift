/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordCategoryTests.swift
/// 覆盖 PasswordCategory.systemDefaults 的不变式：固定 UUID 被多处按下标引用，
/// 数量 / 顺序 / 兜底分类一旦漂移会引发系统分类错乱。
/// ------------------------------------------------------------------

import Foundation
import Testing

@Suite("PasswordCategory.systemDefaults")
struct PasswordCategoryTests {

    @Test("系统分类数量为 6")
    func hasSixSystemDefaults() {
        #expect(PasswordCategory.systemDefaults.count == 6)
    }

    @Test("全部为系统分类")
    func allAreSystem() {
        #expect(PasswordCategory.systemDefaults.allSatisfy { $0.isSystem })
    }

    @Test("使用固定 UUID（被 PasswordEntry 默认值按下标引用）")
    func usesFixedUUIDs() {
        let ids = PasswordCategory.systemDefaults.map(\.id)
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)) // Primary
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000006")!)) // Social
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)) // Finance
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)) // Work
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)) // Life
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000005")!)) // Media
    }

    @Test("按 sortOrder 升序排列（与展示顺序一致）")
    func sortedBySortOrder() {
        let orders = PasswordCategory.systemDefaults.map(\.sortOrder)
        #expect(orders == orders.sorted())
        // 依次为 0..<6
        #expect(orders == [0, 1, 2, 3, 4, 5])
    }

    @Test("删除自定义分类的兜底目标 = Life 分类")
    func defaultCategoryIsLife() {
        #expect(PasswordCategory.defaultCategoryID == UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)
    }
}
