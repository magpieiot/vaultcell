import Foundation
import Combine

@MainActor
final class VaultListViewModel: ObservableObject {
    @Published var items: [VaultItem] = []

    @Published var searchQuery: String = ""
    @Published var selectedCategoryID: UUID?
    @Published var selectedTags: [Tag] = []
    @Published var selectedTypes: Set<VaultItemType> = Set(VaultItemType.allCases)
    @Published var sortField: VaultSortField = .updatedAt
    @Published var sortAscending: Bool = false

    /// 收藏置顶：开关在「工具 → 通用」，改动立即落盘并重排列表（默认关闭）
    @Published var pinFavoritesToTop: Bool {
        didSet {
            UserDefaults.standard.set(pinFavoritesToTop, forKey: VaultKey.pinFavoritesToTop)
        }
    }

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedDestination: VaultDestination?

    /// 是否正在呈现"新增条目"全屏流程（由 MainTabView 的 fullScreenCover 绑定）
    @Published var isPresentingAddFlow: Bool = false

    private let vaultListService: VaultListServiceProtocol
    let referenceData: ReferenceDataService
    let tagSelection: TagSelectionViewModel

    /// 订阅凭据交换导入完成通知，导入后自动刷新列表
    private var importCancellable: AnyCancellable?
    /// 订阅 AutoFill 扩展「保存密码」写入通知，回前台时重载列表
    private var autoFillSaveCancellable: AnyCancellable?

