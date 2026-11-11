/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppStateViews.swift
/// ------------------------------------------------------------------

import SwiftUI

/// 统一加载态：避免各页各自写 ProgressView 与不同的对齐方式
struct AppLoadingStateView: View {
    var title: LocalizedStringKey = "Loading..."

    var body: some View {
        ProgressView {
            Text(title)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 统一空状态：整页用 `.page`，列表内嵌用 `.inline`
struct AppEmptyStateView: View {
    enum Style {
        case page
        case inline
    }

    let title: LocalizedStringKey
    let systemImage: String
    var description: LocalizedStringKey? = nil
    /// 由 ViewModel 拼好的说明文案（非字面量 key）走这里
    var descriptionText: String? = nil
    var style: Style = .page

    private var descriptionView: Text? {
        if let descriptionText { return Text(descriptionText) }
        if let description { return Text(description) }
        return nil
    }

    var body: some View {
        switch style {
        case .page:
            ContentUnavailableView(
                title, systemImage: systemImage, description: descriptionView)
        case .inline:
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let descriptionView {
                    descriptionView
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }
}

/// 统一错误态：错误原因与重试入口放在一起，替代只有「确定」的通用弹窗
struct AppErrorStateView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// 破坏性操作确认：统一「取消 + destructive 主操作」的按钮角色与顺序
struct DestructiveConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let confirmLabel: LocalizedStringKey
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(confirmLabel, role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func destructiveConfirmation(
        _ title: LocalizedStringKey,
        isPresented: Binding<Bool>,
        message: LocalizedStringKey? = nil,
        confirmLabel: LocalizedStringKey = "Delete",
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            DestructiveConfirmationModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                onConfirm: onConfirm))
    }
}
