/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SafeNoteEditorViewModel.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import PhotosUI

/// 安全笔记编辑页的视图模型
/// 负责管理标题、正文、图片草稿的编辑状态，并最终调用 Service 保存笔记。
@MainActor
final class SafeNoteEditorViewModel: ObservableObject {
    @Published var draft: SafeNoteDraft
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?

    private let service: SafeNoteVaultService
    let editingNote: SafeNote?

    init(
        service: SafeNoteVaultService,
        editingNote: SafeNote? = nil
    ) {
        self.service = service
        self.editingNote = editingNote
        if let editingNote {
            self.draft = SafeNoteDraft(
                title: editingNote.title,
                content: editingNote.content,
                assets: editingNote.assets.map {
                    SafeNoteDraftAsset(
                        id: $0.id,
                        existingAsset: $0,
                        sortOrder: $0.sortOrder
                    )
                },
                coverAssetID: editingNote.coverAssetID,
                isFavorite: editingNote.isFavorite
            )
        } else {
            self.draft = SafeNoteDraft()
        }
    }

    func updateTitle(_ title: String) {
        draft.title = title
    }

    func updateContent(_ content: String) {
        draft.content = content
    }

    /// 从 PhotosPicker 选择结果中加载图片数据并加入草稿
    func addImages(from selections: [PhotosPickerItem]) async {
        for item in selections {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let nextOrder = draft.assets.count
                    let draftAsset = SafeNoteDraftAsset(
                        imageData: data,
                        sortOrder: nextOrder
                    )
                    draft.assets.append(draftAsset)
                    if draft.coverAssetID == nil {
                        draft.coverAssetID = draftAsset.id
                    }
                }
            } catch {
                errorMessage = "Failed to load image"
            }
        }
    }

    func removeAsset(_ assetID: UUID) {
        draft.assets.removeAll { $0.id == assetID }
        if draft.coverAssetID == assetID {
            draft.coverAssetID = draft.assets.first?.id
        }
    }

    func moveAssets(from source: IndexSet, to destination: Int) {
        draft.assets.move(fromOffsets: source, toOffset: destination)
        for index in draft.assets.indices {
            draft.assets[index].sortOrder = index
        }
    }

    func setCoverAsset(_ assetID: UUID) {
        draft.coverAssetID = assetID
    }

    /// 软删除当前编辑的笔记（仅对已存在笔记有效）
    func delete() async -> Bool {
        guard let editingNote else { return false }
        do {
            await service.deleteNote(editingNote.id)
            return true
        }
    }

    /// 保存笔记：新建或更新
    func save() async -> SafeNote? {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Title is required"
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let editingNote {
                var updatedNote = editingNote
                updatedNote.title = draft.title
                updatedNote.content = draft.content
                updatedNote.coverAssetID = draft.coverAssetID
                updatedNote.isFavorite = draft.isFavorite
                updatedNote.updatedAt = Date()
                updatedNote.version += 1
                try await service.updateNote(updatedNote, draftAssets: draft.assets)
                return updatedNote
            } else {
                let note = SafeNote(
                    title: draft.title,
                    content: draft.content,
                    coverAssetID: draft.coverAssetID,
                    isFavorite: draft.isFavorite
                )
                try await service.addNoteOrThrow(note, draftAssets: draft.assets)
                return note
            }
        } catch {
            errorMessage = "Save failed"
            return nil
        }
    }
}
