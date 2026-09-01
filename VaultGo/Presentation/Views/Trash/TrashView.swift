//
//  TrashView.swift
//  VaultGo
//
//  回收站：展示已软删除的密码/密码/PIN/银行卡/安全笔记，30 天后物理清理。
//

import SwiftUI

/// 回收站统一条目，用于在列表中展示和操作
struct TrashItem: Identifiable {
    enum Kind: String {
        case password
        case pincode
        case bankcard
        case safeNote

        var iconName: String {
            switch self {
            case .password: return "key.fill"
            case .pincode: return "lock.fill"
            case .bankcard: return "creditcard.fill"
            case .safeNote: return "note.text"
            }
        }

        var displayName: String {
            switch self {
            case .password: return String(localized: "Password")
            case .pincode: return String(localized: "Pincode")
            case .bankcard: return String(localized: "BankCard")
            case .safeNote: return String(localized: "Safe Note")
            }
        }
    }

    let id: UUID
    let kind: Kind
    let title: String
    let deletedAt: Date
}

struct TrashView: View {
    @EnvironmentObject private var vaultListViewModel: VaultListViewModel
    @EnvironmentObject private var safeNoteService: SafeNoteVaultService

    @State private var trashedVaultItems: [VaultItem] = []
    @State private var trashedSafeNotes: [SafeNote] = []
    @State private var isLoading: Bool = false
    @State private var showingClearConfirmation: Bool = false

    private let retentionDays: Int = 30

    var body: some View {
        NavigationStack {
            List {
                if trashItems.isEmpty && !isLoading {
                    emptyState
                } else {
                    ForEach(trashItems) { item in
                        trashRow(for: item)
                    }
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !trashItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Empty Trash") {
                            showingClearConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .presentationDetents([(trashItems.isEmpty ? .medium : .large)])
            .alert("Are you sure to Empty Trash", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Empty", role: .destructive) {
                    Task { await clearAll() }
                }
            } message: {
                Text(
                    "After emptying, all items in the Trash will be permanently deleted. This action cannot be undone."
                )
            }
            .task {
                await loadTrashed()
            }
        }
    }

    // MARK: - 数据

    private var trashItems: [TrashItem] {
        var items: [TrashItem] = []
        for vaultItem in trashedVaultItems {
            switch vaultItem {
            case .password(let entry):
                items.append(
                    TrashItem(
                        id: entry.id, kind: .password, title: entry.siteName,
                        deletedAt: entry.deletedAt ?? .distantPast))
            case .pincode(let entry):
                items.append(
                    TrashItem(
                        id: entry.id, kind: .pincode, title: entry.title,
                        deletedAt: entry.deletedAt ?? .distantPast))
            case .bankcard(let entry):
                items.append(
                    TrashItem(
                        id: entry.id, kind: .bankcard, title: entry.bankName,
                        deletedAt: entry.deletedAt ?? .distantPast))
            }
        }
        for note in trashedSafeNotes {
            items.append(
                TrashItem(
                    id: note.id, kind: .safeNote, title: note.title,
                    deletedAt: note.deletedAt ?? .distantPast))
        }
        // 按删除时间降序排列
        return items.sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: - 视图

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Trash is Empty")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Deleted items are kept for 30 days")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .listRowBackground(Color.clear)
    }

    private func trashRow(for item: TrashItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.iconName)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.kind.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(remainingDaysText(deletedAt: item.deletedAt))
                        .font(.caption)
                        .foregroundColor(
                            remainingDays(deletedAt: item.deletedAt) <= 7 ? .orange : .secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await restore(item) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button {
                    Task { await permanentlyDelete(item) }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task { await permanentlyDelete(item) }
            } label: {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
            .tint(.red)

            Button {
                Task { await restore(item) }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
    }

    // MARK: - 操作

    private func loadTrashed() async {
        isLoading = true
        trashedVaultItems = (try? await vaultListViewModel.loadTrashed()) ?? []
        await safeNoteService.loadTrashedNotes()
        trashedSafeNotes = safeNoteService.trashedNotes
        isLoading = false
    }

    private func restore(_ item: TrashItem) async {
        switch item.kind {
        case .password, .pincode, .bankcard:
            if let vaultItem = trashedVaultItems.first(where: { $0.id == item.id }) {
                try? await vaultListViewModel.restoreTrashed(vaultItem)
            }
        case .safeNote:
            await safeNoteService.restoreNote(item.id)
        }
        await loadTrashed()
    }

    private func permanentlyDelete(_ item: TrashItem) async {
        switch item.kind {
        case .password, .pincode, .bankcard:
            if let vaultItem = trashedVaultItems.first(where: { $0.id == item.id }) {
                try? await vaultListViewModel.permanentlyDeleteTrashed(vaultItem)
            }
        case .safeNote:
            await safeNoteService.permanentlyDeleteNote(item.id)
        }
        await loadTrashed()
    }

    private func clearAll() async {
        for item in trashItems {
            await permanentlyDelete(item)
        }
    }

    // MARK: - 工具

    private func remainingDays(deletedAt: Date) -> Int {
        let elapsed = Date().timeIntervalSince(deletedAt)
        let totalRetention = Double(retentionDays) * 86400
        let remaining = totalRetention - elapsed
        return max(0, Int(ceil(remaining / 86400)))
    }

    private func remainingDaysText(deletedAt: Date) -> String {
        let days = remainingDays(deletedAt: deletedAt)
        if days <= 0 {
            return "Expiring soon"
        }
        return "\(days) days left"
    }
}

#Preview {
    NavigationStack {
        TrashView()
            .environmentObject(VaultListViewModel(referenceData: ReferenceDataService()))
            .environmentObject(SafeNoteVaultService())
    }
}
