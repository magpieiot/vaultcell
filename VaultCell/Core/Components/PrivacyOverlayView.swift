/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PrivacyOverlayView.swift
/// created on: 01/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 快照保护遮罩视图
///
/// 当 App 切入后台时，系统会截取当前界面的快照用于 App Switcher。
/// 此遮罩覆盖毛玻璃模糊层 + 品牌 Logo，防止敏感信息在快照中泄露。
/// 仅在 `AppState.shouldShowPrivacyOverlay` 为 `true` 时显示。
struct PrivacyOverlayView: View {
    var body: some View {
        ZStack {
            // 毛玻璃模糊遮罩，使下方敏感内容无法辨认
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.3))

            // 品牌视觉：锁盾图标 + App 名称
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.85))

                Text("VaultCell")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}
