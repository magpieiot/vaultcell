/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PincodeFormModel.swift
/// created on: 2026-08-03 14:00:00
/// ------------------------------------------------------------------

import Foundation
import SwiftUI

@MainActor
final class PincodeFormModel: ObservableObject {
    enum Mode: Equatable {
        case add
        case edit(PincodeEntry)
    }

    let mode: Mode
    let categories: [PasswordCategory]

    @Published var title: String = ""
    @Published var pincode: String = ""
    @Published var notes: String = ""
    @Published var selectedCategoryID: UUID
    @Published var isFavorite: Bool = false
    @Published var isNumericOnly: Bool = false
    @Published var customFieldModel: CustomFieldModel
    @Published var tagSelection: TagSelectionViewModel

    var isEnabledNextButton: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !pincode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        mode: Mode = .add,
        categories: [PasswordCategory] = PasswordCategory.systemDefaults,
        referenceData: ReferenceDataService
    ) {
        self.mode = mode
        self.categories = categories
        self.tagSelection = TagSelectionViewModel(referenceData: referenceData)

        let defaultCategory = categories.first ?? PasswordCategory.systemDefaults[0]
        self.selectedCategoryID = defaultCategory.id

        if case let .edit(entry) = mode {
            self.title = entry.title
            self.pincode = entry.pincode
            self.notes = entry.notes ?? ""
            self.selectedCategoryID = entry.categoryID
            self.isFavorite = entry.isFavorite
            self.isNumericOnly = entry.isNumericOnly
            self.customFieldModel = CustomFieldModel(customFields: entry.customFields ?? [])
            self.tagSelection.seedSelectedTags(with: entry.tags ?? [])
        } else {
            self.customFieldModel = CustomFieldModel(customFields: [])
        }
    }

    func buildDraftEntry() -> PincodeEntry {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPincode = pincode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tagSelection.selectedTags.map(\.name)

        switch mode {
        case .add:
            return PincodeEntry(
                title: trimmedTitle,
                pincode: trimmedPincode,
                isNumericOnly: isNumericOnly,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                categoryID: selectedCategoryID,
                tags: tags.isEmpty ? [] : tags,
                isFavorite: isFavorite,
                customFields: customFieldModel.customFields.isEmpty ? nil : customFieldModel.customFields,
                isSynced: false
            )
        case let .edit(entry):
            var updatedEntry = entry
            updatedEntry.title = trimmedTitle
            updatedEntry.pincode = trimmedPincode
            updatedEntry.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            updatedEntry.categoryID = selectedCategoryID
            updatedEntry.isFavorite = isFavorite
            updatedEntry.isNumericOnly = isNumericOnly
            updatedEntry.customFields = customFieldModel.customFields.isEmpty ? nil : customFieldModel.customFields
            updatedEntry.tags = tags.isEmpty ? nil : tags
            updatedEntry.updatedAt = Date()
            updatedEntry.isSynced = false
            if trimmedPincode != entry.pincode {
                updatedEntry.updatePincode(trimmedPincode)
            }
            return updatedEntry
        }
    }

    /// 生成已软删除的条目（仅编辑模式下有效）
    func buildSoftDeletedEntry() -> PincodeEntry? {
        guard case let .edit(entry) = mode else { return nil }
        var deletedEntry = entry
        deletedEntry.deletedAt = Date()
        deletedEntry.updatedAt = Date()
        deletedEntry.isSynced = false
        return deletedEntry
    }
}
