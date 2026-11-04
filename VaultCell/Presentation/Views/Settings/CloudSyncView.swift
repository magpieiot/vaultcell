/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CloudSyncView.swift
/// created on: 04/11/2026
/// ------------------------------------------------------------------

import SwiftUI
import UIKit

/// 「同步与备份」子页：顶部说明卡片 + iCloud 同步状态卡片。
///
/// 设置 / 导入 / 导出三个阶段只由 `AppState` 的真实同步回执推导，
/// 不使用计时器推测云端进度；开关与重试直连现有的 CKSyncEngine 链路。
struct CloudSyncView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 参考图中循环箭头的紫色
    private let accent = Color(red: 0.65, green: 0.24, blue: 0.90)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Sync & Backup")
                    .font(.system(size: 32, weight: .heavy))

                heroCard

                Text("iCloud sync")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)

                statusCard

                Text("Turning off iCloud sync keeps the data on this device, but changes will no longer sync to your other devices.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        // 保留系统导航栏（可侧滑返回），但用参考图中的圆形返回按钮替换默认样式
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backButton }
        }
        // 二级页面隐藏底部浮动 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(cardColor))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
    }

    // MARK: - 说明卡片

    private var heroCard: some View {
        VStack(spacing: 14) {
            Image(systemName: syncSymbol)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(accent)
                .frame(height: 62)

            Text("Keep your data in sync")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Your data stays up to date across all your devices and moves with you when you switch to a new one. It is stored in your private iCloud account.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 26)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 时钟 + 双箭头的 SF Symbol 若在当前系统缺失，退回普通循环箭头
    private var syncSymbol: String {
        UIImage(systemName: "clock.arrow.2.circlepath") == nil
            ? "arrow.triangle.2.circlepath" : "clock.arrow.2.circlepath"
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: syncEnabled) {
                Text("iCloud sync")
                    .font(.system(size: 17))
            }
            .tint(.successColor)
            .disabled(appState.syncStatus == .inProgress)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)

            rowDivider

            if let message = errorMessage {
                errorRow(message: message)
                rowDivider
            }

            statusRow(title: "Setup", value: setupStatus)
            rowDivider
            statusRow(title: "Import", value: transferStatus)
            rowDivider
            statusRow(title: "Export", value: transferStatus)
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var syncEnabled: Binding<Bool> {
        Binding(
            get: { appState.isCloudSyncEnabled },
            set: { enabled in
                Task { await appState.setCloudSyncEnabled(enabled) }
            }
        )
    }

    private var errorMessage: String? {
        if case .failed(let message) = appState.syncStatus { return message }
        return nil
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Error")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.errorColor)
                Spacer(minLength: 12)
                Button {
                    Task { await appState.retryCloudSync() }
                } label: {
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func statusRow(title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 17))
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 20)
    }

    private var cardColor: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    // MARK: - 状态文案

    /// CloudKit 引擎初始化对应「设置」阶段；失败时它先于导入 / 导出中断。
    private var setupStatus: String {
        switch appState.syncStatus {
        case .idle:
            return appState.isCloudSyncEnabled
                ? AppLocale.string("Enabled") : AppLocale.string("Not started")
        case .inProgress:
            return AppLocale.string("Sync in progress...")
        case .completed:
            return completedStatus
        case .failed:
            return failedStatus
        }
    }

    /// 一次 `synchronize()` 同时包含从 iCloud 拉取与向 iCloud 推送，两个阶段共用同一份回执。
    private var transferStatus: String {
        switch appState.syncStatus {
        case .inProgress:
            return AppLocale.string("Sync in progress...")
        case .completed:
            return completedStatus
        default:
            return AppLocale.string("Not started")
        }
    }

    private var completedStatus: String {
        guard appState.lastSyncDate != nil else { return AppLocale.string("Sync completed") }
        return String(format: AppLocale.string("Completed: %@"), statusTime)
    }

    private var failedStatus: String {
        guard appState.lastSyncDate != nil else { return AppLocale.string("Sync failed") }
        return String(format: AppLocale.string("Failed: %@"), statusTime)
    }

    /// 用系统相对日期格式得到「今天 12:52 / Today, 12:52」这类展示文本。
    private var statusTime: String {
        guard let date = appState.lastSyncDate else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguage.current.bcp47 ?? Locale.current.identifier)
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
