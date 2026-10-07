/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IconResolver.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 图标解析统一入口：内置图标 → 缓存 → 字母图块 → （开关开启时）远程抓取。
///
/// 分层与硬约束：
/// - **L1 内置图标**：命中即返回本地资产名，**不进入任何网络路径**（内置条目零请求）
/// - **L2 字母图块**：未命中时同步给出首字母，视图永不空白
/// - **L3 远程抓取**：开关关闭 / 无可用域名 / 已失败 一律直接返回，**根本不发起请求**
///
/// `PasswordEntry.icon` 的语义（改造后）：「用户手动指定的图源」的唯一用途。
/// 非空时按该地址精确抓取，不再解释为「按域名抓取」；但内置图标命中时优先返回内置资产，
/// 以保证内置条目零请求这条硬约束无条件成立。

import Foundation
import UIKit

/// 图标解析请求
struct IconRequest: Equatable {
    /// 条目标题（内置表标题兜底与字母图块用）
    let title: String
    /// 条目保存的站点地址（规范化后用于内置查表与抓取）
    let siteURL: String?
    /// 用户手动指定的图源（`PasswordEntry.icon`）
    let manualIconURL: String?

    init(title: String, siteURL: String?, manualIconURL: String? = nil) {
        self.title = title
        self.siteURL = siteURL
        self.manualIconURL = manualIconURL
    }

    /// 缓存键：手动图源按完整 URL 取键，否则按规范化域名；两者都缺时为 nil（不发请求）
    var cacheKey: String? {
        if let manual = manualIconURL?.trimmingCharacters(in: .whitespacesAndNewlines), !manual.isEmpty {
            return DomainKey.hash(manual)
        }
        guard let siteURL else { return nil }
        return DomainKey.cacheKey(siteURL)
    }

    /// 内置图标资产名（命中即零请求）
    var builtinAsset: String? {
        AppCatalog.asset(title: title, url: siteURL)
    }

    /// 字母图块首字母：优先取目录条目，其次取标题首字符
    var tileInitial: String {
        if let fromCatalog = AppCatalog.initial(forTitle: title) { return fromCatalog }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return String(first).uppercased()
    }

    /// 视图 `.task(id:)` 的稳定标识：任一入参变化都要重新解析
    var taskID: String {
        "\(title)|\(siteURL ?? "")|\(manualIconURL ?? "")"
    }
}

/// 同步解析结果
struct IconResolution {
    /// 内置资产名（优先展示，命中时不涉及网络）
    let builtinAsset: String?
    /// 本地缓存图片
    let cachedImage: UIImage?
    /// 字母图块首字母（可能为空，此时视图回退到 SF Symbol）
    let initial: String
}

enum IconResolver {
    // MARK: - 同步解析

    /// 内置资产 → 缓存图片 → 字母图块
    static func resolve(_ request: IconRequest) -> IconResolution {
        let builtinAsset = request.builtinAsset
        let cachedImage = builtinAsset == nil ? cachedImage(for: request) : nil
        return IconResolution(
            builtinAsset: builtinAsset,
            cachedImage: cachedImage,
            initial: request.tileInitial
        )
    }

    /// 读缓存（无可用键时返回 nil）
    static func cachedImage(for request: IconRequest) -> UIImage? {
        guard let key = request.cacheKey else { return nil }
        return IconStore.cachedImage(forKey: key)
    }

    // MARK: - 异步抓取

    /// 按需抓取远程图标；任何一条硬约束不满足都直接返回，不产生请求
    /// - Returns: 抓取成功的图片；未抓取或失败返回 nil
    static func fetchRemote(_ request: IconRequest) async -> UIImage? {
        // 内置命中：绝不进入网络路径
        guard request.builtinAsset == nil else { return nil }
        // 开关关闭：不抓取
        guard IconPreferences.isAutoFetchEnabled else { return nil }
        // 没有可用域名（如只填了标题）：不猜域名，也不抓取
        guard let key = request.cacheKey else { return nil }
        // 已有缓存 / 之前已失败：不再重试
        if let cached = IconStore.cachedImage(forKey: key) { return cached }
        guard !IconStore.hasFailed(key) else { return nil }

        let candidates = candidateURLs(for: request)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            guard let data = await IconFetcher.iconData(from: candidate),
                let image = IconStore.save(data, forKey: key)
            else { continue }
            return image
        }
        // 整条链路都失败：记一笔失败集合，之后同一 key 不再发起请求
        IconStore.markFailed(key)
        return nil
    }

    /// 候选地址：手动图源排最前（精确地址），之后按域名生成同源候选，按地址去重
    ///
    /// 手动图源失败后仍要回落域名候选：`PasswordEntry.icon` 在改造前由「App Store 建议」
    /// 自动写入（裸域 `favicon.ico` 地址），这些历史值现在按「手动图源」处理，
    /// 若不回落，www-only 站点上的老条目会直接从有图标变成字母图块。
    /// 手动地址始终是第一个尝试项，不存在「存了 URL 却只按域名抓取」的情况。
    private static func candidateURLs(for request: IconRequest) -> [URL] {
        var result: [URL] = []
        if let manual = request.manualIconURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !manual.isEmpty,
            let url = URL(string: manual),
            url.scheme?.lowercased() == "https"
        {
            result.append(url)
        }
        if let siteURL = request.siteURL {
            result.append(contentsOf: IconFetcher.candidateURLs(for: siteURL))
        }
        var seen: Set<String> = []
        return result.filter { seen.insert($0.absoluteString).inserted }
    }
}
