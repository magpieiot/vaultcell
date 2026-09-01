/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// SearchHistoryStore.swift
/// created on: 08/07/2026
/// ------------------------------------------------------------------

import Foundation

/// 搜索历史存储：按最近使用排序，去重（忽略大小写），上限 20 条
struct SearchHistoryStore {
    static let maxItems = 20

    static func recentQueries() -> [String] {
        UserDefaults.standard.stringArray(forKey: VaultKey.searchHistory) ?? []
    }

    static func addQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list = recentQueries()
        list.removeAll { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        list.insert(trimmed, at: 0)

        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }

        UserDefaults.standard.set(list, forKey: VaultKey.searchHistory)
    }

    static func removeQuery(_ query: String) {
        var list = recentQueries()
        list.removeAll { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
        UserDefaults.standard.set(list, forKey: VaultKey.searchHistory)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: VaultKey.searchHistory)
    }
}
