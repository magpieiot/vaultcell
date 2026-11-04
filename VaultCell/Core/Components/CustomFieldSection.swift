//
//  CustomFieldSection.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/21.
//

import SwiftUI

/// 自定义字段管理器，负责添加、编辑和删除自定义字段
struct CustomFieldSection: View {
    @Binding var customFields: [CustomField]
    @FocusState private var focusedFieldID: UUID?
    @State private var revealedFieldIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            if customFields.isEmpty {
                // 空状态：图标 + 文案
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.secondary)
                    Text("No custom fields yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // 字段列表：以留白代替分隔线，每行自带值输入容器
                VStack(spacing: 16) {
                    ForEach($customFields) { $field in
                        fieldRow(field: $field)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: customFields.map(\.id))
            }
        }
    }

    /// 单个自定义字段行
    private func fieldRow(field: Binding<CustomField>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 名称输入 + 删除操作
            HStack(spacing: 8) {
                TextField("Name", text: field.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .focused($focusedFieldID, equals: field.id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        removeField(id: field.id)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                // 扩大点击热区并补充无障碍标签
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .accessibilityLabel("Delete Field")
            }

            // 值输入框：放入浅色圆角容器，与名称行形成主次层级
            Group {
                if field.wrappedValue.isSensitive && !revealedFieldIDs.contains(field.id) {
                    SecureField("Value", text: field.value)
                } else {
                    TextField("Value", text: field.value)
                }
            }
            // 敏感字段（可切换明文）使用等宽字体，便于逐字核对密钥类内容
            .font(field.wrappedValue.isSensitive ? .subheadline.monospaced() : .subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                withAnimation {
                    removeField(id: field.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func toggleReveal(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if revealedFieldIDs.contains(id) {
                revealedFieldIDs.remove(id)
            } else {
                revealedFieldIDs.insert(id)
            }
        }
    }

    private func toggleSensitive(_ id: UUID) {
        if let index = customFields.firstIndex(where: { $0.id == id }) {
            customFields[index].isSensitive.toggle()
            if !customFields[index].isSensitive {
                revealedFieldIDs.remove(id)
            }
        }
    }

    /// 删除指定 id 的自定义字段
    private func removeField(id: UUID) {
        customFields.removeAll { $0.id == id }
    }
}

struct AddNewFieldButton: View {
    @Binding var customFields: [CustomField]
    /// 存在名称为空的字段时，提示用户先补全名称
    @State private var showUntitledPrompt = false

    var body: some View {
        Button {
            guard !customFields.hasUntitledField else {
                showUntitledPrompt = true
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                customFields.append(CustomField(name: "", value: ""))
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add New")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundColor(.primaryBrandColor)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Name Required", isPresented: $showUntitledPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please fill in the field name before adding a new one.")
        }
    }
}

fileprivate extension Array where Element == CustomField {
    /// 是否存在名称为空（或仅空白字符）的字段
    var hasUntitledField: Bool {
        contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - 保存前清理与校验

extension Array where Element == CustomField {
    /// 保存前的数据清理与校验：
    /// 1. 移除「名称与值均为空白」的新增空行（静默丢弃，不打扰用户）；
    /// 2. 返回是否存在「有值但缺少名称」的字段行（调用方需弹提示并阻止保存）。
    @discardableResult
    mutating func sanitizeForSave() -> Bool {
        removeAll { field in
            field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && field.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return contains { field in
            field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

extension View {
    /// 自定义字段「有值但缺少名称」时阻止保存的提示弹窗
    func customFieldNameRequiredAlert(isPresented: Binding<Bool>) -> some View {
        alert("Name Required", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some custom fields are missing a name. Fill in the name or delete the field before saving.")
        }
    }
}

// MARK: - Preview

#Preview("自定义字段 - 空状态") {
    @Previewable @State var customFields: [CustomField] = []
    Form {
        Section {
            CustomFieldSection(customFields: $customFields)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(customFields: $customFields)
        }
    }
}

#Preview("自定义字段 - 有数据") {
    @Previewable @State var customFields: [CustomField] = [
        CustomField(name: "Account", value: "admin@example.com"),
        CustomField(name: "Security Question", value: "Your first pet's name", isSensitive: true),
        CustomField(name: "API Key", value: "sk-0123456789abcdef", isSensitive: true)
    ]
    Form {
        Section {
            CustomFieldSection(customFields: $customFields)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(customFields: $customFields)
        }
    }
}
