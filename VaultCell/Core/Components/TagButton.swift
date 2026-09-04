//
//  TagButton.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/12.
//

import SwiftUI

struct TagButton: View {
    let tag: String
    let isSelected: Bool
    var isEditMode: Bool = false
    let onTap: () -> Void
    var onLongPress: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var wiggle = false

    var body: some View {
        ZStack {
            Text(tag)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color(.systemGray5) : Color(.systemGray))
                .cornerRadius(.infinity)
            /*
            if !isEditMode {
                VStack(alignment: .trailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
            */
        }
        // 编辑模式：右上角删除按钮
        .overlay(alignment: .topTrailing) {
            if isEditMode {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .background(Circle().fill(Color(.systemBackground)))
                }
                .buttonStyle(.borderless)
                .offset(x: 6, y: -6)
            }
        }
        // 编辑模式：晃动动画
        .rotationEffect(.degrees(isEditMode ? (wiggle ? 2 : -2) : 0))
        .animation(
            isEditMode
                ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.2),
            value: wiggle
        )
        .onChange(of: isEditMode) { oldValue, newValue in
            if newValue {
                wiggle.toggle()
            } else {
                wiggle = false
            }
        }
        .onTapGesture {
            if isEditMode {
                // 编辑模式下点击：退出编辑模式
                onLongPress()
            } else {
                onTap()
            }
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}
