/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// LanguagePickerView.swift
/// ------------------------------------------------------------------

import SwiftUI

/// 语言选择器（以 sheet 形式呈现）。
///
/// 选中即调用 `AppLanguageManager.set(_:)` 并自动关闭 sheet；
/// 关闭后父视图 SettingsView 会在新语言下重新渲染。
///
/// 设计要点：
/// - “跟随系统”置顶，使用品牌渐变地球徽标；
/// - 每种语言配一个专属配色的语言徽标，便于快速辨识；
/// - 选中行使用品牌色高亮背景 + 圆形勾选图标。
struct LanguagePickerView: View {

    @EnvironmentObject var languageManager: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 跟随系统
                Section {
                    languageRow(for: .followOS)
                } header: {
                    Text("App language. Some items will refresh after restart.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // 具体语言
                Section {
                    ForEach(AppLanguage.allCases.filter { $0 != .followOS }) { language in
                        languageRow(for: language)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// 单条语言选项
    @ViewBuilder
    private func languageRow(for language: AppLanguage) -> some View {
        let isSelected = (language == languageManager.current)

        Button {
            languageManager.set(language)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                LanguageBadge(language: language, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.nativeDisplayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(.primary)
                    Text(language.englishDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.primaryBrandColor)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .contentShape(Rectangle())
            //.padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.primaryBrandColor.opacity(0.08) : Color.clear)
        )
    }
}

#Preview {
    LanguagePickerView()
        .environmentObject(AppLanguageManager.shared)
}
