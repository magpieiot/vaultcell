//
//  TagSelectionViewModel.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/27.
//

import SwiftUI

/// 标签选择与管理视图模型
/// 通用于 PasswordEntry、PincodeEntry、BankcardEntry 等数据的标签编辑场景，
/// 同时也支持全局标签管理页面。所有标签数据统一通过 ReferenceDataService 维护。
@MainActor
final class TagSelectionViewModel: ObservableObject {
    @Published var selectedTags: [Tag] = []
    @Published var inputText: String = ""
    @Published var isInputFocused: Bool = false
    @Published var isEditing: Bool = false

    private let referenceData: ReferenceDataService

    var tags: [Tag] { referenceData.tags }

    /// 智能推荐标签：全局标签中排除已选中的，并根据输入文字模糊匹配
    var suggestedTags: [Tag] {
        tags.filter { tag in
            !selectedTags.contains(tag) &&
            (inputText.isEmpty || tag.name.localizedCaseInsensitiveContains(inputText))
        }
    }

    init(referenceData: ReferenceDataService) {
        self.referenceData = referenceData
    }

    /// 异步加载全局标签列表
    func loadTags() async {
        await referenceData.loadTags()
    }

    /// 使用已有的 Tag 数组初始化已选标签（用于编辑回填）
    func seedSelectedTags(with tagNames: [String]) {
        let seeded = tagNames.map { name in
            tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? Tag(name: name)
        }
        selectedTags = seeded
    }

    func addExistingTag(_ tag: Tag) {
        guard !selectedTags.contains(tag) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedTags.append(tag)
            inputText = ""
        }
    }

    /// 将输入框中的文字创建为新标签（或选中已有标签）并持久化
    func createAndAddNewTag() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            addExistingTag(existing)
            return
        }

        let newTag = Tag(name: trimmed, hexColor: tagColor(for: trimmed), sortOrder: Int32(tags.count))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedTags.append(newTag)
            inputText = ""
        }
        Task {
            await referenceData.addTag(name: trimmed)
        }
    }

    func removeTag(_ tag: Tag) {
        selectedTags.removeAll { $0 == tag }
    }

    /// 从全局标签列表中删除标签（用于标签管理页面）
    func deleteTag(_ tag: Tag) async {
        await referenceData.removeTag(tag.id)
        selectedTags.removeAll { $0.id == tag.id }
    }

    /// 删除最后一个全局标签（用于标签管理页面的退格删除交互）
    func removeLastTag() {
        guard inputText.isEmpty, let last = tags.last else { return }
        Task {
            await deleteTag(last)
        }
    }
}
