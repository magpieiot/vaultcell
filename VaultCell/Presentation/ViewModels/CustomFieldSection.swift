//
//  CustomFieldSection.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/21.
//
import SwiftUI

/// 自定义字段管理器，负责添加、编辑和删除自定义字段
struct CustomFieldSection: View {
    @ObservedObject var model: CustomFieldModel
    @FocusState private var focusedFieldID: UUID?
    @State private var revealedFieldIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            if model.isEmpty {
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
                    ForEach($model.customFields) { $field in
                        fieldRow(field: $field)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.customFields.map(\.id))
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

                /*
                Button {
                    toggleReveal(field.id)
                } label: {
                    Image(
                        systemName: field.wrappedValue.isSensitive
                            ? (revealedFieldIDs.contains(field.id) ? "eye.slash" : "eye")
                            : "eye.slash"
                    )
                    .font(.system(size: 14))
                    .foregroundColor(field.wrappedValue.isSensitive ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .opacity(field.wrappedValue.isSensitive ? 1 : 0.3)
                */

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.deleteField(id: field.id)
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
            .font(.subheadline)
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
                    model.deleteField(id: field.id)
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
        if let index = model.customFields.firstIndex(where: { $0.id == id }) {
            model.customFields[index].isSensitive.toggle()
            if !model.customFields[index].isSensitive {
                revealedFieldIDs.remove(id)
            }
        }
    }

    /// 添加新的自定义字段
    private func addNewField() {
        let newField = model.addField()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            focusedFieldID = newField.id
        }
    }
}

struct AddNewFieldButton: View {
    @ObservedObject var model: CustomFieldModel
    /// 存在名称为空的字段时，提示用户先补全名称
    @State private var showUntitledPrompt = false

    var body: some View {
        Button {
            guard !model.hasUntitledField else {
                showUntitledPrompt = true
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = model.addField()
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

// MARK: - Preview

#Preview("自定义字段 - 空状态") {
    @Previewable @State var model = CustomFieldModel()
    Form {
        Section {
            CustomFieldSection(model: model)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(model: model)
        }
    }
}

#Preview("自定义字段 - 有数据") {
    @Previewable @State var model = CustomFieldModel(customFields: [
        CustomField(name: "Account", value: "admin@example.com"),
        CustomField(name: "Security Question", value: "Your first pet's name", isSensitive: true),
        CustomField(name: "API Key", value: "sk-0123456789abcdef", isSensitive: true)
    ])
    Form {
        Section {
            CustomFieldSection(model: model)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(model: model)
        }
    }
}
