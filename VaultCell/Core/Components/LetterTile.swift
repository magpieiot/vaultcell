/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// LetterTile.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 字母图块：远程图标拿不到时的占位（首字母 + 分类 tint）。
/// 相比 SF Symbol 占位，首字母能让人一眼区分「招商银行 vs 建设银行」这类同分类条目，
/// 而且永远可渲染——列表行不会出现空白。

import SwiftUI

struct LetterTile: View {
    /// 首字母（可能是汉字或拉丁字母）
    let initial: String
    /// 底色 / 文字色（沿用分类 tint）
    var tint: Color = .blue
    /// 字号（跟随调用方的图标尺寸）
    var font: Font = .title2

    var body: some View {
        ZStack {
            tint.opacity(0.14)
            Text(initial)
                .font(font)
                .fontWeight(.semibold)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(2)
        }
    }
}
