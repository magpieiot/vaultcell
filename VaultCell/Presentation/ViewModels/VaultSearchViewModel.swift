/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultSearchViewModel.swift
/// created on: 08/07/2026
/// ------------------------------------------------------------------

import Foundation
import Combine

@MainActor
final class VaultSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [VaultItem] = []
    @Published var history: [String] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let listViewModel: VaultListViewModel

    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    init(listViewModel: VaultListViewModel) {
        self.listViewModel = listViewModel
        self.history = SearchHistoryStore.recentQueries()
        setupBindings()
    }

    deinit {
        loadTask?.cancel()
    }

    private func setupBindings() {
        listViewModel.$items
            .combineLatest($query)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map { [weak self] items, query in
                self?.filter(items: items, query: query) ?? []
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] filtered in
                self?.results = filtered
                // 实时搜索产生结果时，记录到历史（去重由 SearchHistoryStore 保证）
                if let self {
                    let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !filtered.isEmpty {
                        SearchHistoryStore.addQuery(trimmed)
                    }
                    // 查询清空时刷新历史列表，供历史区显示最新数据
                    if self.query.isEmpty {
                        self.history = SearchHistoryStore.recentQueries()
                    }
                }
            }
            .store(in: &cancellables)
    }

    func loadItemsIfNeeded() async {
        guard listViewModel.items.isEmpty else { return }
        isLoading = true
        await listViewModel.loadItems()
        isLoading = false
    }

    func commitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SearchHistoryStore.addQuery(trimmed)
        history = SearchHistoryStore.recentQueries()
    }

    func selectHistory(_ query: String) {
        self.query = query
        commitSearch()
    }

    func removeHistory(_ query: String) {
        SearchHistoryStore.removeQuery(query)
        history = SearchHistoryStore.recentQueries()
    }

    func clearHistory() {
        SearchHistoryStore.clearAll()
        history = []
    }

    var groupedResults: [(type: VaultItemType, items: [VaultItem])] {
        VaultItemType.allCases.compactMap { type in
            let group = results.filter { $0.type == type }
            guard !group.isEmpty else { return nil }
            let sorted = group.sorted {
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite && !$1.isFavorite
                }
                return $0.displayDate > $1.displayDate
            }
            return (type, sorted)
        }
    }

    private func filter(items: [VaultItem], query: String) -> [VaultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return items.filter { item in
            let text = item.searchableText
            return tokens.allSatisfy { token in
                text.localizedStandardRange(of: token) != nil
            }
        }
    }
}
