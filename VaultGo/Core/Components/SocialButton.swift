/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// SocialButton.swift
/// created on: 12/06/2026
/// ------------------------------------------------------------------

//
//  SocialButton.swift
//  VaultGo
//
//  Created by gavanwang on 2026/6/12.
//

import SwiftUI

struct SocialButton: View {
    var label: String
    var assetName: String? = nil
    var systemName: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let iconSize = min(max(side * 0.5, 22), 44)

                Group {
                    if let assetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                    } else if let systemName {
                        Image(systemName: systemName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "questionmark")
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(Text(label))
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}


struct customNaviButton: View {
    let systemName: String
    var action: () -> Void = {}
    
    var body: some View {
        Button (action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
    }
}

/// 复制到剪贴板按钮
/// 点击后将 `text` 写入系统剪贴板，图标短暂变为 checkmark，延迟 `time` 秒后恢复。
/// `backgroundLight: true` 使用浅色背景，false 使用深色背景。
struct Copy2ClipboardButton: View {
    let text: String
    var time: Double = 2.0
    var backgroundLight: Bool = true
    var action: (() -> Void)? = nil

    @State private var isCopied = false

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(backgroundColor)
                        .overlay(
                            Circle()
                                .stroke(borderColor, lineWidth: 0.5)
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isCopied)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appearance

    private var foregroundColor: Color {
        backgroundLight ? .secondary : .white
    }

    private var backgroundColor: Color {
        backgroundLight ? Color(.secondarySystemBackground) : Color(.label).opacity(0.8)
    }

    private var borderColor: Color {
        backgroundLight ? Color.black.opacity(0.05) : Color.white.opacity(0.2)
    }

    // MARK: - Action

    /// 执行复制操作，图标变为 checkmark 并在延迟后恢复
    /// 复制动作由 ClipboardService 完成
    private func copyToClipboard() {
        ClipboardService.shared.copyToClipboard(text)
        action?()

        isCopied = true
        // 轻量触觉反馈，提示用户复制已完成
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + max(time, 0.1)) {
            isCopied = false
        }
    }
}
