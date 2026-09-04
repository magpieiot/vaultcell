/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppCatalogService.swift
/// created on: 08/23/2026
/// ------------------------------------------------------------------

import Foundation

/// 应用目录加载错误
enum AppCatalogError: Error, LocalizedError {
    case fileNotFound
    case decodeFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "未找到应用目录 JSON 文件"
        case .decodeFailed(let error):
            return "解析应用目录失败: \(error.localizedDescription)"
        }
    }
}

/// 应用目录服务协议
protocol AppCatalogServiceProtocol {
    /// 从 bundle 加载应用元数据数组
    func loadApps() async throws -> [AppInfo]
}

/// 默认实现：从 main bundle 的 JSON 文件加载应用目录
final class AppCatalogService: AppCatalogServiceProtocol {
    
    /// JSON 文件名（不含扩展名）
    private let filename: String
    
    /// 资源所在 bundle
    private let bundle: Bundle
    
    init(filename: String = "apps_500_min", bundle: Bundle = .main) {
        self.filename = filename
        self.bundle = bundle
    }
    
    /// 加载并解析应用元数据
    ///
    /// 在后台线程读取文件，避免阻塞主线程。
    func loadApps() async throws -> [AppInfo] {
        try await Task.detached(priority: .userInitiated) {
            guard let url = self.bundle.url(forResource: self.filename, withExtension: "json") else {
                throw AppCatalogError.fileNotFound
            }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            do {
                return try decoder.decode([AppInfo].self, from: data)
            } catch {
                throw AppCatalogError.decodeFailed(error)
            }
        }.value
    }
}
