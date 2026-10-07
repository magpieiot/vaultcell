/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IconStore.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 图标本地缓存 + 失败集合。
///
/// 缓存文件名 = `sha256(规范化域名)`（见 `DomainKey.cacheKey(_:)`），
/// 同一站点无论用户填 `www.x.com` 还是 `https://x.com/login` 都命中同一文件；
/// 目录与文件名都不含明文域名，dump 沙盒看不出用户访问过哪些站点。
///
/// 失败集合：整条抓取链路（≥1 次请求）全部失败后按哈希记一笔，
/// 之后同一个 key 直接返回，不再重试——避免弱网站点在列表滚动时反复发起请求。
/// 只存哈希，落在 App 私有缓存目录，不依赖已解锁的主密钥（锁屏 / 崩溃后同样可写）。

import Foundation
import UIKit

enum IconStore {
    /// 缓存写入通知：任一视图抓取成功并落盘后发出，
    /// 让正在展示同一图源的其他视图（如列表行）立即刷新，
    /// 避免详情页已拿到图标、返回列表后列表仍停留在占位态。
    static let cacheDidUpdateNotification = Notification.Name("IconStore.cacheDidUpdate")
    /// 通知 userInfo 中携带缓存键的 key
    static let cacheKeyUserInfoKey = "cacheKey"

    /// 失败集合上限：只存哈希，超出后按插入顺序淘汰最旧的（防无限增长）
    private static let maxFailureCount = 1000

    // MARK: - 路径

    /// 缓存目录：`Library/Caches/AppIconsV3`（系统可自动清理，无则重建）
    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppIconsV3", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key + ".img")
    }

    /// 失败集合落盘位置（与缓存同目录：清理缓存时一并清掉，随后允许重新抓取）
    static var failureStorageURL: URL {
        cacheDirectory.appendingPathComponent("failures.json")
    }

    // MARK: - 缓存读写

    /// 读取缓存图片（无缓存 / 读盘失败 / 数据损坏返回 nil）
    static func cachedImage(forKey key: String) -> UIImage? {
        guard !key.isEmpty, let data = try? Data(contentsOf: fileURL(forKey: key)) else { return nil }
        return UIImage(data: data)
    }

    /// 校验 → 解码 → 落盘 → 广播
    /// - Returns: 解码后的图片；数据不合法或解码失败返回 nil（调用方据此记失败集合）
    @discardableResult
    static func save(_ data: Data, forKey key: String) -> UIImage? {
        guard !key.isEmpty,
            IconSafety.isAcceptable(data),
            let image = UIImage(data: data),
            IconSafety.isAcceptable(size: image.size)
        else { return nil }

        do {
            try data.write(to: fileURL(forKey: key), options: .atomic)
        } catch {
            // 落盘失败不影响本次展示：图片照常返回，下次进入重新抓取
            return image
        }
        postCacheDidUpdate(forKey: key)
        return image
    }

    // MARK: - 失败集合

    /// 该 key 是否已抓取失败（失败即止，不再重试）
    static func hasFailed(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return IconFailureRegistry.shared.contains(key)
    }

    /// 记录一次抓取失败
    static func markFailed(_ key: String) {
        guard !key.isEmpty else { return }
        IconFailureRegistry.shared.insert(key, maxCount: maxFailureCount)
    }

    // MARK: - 清理

    /// 清空缓存目录与失败集合（设置页「清除图标缓存」）
    static func clearAll() {
        IconFailureRegistry.shared.clear()
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// 删除 v2 旧缓存目录：键体系已从「完整 URL 哈希」改为「规范化域名哈希」，
    /// 旧文件无法复用（目录名也不同，不会误命中）。幂等，启动时调用一次即可。
    static func removeLegacyCache() {
        let legacy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppIconsV2", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.removeItem(at: legacy)
    }

    // MARK: - 内部

    private static func postCacheDidUpdate(forKey key: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: cacheDidUpdateNotification,
                object: nil,
                userInfo: [cacheKeyUserInfoKey: key]
            )
        }
    }
}

/// 失败集合的内存索引 + 落盘（哈希数组，保持插入顺序便于按上限淘汰）
private final class IconFailureRegistry {
    static let shared = IconFailureRegistry()

    private let lock = NSLock()
    private var didLoad = false
    private var order: [String] = []
    private var lookup: Set<String> = []

    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return lookup.contains(key)
    }

    func insert(_ key: String, maxCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard lookup.insert(key).inserted else { return }
        order.append(key)
        if order.count > maxCount {
            let overflow = order.count - maxCount
            let removed = order.prefix(overflow)
            order.removeFirst(overflow)
            for item in removed { lookup.remove(item) }
        }
        persist()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        didLoad = true
        order = []
        lookup = []
        try? FileManager.default.removeItem(at: IconStore.failureStorageURL)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: IconStore.failureStorageURL),
            let stored = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        order = stored
        lookup = Set(stored)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(order) else { return }
        try? data.write(to: IconStore.failureStorageURL, options: .atomic)
    }
}
