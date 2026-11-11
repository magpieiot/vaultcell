//
//  PincodeDetailView.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/25.
//

import SwiftUI

/// PIN Code 详情视图
/// 展示单条 PincodeEntry 的完整信息，包括标题、PIN 码、历史记录、备注、标签等
struct PincodeDetailView: View {
    let entry: PincodeEntry
    var onUpdate: ((PincodeEntry) async -> Void)?
    var onDelete: ((PincodeEntry) async -> Void)?
    @ObservedObject var tagSelection: TagSelectionViewModel
    let referenceData: ReferenceDataService

    @State private var isPincodeVisible = false
    @State private var showingCopied = false
    @State private var showingEditSheet = false

    @EnvironmentObject var viewModel: VaultListViewModel

    private var category: PasswordCategory?  {
        viewModel.categories.first { $0.id == entry.categoryID }
    }

    var body: some View {
        List {
            Section {
                headerSection
            } footer: {
                if !(entry.tags ?? []).isEmpty {
                    TagListView(tags: entry.tags ?? [])
                }
            }
            .listRowBackground(Color.backgroundFor(domain: entry.title))
            
            if let history = entry.pincodeHistory, !history.isEmpty {
                historySection
            }

            if let notes = entry.notes, !notes.isEmpty {
                notesSection
            }

            if !(entry.customFields ?? []).isEmpty {
                customFieldSection
            }

            otherInfoSection
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.horizontal, 16)
        }
        .listStyle(.sidebar)
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
            
        }
        .sheet(isPresented: $showingEditSheet) {
            PincodeFormView(
                formModel: PincodeFormModel(mode: .edit(entry), referenceData: referenceData),
                onSave: { updatedEntry in
                    await onUpdate?(updatedEntry)
                },
                onSoftDelete: { deletedEntry in
                    await onDelete?(deletedEntry)
                }
            )
        }
        .preference(key: TabBarVisibilityKey.self, value: true)
    }

    // MARK: - Header

    private var headerSection: some View {
        
        VStack(alignment: .center, spacing: 8) {
            /// 分类标签
            HStack {
                CategoryLabel(category: category!)

                Spacer()
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 24, height: 24)
                }
            }

            if isPincodeVisible {
                Text(entry.pincode)
                    .font(.system(size: 48, design: .monospaced))
            } else {
                Text(String(repeating: "•", count: min(entry.pincode.count, 16)))
                    .font(.system(size: 48, design: .monospaced))
            }
            
            HStack {
                Button {
                    isPincodeVisible.toggle()
                } label: {
                    Image(systemName: isPincodeVisible ? "eye.slash" : "eye")
                        .foregroundColor(Color.tintFor(domain: entry.title))
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 4)

                Button {
                    copyToClipboard(entry.pincode)
                } label: {
                    Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(showingCopied ? .green : Color.tintFor(domain: entry.title))
                }
                .buttonStyle(.borderless)
            }

            /// PIN Code 类型标签
            if entry.isNumericOnly {
                Text("Numeric PIN")
                    .font(.caption)
                    .foregroundColor(Color.tintFor(domain: entry.title))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .cornerRadius(8)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pincode Row

    private var pincodeRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pincode")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isPincodeVisible {
                    Text(entry.pincode)
                        .font(.system(.headline, design: .monospaced))
                } else {
                    Text(String(repeating: "•", count: min(entry.pincode.count, 16)))
                        .font(.system(.headline, design: .monospaced))
                }
            }

            Spacer()

            Button {
                isPincodeVisible.toggle()
            } label: {
                Image(systemName: isPincodeVisible ? "eye.slash" : "eye")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 4)

            Button {
                copyToClipboard(entry.pincode)
            } label: {
                Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(showingCopied ? .green : .orange)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section("PIN History") {
            ForEach(historyEntries) { item in
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(maskedPincode(item.pincode))
                            .font(.system(.subheadline, design: .monospaced))
                        Text(item.changedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            Text(entry.notes ?? "")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Custom Fields

    private var customFieldSection: some View {
        Section("Custom Fields") {
            ForEach(entry.customFields ?? [], id: \.name) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(field.value)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Other Info

    private var otherInfoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Source: \((entry.dataSource ?? .manual).displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Created: \((entry.createdAt ?? Date()).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Updated: \((entry.updatedAt ?? Date()).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tag Header
    /*
    private var tagHeader: some View {
        HStack {
            ForEach(entry.tags ?? [], id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
                
            }
        }
    }
    */

    // MARK: - Helpers

    private var historyEntries: [PincodeHistoryEntry] {
        (entry.pincodeHistory ?? []).sorted { $0.changedAt > $1.changedAt }
    }

    private func maskedPincode(_ value: String) -> String {
        String(repeating: "•", count: min(value.count, 8))
    }

    private func copyToClipboard(_ text: String) {
        let seconds = ClipboardService.shared.copy(text)
        ToastCenter.shared.toast = .copied(clearAfter: seconds)
        showingCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopied = false
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

#Preview {
    let entry = PincodeEntry(
        title: "Phone Lock PIN",
        pincode: "1234",
        isNumericOnly: true,
        notes: "手机锁屏 PIN",
        categoryID: PasswordCategory.systemDefaults[0].id,
        tags: ["device", "seed"],
        isFavorite: true
    )

    let referenceData = ReferenceDataService()

    NavigationStack {
        PincodeDetailView(
            entry: entry,
            tagSelection: TagSelectionViewModel(referenceData: referenceData),
            referenceData: referenceData
        )
    }
}
