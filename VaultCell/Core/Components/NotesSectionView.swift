/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// NotesSectionView.swift
/// created on: 05/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 表单中统一的 Notes（备注）多行输入区
/// 组件自带 Section，直接放入 Form 使用，例如：
/// ```swift
/// NotesSectionView(text: $formModel.notes, iconColor: .orange)
/// ```
/// - 占位符仅在内容为空且未聚焦时显示，避免与光标重叠
/// - 编辑框固定最小高度，避免空内容时行高随焦点状态变化导致跳动
struct NotesSectionView: View {
    /// 备注内容（由调用方的表单模型绑定）
    @Binding var text: String
    /// 占位符图标使用的表单主题色
    let iconColor: Color
    /// 占位符文案
    var placeholder: String = "Add Notes"
    /// Section footer 文案（可选；不为 nil 时显示，供需要补充说明的页面使用）
    var footer: String?

    /// 备注输入框是否处于聚焦状态（聚焦时隐藏占位文字，避免与光标重叠）
    @FocusState private var isFocused: Bool

    var body: some View {
        if let footer {
            Section {
                editorContent
            } header: {
                Text("Notes")
            } footer: {
                Text(footer)
                    .font(.caption)
            }
        } else {
            Section("Notes") {
                editorContent
            }
        }
    }

    /// 编辑器内容：占位符（仅在内容为空且未聚焦时显示）+ 多行输入框
    private var editorContent: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty && !isFocused {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundColor(iconColor)
                        .frame(width: 24, height: 24)
                    Text(placeholder)
                        .foregroundColor(.secondary)
                }
            }

            TextEditor(text: $text)
                .focused($isFocused)
                .multilineTextAlignment(.leading)
                // 固定最小高度，避免空内容时行高随焦点状态变化导致跳动
                .frame(minHeight: 100)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var notes = ""

        var body: some View {
            NavigationStack {
                Form {
                    NotesSectionView(text: $notes, iconColor: .orange)
                }
            }
        }
    }

    return PreviewWrapper()
}
