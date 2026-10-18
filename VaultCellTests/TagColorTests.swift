/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TagColorTests.swift
/// 覆盖 tagColor(for:) 的确定性配色：同名标签跨设备/跨启动颜色必须一致，
/// 且输出必须落在预置调色板内（否则 UI 取不到颜色）。
/// ------------------------------------------------------------------

import Testing

@Suite("tagColor(for:)")
struct TagColorTests {

    private let palette = [
        "#007AFF", "#34C759", "#FF9500", "#AF52DE",
        "#FF2D55", "#5856D6", "#30B0C7", "#8E8E93",
    ]

    @Test("同名标签颜色稳定（确定性）")
    func deterministicForSameName() {
        #expect(tagColor(for: "Work") == tagColor(for: "Work"))
        #expect(tagColor(for: "个人") == tagColor(for: "个人"))
    }

    @Test("大小写不敏感")
    func caseInsensitive() {
        #expect(tagColor(for: "Work") == tagColor(for: "work"))
        #expect(tagColor(for: "SERVER") == tagColor(for: "server"))
    }

    @Test("输出始终在预置调色板内")
    func alwaysInPalette() {
        let names = ["", "a", "Work", "Personal", "Server", "Bank", "Social Media", "中文标签", "🚀"]
        for name in names {
            #expect(palette.contains(tagColor(for: name)), "\(name) 的颜色不在调色板内")
        }
    }

    @Test("空名返回调色板首色")
    func emptyNameUsesFirstColor() {
        #expect(tagColor(for: "") == palette[0])
    }

    @Test("不同名称可能产生同色（取模碰撞是允许的）")
    func collisionIsAllowed() {
        // 仅做存在性断言：至少有一个名字能映射，且结果有效
        let first = tagColor(for: "alpha")
        #expect(palette.contains(first))
    }
}
