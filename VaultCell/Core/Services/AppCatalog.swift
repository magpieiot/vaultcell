/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppCatalog.swift
/// created on: 21/09/2026
/// ------------------------------------------------------------------
///
/// 统一应用目录：`VaultCell/Resources/app_catalog.json` → 内存索引。
///
/// 一份数据同时服务两条链路，避免两张表各自漂移：
/// - **图标解析**（`IconResolver`）：按规范化域名精确命中，未命中再按标题 / 拼音兜底，
///   命中即返回本地资产，**不进入任何网络路径**
/// - **标题联想**（`AppState.apps`）：按标题 / 英文名 / 全拼 / 首字母 / 域名模糊匹配
///
/// key 口径与 `DomainKey.normalize` 同源（规范化域名），与缓存键、失败集合键保持一致。

import Foundation

/// 统一目录条目
struct AppCatalogEntry: Codable, Identifiable, Hashable {

    /// 稳定标识（资产名小写去符号）
    let id: String

    /// Assets 中的 imageset 名；无内置图标时为 nil
    let asset: String?

    /// 规范化域名，主域在前，其后为别名域（如 `claude.ai` / `claudeai.com`）
    let domains: [String]

    /// 英文名
    let en: String

    /// 中文名
    let zh: String?

    /// 全拼
    let pinyin: String?

    /// 拼音首字母
    let initials: String?

    /// 地区：`cn` / `global`
    let region: String?

    /// 是否支持 OAuth 登录
    let oauth: Bool?

    /// 流行度排序，越小越靠前
    let rank: Int?

    /// 展示标题：中文名优先，缺失时回落英文名
    var title: String {
        guard let zh, !zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return en }
        return zh
    }

    /// 站点地址：主域拼 `https://`
    var url: String {
        domains.first.map { "https://\($0)" } ?? ""
    }

    /// 联想匹配：标题 / 英文名 / 全拼 / 首字母 / 域名任一命中即为真
    ///
    /// 中文标题按整串包含匹配，拼音与首字母让「douyin」「dy」都能命中「抖音」。
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if title.localizedCaseInsensitiveContains(trimmed) { return true }
        if en.localizedCaseInsensitiveContains(trimmed) { return true }
        if let pinyin, pinyin.localizedCaseInsensitiveContains(trimmed) { return true }
        if let initials, initials.localizedCaseInsensitiveContains(trimmed) { return true }
        if domains.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) { return true }
        return false
    }
}

enum AppCatalog {

    /// 全量目录（按流行度排序），懒加载一次
    static let entries: [AppCatalogEntry] = loadEntries()

    /// 规范化域名 → 条目
    private static let domainIndex: [String: AppCatalogEntry] = {
        var index: [String: AppCatalogEntry] = [:]
        for entry in entries {
            for domain in entry.domains {
                guard let key = DomainKey.normalize(domain), index[key] == nil else { continue }
                index[key] = entry
            }
        }
        return index
    }()

    /// 标题（英文名 / 中文名 / 全拼，小写）→ 条目
    private static let titleIndex: [String: AppCatalogEntry] = {
        var index: [String: AppCatalogEntry] = [:]
        for entry in entries {
            for candidate in [entry.en, entry.zh, entry.pinyin] {
                guard let candidate else { continue }
                let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty, index[key] == nil else { continue }
                index[key] = entry
            }
        }
        return index
    }()

    // MARK: - 查表

    /// 统一入口：先按规范化域名精确命中，再按标题兜底
    static func entry(title: String, url: String?) -> AppCatalogEntry? {
        if let url, let key = DomainKey.normalize(url), let entry = domainIndex[key] {
            return entry
        }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTitle.isEmpty else { return nil }
        return titleIndex[normalizedTitle]
    }

    /// 内置图标资产名；nil 表示未命中（需要走缓存 / 抓取 / 字母图块）
    static func asset(title: String, url: String?) -> String? {
        entry(title: title, url: url)?.asset
    }

    /// 字母图块首字母：优先取条目拼音首字母，其次取英文名首字符
    static func initial(forTitle title: String) -> String? {
        guard let entry = entry(title: title, url: nil) else { return nil }
        let candidates = [entry.initials, entry.en]
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first, first.isLetter else { continue }
            return String(first).uppercased()
        }
        return nil
    }

    // MARK: - 载入

    private static func loadEntries() -> [AppCatalogEntry] {
        guard let url = Bundle.main.url(forResource: "app_catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([AppCatalogEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