    init(
        vaultListService: VaultListServiceProtocol = VaultListService(),
        referenceData: ReferenceDataService
    ) {
        self.vaultListService = vaultListService
        self.referenceData = referenceData
        self.tagSelection = TagSelectionViewModel(referenceData: referenceData)
        self.pinFavoritesToTop = UserDefaults.standard.bool(forKey: VaultKey.pinFavoritesToTop)

        Task {
            await referenceData.reloadAll()
            await loadItems()
        }

        // Credential Exchange 导入完成后刷新列表（系统以 UserActivity 拉起 App，
        // 列表不会自动感知新增条目，这里通过通知触发重载）
        importCancellable = NotificationCenter.default
            .publisher(for: .credentialExchangeDidImport)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.loadItems() }
            }

        // AutoFill 扩展保存密码后刷新列表（扩展写的是同一份共享数据库，
        // 但主 App 的列表不会自动感知跨进程写入）
        autoFillSaveCancellable = NotificationCenter.default
            .publisher(for: .autoFillDidSaveCredential)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.loadItems() }
            }
    }

    var categories: [PasswordCategory] { referenceData.categories }
    var tags: [Tag] { referenceData.tags }

    var filteredItems: [VaultItem] {
        applyFiltersAndSorting(to: items)
    }

    var passwordEntriesForAudit: [PasswordEntry] {
        filteredItems.compactMap {
            guard case let .password(entry) = $0 else { return nil }
            return entry
        }
    }

    func loadItems() async {
        isLoading = true
        errorMessage = nil

        do {
            items = try await vaultListService.loadAll()
            // 每次加载密码库后同步联系人信息，确保最近列表跟随密码库刷新
            let passwordEntries = items.compactMap { item -> PasswordEntry? in
                guard case let .password(entry) = item else { return nil }
                return entry
            }
            UserContactStore.syncFromPasswordEntries(passwordEntries)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 启动懒清理：物理删除超过 30 天保留期的回收站条目
    func purgeExpired() async {
        _ = try? await vaultListService.purgeExpired(retentionDays: 30)
    }

    // MARK: - 回收站操作

    func loadTrashed() async throws -> [VaultItem] {
        try await vaultListService.loadTrashed()
    }

    func restoreTrashed(_ item: VaultItem) async throws {
        do {
            try await vaultListService.restore(item)
            // 恢复成功后同步刷新主列表，确保条目回到 vault list（与 delete/toggleFavorite 保持一致的同步模式）
            await loadItems()
        } catch {
            // 即使调用方用 try? 吞掉错误，也保证错误能被展示
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func permanentlyDeleteTrashed(_ item: VaultItem) async throws {
        try await vaultListService.permanentlyDelete(item)
    }

    func refresh() async {
        await referenceData.reloadAll()

        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await loadItems()
        } else {
            await searchItems()
        }
    }

    func searchItems() async {
        isLoading = true
        errorMessage = nil

        do {
            items = try await vaultListService.searchAll(query: searchQuery)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteItem(_ item: VaultItem) async {
        do {
            try await vaultListService.delete(item)
            items.removeAll { $0.id == item.id && $0.type == item.type }
            selectedDestination = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ item: VaultItem) async {
        do {
            try await vaultListService.toggleFavorite(item)

            if let index = items.firstIndex(where: { $0.id == item.id && $0.type == item.type }) {
                items[index] = toggledFavoriteItem(from: items[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 更新密码条目
    func updatePasswordItem(_ entry: PasswordEntry) async {
        do {
            try await vaultListService.updatePassword(entry)

            if let index = items.firstIndex(where: { $0.id == entry.id && $0.type == .password }) {
                items[index] = .password(entry)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 更新PIN码条目
    func updatePincodeItem(_ entry: PincodeEntry) async {
        do {
            try await vaultListService.updatePincode(entry)

            if let index = items.firstIndex(where: { $0.id == entry.id && $0.type == .pincode }) {
                items[index] = .pincode(entry)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 软删除密码条目
    func deletePasswordItem(_ entry: PasswordEntry) async {
        await deleteItem(.password(entry))
    }

    // 软删除PIN码条目
    func deletePincodeItem(_ entry: PincodeEntry) async {
        await deleteItem(.pincode(entry))
    }

    // 软删除银行卡条目
    func deleteBankcardItem(_ entry: BankcardEntry) async {
        await deleteItem(.bankcard(entry))
    }

    // 更新银行卡条目
    func updateBankcardItem(_ entry: BankcardEntry) async {
        do {
            try await vaultListService.updateBankcard(entry)

            if let index = items.firstIndex(where: { $0.id == entry.id && $0.type == .bankcard }) {
                items[index] = .bankcard(entry)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 打开详情视图
    func openDetail(for item: VaultItem) {
        selectedDestination = item.destination
    }

    // 
    func category(for categoryID: UUID) -> PasswordCategory? {
        referenceData.category(for: categoryID)
    }

    // 清除筛选条件
    func clearFilters() {
        selectedCategoryID = nil
        selectedTags = []
        selectedTypes = Set(VaultItemType.allCases)
        sortField = .updatedAt
        sortAscending = false
    }

    private func applyFiltersAndSorting(to items: [VaultItem]) -> [VaultItem] {
        let filteredByType = items.filter { $0.matches(types: selectedTypes) }
        let filteredByCategory = filteredByType.filter { $0.matches(categoryID: selectedCategoryID) }
        let filteredByTags = filteredByCategory.filter { $0.matches(tags: selectedTags) }
        return sort(filteredByTags, by: sortField, ascending: sortAscending)
    }

    /// 按指定字段和方向排序；排序键相同时用 id 兜底，保证结果稳定
    ///
    /// 开启「收藏置顶」时先按 isFavorite 分组，组内再按选定字段排，
    /// 这样切换排序字段不会把收藏项打散。
    private func sort(_ items: [VaultItem], by field: VaultSortField, ascending: Bool) -> [VaultItem] {
        items.sorted { lhs, rhs in
            if pinFavoritesToTop && lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            switch field {
            case .createdAt:
                let left = lhs.createdAt ?? .distantPast
                let right = rhs.createdAt ?? .distantPast
                if left != right {
                    return ascending ? left < right : left > right
                }
            case .updatedAt:
                let left = lhs.displayDate
                let right = rhs.displayDate
                if left != right {
                    return ascending ? left < right : left > right
                }
            case .title:
                let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if comparison != .orderedSame {
                    return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func toggledFavoriteItem(from item: VaultItem) -> VaultItem {
        let now = Date()

        switch item {
        case var .password(entry):
            entry.isFavorite.toggle()
            entry.updatedAt = now
            entry.isSynced = false
            return .password(entry)
        case var .pincode(entry):
            entry.isFavorite.toggle()
            entry.updatedAt = now
            entry.isSynced = false
            return .pincode(entry)
        case var .bankcard(entry):
            entry.isFavorite.toggle()
            entry.updatedAt = now
            entry.isSynced = false
            return .bankcard(entry)
        }
    }
}
