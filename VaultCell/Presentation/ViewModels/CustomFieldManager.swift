//
//  CustomFieldManager.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/21.
//
import SwiftUI

/// 自定义字段管理器，负责添加、编辑和删除自定义字段
struct CustomFieldManager: View {
    @ObservedObject var model: CustomFieldModel
    @FocusState private var focusedFieldID: UUID?
    @State private var revealedFieldIDs: Set<UUID> = []


    var body: some View {
        VStack(spacing: 0) {
            if model.isEmpty {
                Text("No custom fields yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach($model.customFields) { $field in
                    fieldRow(field: $field)
                    if field.id != model.customFields.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    /// 单个自定义字段行
    private func fieldRow(field: Binding<CustomField>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                TextField("Name", text: field.name)
                    .font(.subheadline)
                    .focused($focusedFieldID, equals: field.id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    toggleReveal(field.id)
                } label: {
                    Image(systemName: field.wrappedValue.isSensitive
                          ? (revealedFieldIDs.contains(field.id) ? "eye.slash" : "eye")
                          : "eye.slash")
                        .font(.system(size: 14))
                        .foregroundColor(field.wrappedValue.isSensitive ? .accentColor : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .opacity(field.wrappedValue.isSensitive ? 1 : 0.3)

                /*
                Button {
                    toggleSensitive(field.id)
                } label: {
                    Image(systemName: field.wrappedValue.isSensitive ? "lock.fill" : "lock.open")
                        .font(.system(size: 14))
                        .foregroundColor(field.wrappedValue.isSensitive ? .orange : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                */

                Button {
                    withAnimation {
                        model.deleteField(id: field.id)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            // 值输入框
            Group {
                if field.wrappedValue.isSensitive && !revealedFieldIDs.contains(field.id) {
                    SecureField("Value", text: field.value)
                        .font(.subheadline)
                } else {
                    TextField("Value", text: field.value)
                        .font(.subheadline)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        //.padding(.vertical, 10)
        //.padding(.horizontal, 16)
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
    
    var body: some View {
        Button {
            model.addField()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                Text("Add New")
                    Spacer()
            }
            .foregroundColor(.blue)
            //.padding(.vertical, 12)
            //.padding(.horizontal, 16)
        }
        //.buttonStyle(.plain)
    }
}

