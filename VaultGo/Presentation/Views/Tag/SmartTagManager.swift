//
//  SmartTagManager.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/29.
//

import SwiftUI

// MARK: - Smart Tag Manager

/// 通用于 PasswordEntry、PincodeEntry、BankcardEntry 等数据的标签编辑。
/// 配合 TagSelectionViewModel 使用，提供标签流式布局、输入推荐和增删交互。
struct SmartTagManager: View {
    @ObservedObject var viewModel: TagSelectionViewModel
    @FocusState private var isFocused: Bool
    @State private var isDeleteMode = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isDeleteMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isDeleteMode = false
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.selectedTags) { tag in
                        TagChipView(
                            tag: tag,
                            isEditing: isDeleteMode,
                            onDelete: {
                                viewModel.removeTag(tag)
                            },
                            onLongPress: {
                                isDeleteMode = true
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                        TextField("Add Tag", text: $viewModel.inputText)
                            .font(.subheadline)
                            .frame(minWidth: 60, maxWidth: 120)
                            .focused($isFocused)
                            .onChange(of: isFocused) { _, newValue in
                                viewModel.isInputFocused = newValue
                                if newValue {
                                    isDeleteMode = false
                                }
                            }
                            .onSubmit {
                                viewModel.createAndAddNewTag()
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5))
                }

                if isFocused || !viewModel.inputText.isEmpty {
                    if viewModel.suggestedTags.isEmpty {
                        Text("No matching tags found. Press enter to create a new tag.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.suggestedTags) { tag in
                                TagChipView(
                                    tag: tag,
                                    isEditing: false,
                                    onTap: {
                                        viewModel.addExistingTag(tag)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedTags)
        .animation(.easeInOut, value: isFocused)
        .animation(.easeInOut, value: isDeleteMode)
    }
}
