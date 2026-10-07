/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IconFetcher.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 远程图标抓取器：只直连目标站点，不经任何聚合端点（不请求 Google 图标服务），
/// 不解析主页 HTML（`<link rel=icon>` 会额外产生 1~2 次请求）。
///
/// 抓取顺序（单域最坏 4 次请求，命中即止）：
/// 1. `https://<规范化域>/apple-touch-icon.png`
/// 2. `https://www.<规范化域>/apple-touch-icon.png`
/// 3. `https://<规范化域>/favicon.ico`
/// 4. `https://www.<规范化域>/favicon.ico`
///
/// www 变体必须保留：部分站点只在 www 子域提供 favicon（如 www.meituan.com），
/// 而规范化会去掉 `www.`，所以抓取阶段要把它补回来。
///
/// 会话策略：低数据模式（constrained）直接不发请求；单次响应体 ≤ 64KB，超限立即断开。

import Foundation
import UIKit

enum IconFetcher {
    // MARK: - 候选地址

    /// 生成抓取候选（路径优先交错，保证常见站点在前两次请求内命中）
    static func candidateURLs(for rawInput: String) -> [URL] {
        let hosts = DomainKey.fetchHosts(rawInput)
        guard !hosts.isEmpty else { return [] }
        var result: [URL] = []
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            for host in hosts {
                if let url = URL(string: "https://" + host + path) {
                    result.append(url)
                }
            }
        }
        return result
    }

    // MARK: - 抓取

    /// 抓取并校验单个图标地址（仅 HTTPS；体积 / 类型 / 尺寸三道闸门由 `IconSafety` 把关）
    /// - Returns: 通过校验的原始图片数据；任何一步不通过都返回 nil
    static func iconData(from url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard let data = await IconDownloadSession.shared.data(from: url, limit: IconSafety.maxBytes)
        else { return nil }
        guard IconSafety.isAcceptable(data) else { return nil }
        return data
    }
}

// MARK: - 带上限的流式下载

/// 带上限的流式下载器（全局单例，避免每次请求新建 URLSession）。
///
/// 为什么不用 `URLSession.data(from:)`：它会先把整个响应体读进内存，拿到结果后再判断大小已经晚了
/// （`data.prefix(n)` 同理，只能截断已经读进内存的数据）。因此这里实现 `URLSessionDataDelegate`，
/// 在流式回调中累计字节，超限立即取消任务。
private final class IconDownloadSession: NSObject, URLSessionDataDelegate {
    static let shared = IconDownloadSession()

    private let lock = NSLock()
    /// taskIdentifier -> 已接收数据
    private var received: [Int: Data] = [:]
    /// taskIdentifier -> 该任务的字节上限
    private var limits: [Int: Int] = [:]
    /// taskIdentifier -> 等待中的调用方
    private var continuations: [Int: CheckedContinuation<Data?, Never>] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        configuration.httpMaximumConnectionsPerHost = 4
        // 图标有自有缓存目录，无需 URL 缓存，也避免与其他网络行为共享 cookie
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // 低数据模式（用户主动开启省流）时不抓取远程图标
        configuration.allowsConstrainedNetworkAccess = false
        configuration.allowsExpensiveNetworkAccess = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func data(from url: URL, limit: Int) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            var request = URLRequest(url: url)
            request.setValue("VaultCell/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue(
                "image/png,image/jpeg,image/x-icon,image/vnd.microsoft.icon,image/*;q=0.8",
                forHTTPHeaderField: "Accept")
            let task = session.dataTask(with: request)
            let id = task.taskIdentifier
            lock.lock()
            continuations[id] = continuation
            limits[id] = limit
            received[id] = Data()
            lock.unlock()
            task.resume()
        }
    }

    /// 响应头即拒收明显不是图片的类型（域名填错指向网页、或服务端返回 SVG），
    /// 不必等把响应体读完。注意不能只放行 image/*：部分站点用 application/octet-stream 返回 .ico。
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let mimeType = response.mimeType?.lowercased() else {
            completionHandler(.allow)
            return
        }
        let rejected = mimeType.hasPrefix("text/") || mimeType.contains("svg")
        completionHandler(rejected ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        lock.lock()
        guard var buffer = received[id], let limit = limits[id] else {
            lock.unlock()
            return
        }
        guard buffer.count + data.count <= limit else {
            // 超限：先清状态再取消，didCompleteWithError 回来时找不到调用方，不会重复 resume
            received[id] = nil
            limits[id] = nil
            let continuation = continuations.removeValue(forKey: id)
            lock.unlock()
            dataTask.cancel()
            continuation?.resume(returning: nil)
            return
        }
        buffer.append(data)
        received[id] = buffer
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        lock.lock()
        let buffer = received.removeValue(forKey: id)
        limits[id] = nil
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(returning: error == nil && buffer?.isEmpty == false ? buffer : nil)
    }
}
