/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ExportDataView.swift
/// created on: 29/08/2026
/// ------------------------------------------------------------------
///
/// 明文导出界面：选择格式 + 勾选条目类型 → 生成文件 → 系统保存面板。
///
/// 与「备份」的差异：备份产出加密的 .vgbackup 用于恢复，导出产出明文的
/// CSV / JSON 用于迁移，因此底部固定展示未加密风险提示。
/// ------------------------------------------------------------------

import SwiftUI

struct ExportDataView: View {

    /// 导出结果通过共享的设置弹窗回传给设置页（与导入/备份保持一致）
    @ObservedObject var settingsVM: SettingsViewModel

    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case loaded(VaultExportSnapshot)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var selectedItemTypes: Set<VaultExportItemType> = []
    @State private var format: VaultExportFormat = .csv

    @State private var isPreparing = false
    @State private var exportError: String?
    @State private var exportDocument: VaultExportDocument?
    @State private var showingExporter = false
    /// 本次导出生成的文件名与条目数（保存面板与结果对话框共用）
    @State private var exportedFileName = ""
    @State private var exportedItemCount = 0

    var body: some View {
        NavigationStack {
            content
                .background(SettingsBackground())
                .navigationTitle(AppLocale.string("Export"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task { await load() }
                .fileExporter(
                    isPresented: $showingExporter,
                    document: exportDocument,
                    contentType: format.contentType,
                    defaultFilename: Self.defaultFilename(for: format)
                ) { result in
                    exportDocument = nil
                    switch result {
                    case .success:
                        settingsVM.alert = .operationResult(
                            DataOperationResult(
                                operation: .dataExport,
                                succeeded: true,
                                fileName: exportedFileName,
                                itemCount: exportedItemCount,
                                skippedCount: 0,
                                errorMessage: nil
                            )
                        )
                    case .failure(let error):
                        settingsVM.alert = .operationResult(
                            DataOperationResult(
                                operation: .dataExport,
                                succeeded: false,
                                fileName: exportedFileName,
                                itemCount: 0,
                                skippedCount: 0,
                                errorMessage: AppLocale.string(
                                    "Export failed: \(error.localizedDescription)")
                            )
                        )
                    }
                    dismiss()
                }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isPreparing)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(AppLocale.string("Reading vault..."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.errorColor)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let snapshot):
            selectionList(snapshot: snapshot)
        }
    }

    private func selectionList(snapshot: VaultExportSnapshot) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Picker(AppLocale.string("Format"), selection: $format) {
                        ForEach(VaultExportFormat.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(format.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    ForEach(VaultExportItemType.allCases) { itemType in
                        ItemTypeToggleRow(
                            type: itemType,
                            count: snapshot.itemCount(for: itemType),
                            isSelected: selectedItemTypes.contains(itemType)
                        ) {
                            toggle(itemType)
                        }
                    }
                } header: {
                    HStack {
                        Text(AppLocale.string("Item Types"))
                        Spacer()
                        Button(
                            allSelected
                                ? AppLocale.string("Deselect All")
                                : AppLocale.string("Select All")
                        ) {
                            toggleAll()
                        }
                        .disabled(itemTypes.isEmpty)
                    }
                } footer: {
                    Text(AppLocale.string("Items in the Trash are not exported."))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            footerView(snapshot: snapshot)
        }
    }

    private func footerView(snapshot: VaultExportSnapshot) -> some View {
        VStack(spacing: 12) {
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundColor(.errorColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label {
                    Text(
                        AppLocale.string(
                            "Exported files are not encrypted. Keep them somewhere safe and delete them when you are done."
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.errorColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryActionButton(
                title: AppLocale.string("Export \(snapshot.itemCount(in: selectedItemTypes)) Items"),
                isLoading: isPreparing,
                isEnabled: canExport
            ) {
                prepareExport(snapshot: snapshot)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.bar)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(AppLocale.string("Cancel")) { dismiss() }
        }
    }

    // MARK: - 逻辑

    private var itemTypes: [VaultExportItemType] { VaultExportItemType.allCases }

    private var allSelected: Bool {
        guard !itemTypes.isEmpty else { return false }
        return selectedItemTypes.count == itemTypes.count
    }

    private var canExport: Bool {
        !selectedItemTypes.isEmpty && !isPreparing
    }

    private func load() async {
        do {
            let snapshot = try await VaultExportService().loadSnapshot()
            selectedItemTypes = Set(snapshot.allItemTypes)
            loadState = .loaded(snapshot)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func toggle(_ type: VaultExportItemType) {
        if selectedItemTypes.contains(type) {
            selectedItemTypes.remove(type)
        } else {
            selectedItemTypes.insert(type)
        }
        exportError = nil
    }

    private func toggleAll() {
        if allSelected {
            selectedItemTypes.removeAll()
        } else {
            selectedItemTypes = Set(itemTypes)
        }
        exportError = nil
    }

    private func prepareExport(snapshot: VaultExportSnapshot) {
        guard !isPreparing, !selectedItemTypes.isEmpty else { return }

        isPreparing = true
        exportError = nil

        let itemTypes = selectedItemTypes
        let format = self.format

        Task.detached(priority: .userInitiated) {
            let service = VaultExportService()
            do {
                let data = try service.makeExportData(
                    snapshot: snapshot,
                    format: format,
                    itemTypes: itemTypes
                )
                await MainActor.run {
                    isPreparing = false
                    exportDocument = VaultExportDocument(data: data)
                    exportedFileName = Self.defaultFilename(for: format)
                    exportedItemCount = snapshot.itemCount(in: itemTypes)
                    showingExporter = true
                }
            } catch {
                await MainActor.run {
                    isPreparing = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private static func defaultFilename(for format: VaultExportFormat) -> String {
        VaultExportService.defaultFilename(for: format)
    }
}

// MARK: - 条目类型勾选行

private struct ItemTypeToggleRow: View {
    let type: VaultExportItemType
    let count: Int
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(
                        isSelected ? .primaryBrandColor : Color.secondary.opacity(0.45))

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primaryBrandColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: type.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text(type.displayName)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundColor(count > 0 ? .secondary : Color.secondary.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExportDataView(settingsVM: SettingsViewModel())
}
