//
//  CategoryManagementView.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/16.
//
// MARK: - 分类管理
import SwiftUI

struct CategoryManagementView: View {
    @ObservedObject var viewModel: VaultListViewModel
    @Environment(\.editMode) private var editMode

    @State private var categories: [PasswordCategory] = []

    /// 删除自定义分类时，条目迁移到的兜底分类名（与 PasswordCategory.defaultCategoryID 保持一致）
    private var fallbackCategoryName: String {
        viewModel.referenceData.category(for: PasswordCategory.defaultCategoryID)?.name ?? "Life"
    }

    @State private var showingAddSheet = false
    @State private var categoryToDelete: PasswordCategory?
    @State private var isProcessing = false
    @State private var resultMessage: String?

    private let systemBadgeColor = Color.gray

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    CategoryRow(
                        category: category,
                        entryCount: entryCount(for: category),
                        isProcessing: isProcessing,
                        onDelete: category.isSystem ? nil : { categoryToDelete = category }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !category.isSystem {
                            Button(role: .destructive) {
                                categoryToDelete = category
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("List (\(categories.count))")
            } footer: {
                Text("Long press and drag to reorder. System default categories cannot be deleted. Deleting a custom category will reassign its entries to \"\(fallbackCategoryName)\".")
                    .font(.caption)
            }
        }
        .navigationTitle("Vault Categories")
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .disabled(isProcessing)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCategorySheet(viewModel: viewModel) {
                Task { await refresh() }
            }
        }
        .alert("Delete Category?", isPresented: Binding(
            get: { categoryToDelete != nil },
            set: { if !$0 { categoryToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete {
                    Task { await deleteCategory(category) }
                }
            }
            Button("Cancel", role: .cancel) { categoryToDelete = nil }
        } message: {
            if let category = categoryToDelete {
                let count = entryCount(for: category)
                if count > 0 {
                    Text("The category \"\(category.name)\" contains \(count) entries. Deleting it will reassign them to \"\(fallbackCategoryName)\". This action cannot be undone.")
                } else {
                    Text("Are you sure to delete the category \"\(category.name)\"? This action cannot be undone.")
                }
            } else {
                Text("")
            }
        }
        .alert("Category Update", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } })
        ) {
            Button("Confirm", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        await viewModel.referenceData.loadCategories()
        categories = viewModel.referenceData.categories
    }

    /// 该分类下的条目数量（密码 / PIN 码 / 银行卡合计）
    private func entryCount(for category: PasswordCategory) -> Int {
        viewModel.items.filter { $0.categoryID == category.id }.count
    }

    private func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        let reordered = categories
        Task {
            await viewModel.referenceData.reorderCategories(reordered)
            await MainActor.run {
                categories = viewModel.referenceData.categories
            }
        }
    }

    private func deleteCategory(_ category: PasswordCategory) async {
        isProcessing = true
        defer { isProcessing = false }
        // 迁移数量需要在删除前统计（删除后条目已归入兜底分类）
        let movedCount = entryCount(for: category)
        let fallbackName = fallbackCategoryName
        let fallbackID = PasswordCategory.defaultCategoryID
        // 分类下的条目由服务层先行迁移到兜底分类，再删除分类本身
        let deleted = await viewModel.referenceData.deleteCategory(
            category.id, reassignTo: fallbackID)
        categoryToDelete = nil
        guard deleted else {
            resultMessage = viewModel.referenceData.errorMessage
                ?? String(
                    format: AppLocale.string("Unable to delete the category \"%@\"."),
                    category.name)
            return
        }
        // 列表正按被删除的分类筛选时清空筛选，避免删除后列表变空且找不到入口
        if viewModel.selectedCategoryID == category.id {
            viewModel.selectedCategoryID = nil
        }
        await viewModel.loadItems()
        await refresh()
        resultMessage = movedCount > 0
            ? String(
                format: AppLocale.string("Category \"%@\" has been deleted, and its entries have been reassigned to \"%@\"."
                ), category.name, fallbackName)
            : String(
                format: AppLocale.string("Category \"%@\" has been deleted."), category.name)
    }
}

private struct CategoryRow: View {
    let category: PasswordCategory
    let entryCount: Int
    let isProcessing: Bool
    /// 删除回调；系统默认分类传 nil，不显示删除按钮
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: category.hexColor))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: category.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(.body)
                    if category.isSystem {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.gray)
                            .clipShape(Capsule())
                    }
                }
                Text("\(entryCount) Items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isProcessing {
                ProgressView()
            } else if let onDelete {
                // 行内删除入口：让自定义分类不必依赖滑动手势就能删除
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete"))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新增分类

struct AddCategorySheet: View {
    @ObservedObject var viewModel: VaultListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedIcon: String = AddCategorySheet.iconOptions[0]
    @State private var selectedColor: String = AddCategorySheet.colorOptions[0]
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSaved: () -> Void

    private static let iconOptions: [String] = [
        "folder.fill", "person.2.fill", "briefcase.fill", "banknote.fill",
        "cart.fill", "gamecontroller.fill", "globe.fill", "lock.fill",
        "key.fill", "shield.fill", "creditcard.fill", "airplane.fill",
        "house.fill", "gearshape.fill", "bookmark.fill", "book.fill"
    ]

    private static let colorOptions: [String] = [
        "#FF9500", "#007AFF", "#34C759", "#AF52DE",
        "#FF2D55", "#5856D6", "#30B0C7", "#8E8E93",
        "#FFD60A", "#FF6B35", "#5AC8FA", "#BF5AF2"
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        viewModel.referenceData.categories.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Category Name", text: $name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(AddCategorySheet.iconOptions, id: \.self) { icon in
                            iconCell(icon)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(AddCategorySheet.colorOptions, id: \.self) { color in
                            colorCell(color)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Preview") {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: selectedColor))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                        Text(trimmedName.isEmpty ? "New Category" : trimmedName)
                            .font(.body)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").bold()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func iconCell(_ icon: String) -> some View {
        Button(action: { selectedIcon = icon }) {
            Circle()
                .fill(selectedIcon == icon ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(selectedIcon == icon ? .accentColor : .primary)
                )
                .overlay(
                    Circle()
                        .stroke(selectedIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func colorCell(_ color: String) -> some View {
        Button(action: { selectedColor = color }) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: selectedColor == color ? "checkmark" : "")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            await viewModel.referenceData.addCategory(
                name: trimmedName,
                icon: selectedIcon,
                hexColor: selectedColor
            )
            await MainActor.run {
                isSaving = false
                onSaved()
                dismiss()
            }
        }
    }
}

/*
extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
*/

#Preview {
    CategoryManagementView(viewModel: VaultListViewModel(referenceData: ReferenceDataService()))
}
