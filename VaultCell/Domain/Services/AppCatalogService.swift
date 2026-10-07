/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppCatalogService.swift
/// created on: 08/23/2026
/// ------------------------------------------------------------------

import Foundation

/// 应用目录服务协议
protocol AppCatalogServiceProtocol {
    /// 返回 bundle 中的统一应用目录条目
    func loadApps() async -> [AppCatalogEntry]
}

/// 默认实现：读取 `AppCatalog`（`app_catalog.json`）
///
/// 读取放在后台线程，避免首次访问时阻塞主线程；目录本身只解析一次。
final class AppCatalogService: AppCatalogServiceProtocol {

    init() {}

    func loadApps() async -> [AppCatalogEntry] {
        await Task.detached(priority: .userInitiated) {
            AppCatalog.entries
        }.value
    }
}
