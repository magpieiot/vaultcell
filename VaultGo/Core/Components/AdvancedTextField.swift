//
//  AdvancedTextField.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/5.
//

import SwiftUI

struct AdvancedTextField: View {
    // 1. 单一数据源：title 只在这里定义一次
    let iconName: String
    let iconColor: Color
    let title: String
    let unFocusedColor: Color = .secondary
    let focusedColor: Color = Color.primaryBrandColor
    let changedColor: Color = Color.red
    var keyboardType: UIKeyboardType = .default
    // 是否启用「左滑删除」能力：为 true 时左侧显示红色 minus 按钮
    var isItemDeleteEnabled: Bool = false
    // 点击红色 Delete 按钮后的回调
    var onDeleteItem: (() -> Void)? = nil
    // 尾部辅助视图（如下拉菜单），与 xmark 按钮在同一行内协调排列，避免重叠
    var trailingAccessory: (() -> AnyView)? = nil

    @Binding var text: String

    // 内部状态管理
    @FocusState private var internalFocus: Bool
    // 外部可传入的焦点绑定，提供后接管 internalFocus（用于外部 View 编程式聚焦）
    var externalFocus: FocusState<Bool>.Binding? = nil
    // 删除模式：点击 minus 后激活，输入框左滑并显示 Delete 按钮
    @State private var isDeleteModeActive: Bool = false

    /// 当前是否聚焦（优先外部绑定，回退内部 @FocusState）
    private var isFocused: Bool {
        externalFocus?.wrappedValue ?? internalFocus
    }

    /// 设置焦点（优先外部绑定，回退内部 @FocusState）
    private func setFocus(_ value: Bool) {
        if let externalFocus {
            externalFocus.wrappedValue = value
        } else {
            internalFocus = value
        }
    }

    // 动态计算标签位置和大小
    private var isLabelFloating: Bool {
        isFocused || !text.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            // 左侧 minus 按钮：仅当启用删除能力且未激活删除模式时显示
            if isItemDeleteEnabled && !isDeleteModeActive {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isDeleteModeActive = true
                        setFocus(false)
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.body.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // 主内容区（图标 + 标题/输入区 + 清除按钮）
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {

                    // 2. 外部显示的 Title (带动画)
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(isFocused ? focusedColor : unFocusedColor)
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.7), value: isLabelFloating)

                    // 3. 核心输入区

                    // 原始的 TextField
                    TextField("", text: $text)
                        .font(.body)
                        .focused(externalFocus ?? $internalFocus)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        // 删除模式激活时禁止输入框接收点击（避免进入编辑模式），
                        // 事件穿透到父视图 onTapGesture 统一执行收起逻辑
                        .allowsHitTesting(!isDeleteModeActive)
                }

                // 清除按钮：仅在聚焦且输入区不为空时显示，点击清空内容
                if isFocused && !text.isEmpty {
                    Button(action: {
                        text = ""
                        setFocus(true)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.isEmpty)
                }

                // 尾部辅助视图（如下拉菜单），与 xmark 间距 4pt 避免重叠
                if let trailingAccessory {
                    trailingAccessory()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧 Delete 按钮：删除模式激活后显示，点击触发 onDeleteItem 回调
            if isDeleteModeActive {
                Button(action: {
                    onDeleteItem?()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isDeleteModeActive = false
                    }
                }) {
                    Text("Delete")
                        .font(.body.weight(.regular))
                        .foregroundColor(.white)
                        .frame(width: 76, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.leading, isDeleteModeActive ? -64 : 0)
        // 扩大点击区域
        .contentShape(Rectangle())
        .onTapGesture {
            // 与 EditPasswordView「点击 Rescan 左侧区域收起」相同逻辑：
            // 删除模式激活时，点击 Delete 按钮左侧区域即退出删除模式，且不重新聚焦
            if isDeleteModeActive {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isDeleteModeActive = false
                }
            } else {
                // 非删除模式：点击组件任意区域让输入框获得焦点
                setFocus(true)
            }
        }
    }
}

// Preview 预览组件，展示 AdvancedTextField 的实际使用效果
struct AdvancedTextField_Previews: PreviewProvider {

    // 交互式预览包装器，用于展示删除功能
    struct DeleteWrapper: View {
        @State private var text = "标签内容"
        var body: some View {
            AdvancedTextField(
                iconName: "tag",
                iconColor: .orange,
                title: "标签",
                isItemDeleteEnabled: true,
                onDeleteItem: {
                    print("点击了 Delete")
                },
                text: $text
            )
            .padding()
        }
    }

    static var previews: some View {
        Group {
            // 空输入状态的 TextField
            AdvancedTextField(
                iconName: "envelope",
                iconColor: .blue,
                title: "邮箱地址",
                keyboardType: .emailAddress,
                text: .constant("")
            )
            .previewDisplayName("空输入状态")
            .padding()
            .previewLayout(.sizeThatFits)

            // 已有内容的 TextField
            AdvancedTextField(
                iconName: "lock",
                iconColor: .red,
                title: "密码",
                keyboardType: .default,
                text: .constant("123456")
            )
            .previewDisplayName("已输入内容状态")
            .padding()
            .previewLayout(.sizeThatFits)

            // 启用删除能力的交互式预览
            DeleteWrapper()
                .previewDisplayName("删除功能（点击 minus）")
                .previewLayout(.sizeThatFits)
        }
        .previewLayout(.fixed(width: 350, height: 200))
    }
}
