/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PincodeFormView.swift
/// created on: 2026-08-03 14:00:00
/// ------------------------------------------------------------------

import SwiftUI

/// 新增/编辑 PIN Code 的统一表单视图
struct PincodeFormView: View {
    @ObservedObject var formModel: PincodeFormModel
    var onSave: (PincodeEntry) async throws -> Void
    var onSoftDelete: ((PincodeEntry) async throws -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isPincodeVisible = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false

    private var isEditMode: Bool {
        if case .edit = formModel.mode { return true }
        return false
    }

    init(
        formModel: PincodeFormModel,
        onSave: @escaping (PincodeEntry) async throws -> Void,
        onSoftDelete: ((PincodeEntry) async throws -> Void)? = nil
    ) {
        self.formModel = formModel
        self.onSave = onSave
        self.onSoftDelete = onSoftDelete
    }

    var body: some View {
        Group {
            if isEditMode {
                NavigationStack {
                    formContent
                        .navigationTitle("Edit PIN")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { editToolbar }
                }
            } else {
                formContent
            }
        }
    }

    private var formContent: some View {
        Form {
            basicInfoSection
            pincodeSection
            notesSection
            tagsSection
            customFieldSection
            if isEditMode {
                deleteSection
            }
        }
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await save() }
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 28, height: 28)
            }
            .disabled(!formModel.isEnabledNextButton || isSaving)
        }
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        Section {
            AdvancedTextField(
                iconName: "number.square.fill",
                iconColor: .orange,
                title: String(localized: "Title"),
                keyboardType: .default,
                text: $formModel.title
            )

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.orange)
                    .frame(width: 24, height: 24)

                Picker("Category", selection: $formModel.selectedCategoryID) {
                    ForEach(formModel.categories) { cat in
                        Text(cat.name).tag(cat.id)
                    }
                }
            }

            Toggle(isOn: $formModel.isFavorite) {
                HStack(spacing: 8) {
                    Image(systemName: "heart")
                        .foregroundColor(.orange)
                        .frame(width: 24, height: 24)
                    Text("Favorite")
                }
            }
        }
    }

    // MARK: - Pincode

    private var pincodeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pincode")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)

                HStack(alignment: .center, spacing: 8) {
                    if isPincodeVisible {
                        TextField("Pincode", text: $formModel.pincode)
                            .keyboardType(formModel.isNumericOnly ? .numberPad : .default)
                    } else {
                        SecureField("Pincode", text: $formModel.pincode)
                    }

                    Button {
                        isPincodeVisible.toggle()
                    } label: {
                        Image(systemName: isPincodeVisible ? "eye" : "eye.slash")
                            .foregroundColor(.secondary)
                    }
                }
                .textFieldStyle(LeadingIconTextFieldStyle(systemName: "lock"))
            }

            Toggle(isOn: $formModel.isNumericOnly) {
                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .foregroundColor(.orange)
                        .frame(width: 24, height: 24)
                    Text("Numeric Only")
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        NotesSectionView(text: $formModel.notes, iconColor: .orange)
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section {
            SmartTagManager(viewModel: formModel.tagSelection)
        } header: {
            Text("Tags")
        } footer: {
            Text("Separate tags with commas.")
                .font(.caption)
        }
    }

    // MARK: - Custom Fields

    private var customFieldSection: some View {
        Section {
            CustomFieldSection(model: formModel.customFieldModel)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Custom Fields")
        } footer: {
            AddNewFieldButton(model: formModel.customFieldModel)
        }
    }

    // MARK: - Soft Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Move to Trash")
                    Spacer()
                }
            }
            .alert("Move to Trash?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Move to Trash", role: .destructive) {
                    Task { await softDelete() }
                }
            } message: {
                Text("This item will be moved to the Trash and kept for 30 days.")
            }
        }
    }

    // MARK: - Actions

    private func save() async {
        guard formModel.isEnabledNextButton else { return }
        isSaving = true
        defer { isSaving = false }

        let entry = formModel.buildDraftEntry()

        do {
            try await onSave(entry)
            await MainActor.run { dismiss() }
        } catch {
            print("Failed to save pincode: \(error)")
        }
    }

    private func softDelete() async {
        guard let entry = formModel.buildSoftDeletedEntry() else { return }

        do {
            try await onSoftDelete?(entry)
            await MainActor.run { dismiss() }
        } catch {
            print("Failed to soft delete pincode: \(error)")
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Add Mode") {
        let referenceData = ReferenceDataService()
        PincodeFormView(formModel: PincodeFormModel(referenceData: referenceData)) { _ in }
    }

    #Preview("Edit Mode") {
        let referenceData = ReferenceDataService()
        let entry = PincodeEntry(
            title: "Phone Lock PIN",
            pincode: "918273",
            isNumericOnly: true,
            notes: "手机锁屏 PIN",
            categoryID: PasswordCategory.systemDefaults[0].id,
            tags: ["device", "personal"],
            isFavorite: true
        )

        PincodeFormView(
            formModel: PincodeFormModel(mode: .edit(entry), referenceData: referenceData),
            onSave: { _ in },
            onSoftDelete: { _ in }
        )
    }
#endif
