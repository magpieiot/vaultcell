//
//  TagChipView.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/13.
//
import SwiftUI

// 标签胶囊组件
struct TagChipView: View {
    let tag: Tag
    let isEditing: Bool
    var onDelete: () -> Void = {}
    var onTap: () -> Void = {}
    var onLongPress: () -> Void = {}
    
    // 抖动动画的状态
    @State private var jitterAngle: Double = 0
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag.name)
                .font(.subheadline)
                .foregroundColor(tag.color)
            
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .transition(.scale)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tag.color.opacity(0.15))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(tag.color.opacity(0.3), lineWidth: 1))
        .contentShape(Capsule())
        .rotationEffect(.degrees(isEditing ? jitterAngle : 0))
        .onChange(of: isEditing) { _, editing in
            if editing { startJittering() } else { jitterAngle = 0 }
        }
        .onTapGesture {
            if isEditing {
                onDelete()
            } else {
                onTap()
            }
        }
        .onLongPressGesture {
            if !isEditing {
                onLongPress()
            }
        }
    }
    
    // 模拟 iOS 桌面图标的轻微抖动效果
    private func startJittering() {
        let animation = Animation.easeInOut(duration: 0.1).repeatForever(autoreverses: true)
        withAnimation(animation) {
            jitterAngle = 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(animation) { jitterAngle = -1.5 }
        }
    }
}

// 内联输入框组件
struct InlineTagInput: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onBackspace: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("New", text: $text)
                .font(.subheadline)
                .focused(isFocused)
                .frame(minWidth: 40, maxWidth: 120) // 限制最大宽度，防止换行突兀
                .onSubmit(onSubmit)
                .onChange(of: text) { oldValue, newValue in
                    // 🏆 监听退格键：如果旧值非空，新值为空，说明按了退格
                    if oldValue.isEmpty && newValue.isEmpty {
                        onBackspace()
                    }
                    // 自动去除空格，防止用户输入纯空格
                    if newValue.contains(" ") {
                        text = newValue.replacingOccurrences(of: " ", with: "")
                        onSubmit() // 遇到空格自动确认（可选体验）
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .overlay(Capsule().stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
        .clipShape(Capsule())
    }
}
