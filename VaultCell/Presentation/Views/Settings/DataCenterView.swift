/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// DataCenterView.swift
/// created on: 05/11/2026
/// ------------------------------------------------------------------

import SwiftUI
import UIKit

/// 「数据中心」子页：数据安全说明 + 导出 / 导入 + 数据存储与清理。
///
/// 导入 / 明文导出 / 重置密码库沿用 `SettingsViewModel` 的既有链路，
/// iCloud 云端清除走 `CloudVaultClearService`；危险操作统一用红色标识。
struct DataCenterView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vaultListViewModel: VaultListViewModel
    @EnvironmentObject private var safeNoteService: SafeNoteVaultService
    @Environment(\.dismiss) private var dismiss

    /// 本页独立持有数据操作 ViewModel，避免与工具中心、同步页的状态互相串改
    @StateObject private var settingsVM = SettingsViewModel()

    @State private var showingExportSheet = false
    @State private var showingResetVerify = false

    /// 与主 App 保持同一个强调色
    private let accent = Color.appAccent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Data Center")
                    .font(.appTitle)

                heroCard

                exportSection

                cleanupSection
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
        // 弹窗挂在本页根层：工具中心的导入选择器与重置弹窗已迁入这里
        .sheet(isPresented: $showingExportSheet) {
            ExportDataView(settingsVM: settingsVM)
        }
        .sheet(isPresented: $showingResetVerify) {
            ResetVaultVerifyView { password in
                await settingsVM.verifyAndReset(masterPassword: password)
            }
        }
        .fileImporter(
            isPresented: $settingsVM.showingFilePicker,
            allowedContentTypes: settingsVM.filePickerContentTypes,
            allowsMultipleSelection: false
        ) { result in
            settingsVM.handleFilePickerResult(result)
        }
        .alert(item: $settingsVM.alert) { alert in
            alertContent(for: alert)
        }
        .onAppear {
            settingsVM.configure(
                appState: appState,
                vaultListViewModel: vaultListViewModel,
                safeNoteService: safeNoteService
            )
        }
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
            Image(systemName: safeSymbol("lock.shield", fallback: "lock.shield.fill"))
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(accent)
                .frame(height: 66)

            Text("Your data is safe")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Your vault is encrypted and stored on this device or in your private iCloud account. We never collect, sell, or share your data.")
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

    // MARK: - 导出 / 导入

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Export Data")

            VStack(spacing: 0) {
                actionRow(
                    icon: "square.and.arrow.up",
                    title: "Export",
                    tint: Color.primaryBrandColor
                ) {
                    showingExportSheet = true
                }

                rowDivider

                actionRow(
                    icon: "square.and.arrow.down",
                    title: "Import",
                    tint: Color.primaryBrandColor,
                    isBusy: settingsVM.isImporting
                ) {
                    settingsVM.presentImportPicker()
                }
            }
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            footerNote("Exported files are not encrypted. Keep them somewhere safe and delete them when you are done.")
        }
    }

    // MARK: - 数据存储与清理

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Data Storage & Cleanup")

            VStack(spacing: 0) {
                actionRow(
                    icon: "trash",
                    title: "Clear Vault",
                    tint: Color.errorColor
                ) {
                    settingsVM.alert = .resetConfirm
                }

                rowDivider

                actionRow(
                    icon: "icloud",
                    title: "Clear iCloud Data",
                    tint: Color.errorColor
                ) {
                    settingsVM.alert = .clearICloudConfirm
                }
            }
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            footerNote("Clearing data cannot be undone. Export an encrypted backup before you continue.")
        }
    }

    // MARK: - 弹窗

    private func alertContent(for alert: SettingsAlert) -> Alert {
        switch alert {
        case .resetConfirm:
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .destructive(Text(AppLocale.string("Reset"))) {
                    settingsVM.alert = nil
                    showingResetVerify = true
                },
                secondaryButton: .cancel()
            )
        case .clearICloudConfirm:
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .destructive(Text(AppLocale.string("Clear"))) {
                    Task { await settingsVM.clearICloudData() }
                },
                secondaryButton: .cancel()
            )
        default:
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(AppLocale.string("OK")))
            )
        }
    }

    // MARK: - 通用组件

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
    }

    private func footerNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }

    private func actionRow(
        icon: String,
        title: LocalizedStringKey,
        tint: Color,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 20)
    }

    private var cardColor: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// SF Symbol 在个别系统版本可能缺失，退回同义符号避免出现空白图标
    private func safeSymbol(_ preferred: String, fallback: String) -> String {
        UIImage(systemName: preferred) == nil ? fallback : preferred
    }
}
