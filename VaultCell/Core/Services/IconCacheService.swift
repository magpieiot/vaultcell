//
//  IconCacheService.swift
//  VaultCell
//
//  图标服务：favicon 地址生成 + 本地缓存 + 下载兜底。
//  缓存文件名由源 URL 的 SHA256 哈希确定性生成，同一 URL 永远命中
//  同一文件（无需在条目中额外存储）。
//
//  加载策略（按优先级）：
//  1. 本地缓存（离线可用）
//  2. 主 URL（条目中存储的图标地址）
//  3. 同源 favicon 候选（bare / www × favicon.ico / favicon.png / apple-touch-icon.png）
//  4. 主页 HTML 解析 `<link rel="icon">`（覆盖 CDN 图标、非根路径等场景）
//  5. Google 图标服务兜底（主要覆盖海外站点）
//

import UIKit
import CryptoKit
import SVGKit

enum IconCacheService {
    // MARK: - Favicon 地址生成

    /// 缓存写入通知：任一视图下载成功并落盘后发出，
    /// 让正在展示同一图标地址的其他视图（如列表行）能立即刷新，
    /// 避免详情页已拿到图标、返回列表后列表仍停留在占位图。
    static let iconCacheDidUpdateNotification = Notification.Name("IconCacheService.iconCacheDidUpdate")
    /// 通知 userInfo 中携带缓存键（即图源地址）的 key
    static let cacheKeyUserInfoKey = "cacheKey"

    /// 提取标准域名（去除 scheme、www. 前缀与路径）
    /// 例：`https://www.example.com/login` -> `example.com`
    static func domain(from urlString: String) -> String? {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        guard let host = URL(string: s)?.host else { return nil }
        var h = host.lowercased()
        if h.hasPrefix("www.") {
            h = String(h.dropFirst(4))
        }
        return h.isEmpty ? nil : h
    }

    /// 站点同源 favicon 主地址（优先使用，中文站点可达性好）
    /// 例：`example.com` -> `https://example.com/favicon.ico`
    static func faviconURL(for urlString: String) -> URL? {
        guard let domain = domain(from: urlString) else { return nil }
        return URL(string: "https://" + domain + "/favicon.ico")
    }

    /// 兜底 favicon 地址（Google 图标服务，覆盖广；国内不可达，主要服务海外站点）
    /// 例：`example.com` -> `https://www.google.com/s2/favicons?domain=example.com&sz=128`
    static func fallbackURL(for urlString: String) -> URL? {
        guard let domain = domain(from: urlString) else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "sz", value: "128")
        ]
        return components?.url
    }

    /// 同源 favicon 候选列表（bare 与 www 各一套常见路径）。
    /// 部分站点（如 www.meituan.com）仅在 www 子域提供 favicon。
    static func faviconCandidates(for urlString: String) -> [URL] {
        guard let domain = domain(from: urlString) else { return [] }
        var result: [URL] = []
        for host in [domain, "www." + domain] {
            for path in ["/favicon.ico", "/favicon.png", "/apple-touch-icon.png"] {
                if let url = URL(string: "https://" + host + path) {
                    result.append(url)
                }
            }
        }
        return result
    }

    /// 从主页 HTML 提取 `<link rel="icon">` 引用的 favicon 地址。
    /// 返回按优先级排序（apple-touch-icon PNG 优先，SVG 最后）的 URL 列表，已去重。
    static func faviconURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let patterns = [
            // rel 在 href 前
            #"<link\b[^>]*\brel\s*=\s*["'][^"']*(?:icon|apple-touch-icon)[^"']*["'][^>]*\bhref\s*=\s*["']([^"']+)["']"#,
            // href 在 rel 前
            #"<link\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*\brel\s*=\s*["'][^"']*(?:icon|apple-touch-icon)[^"']*["']"#,
        ]
        var found: [(url: URL, isAppleTouch: Bool, isSVG: Bool)] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let ns = html as NSString
            regex.enumerateMatches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let href = ns.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = Self.resolve(href: href, baseURL: baseURL) else { return }
                // apple-touch-icon 通常是 PNG 大图，优先；SVG 仅作最后兜底（需离屏渲染）
                let isAppleTouch = pattern.contains("apple-touch-icon")
                let isSVG = url.absoluteString.lowercased().hasSuffix(".svg")
                found.append((url, isAppleTouch, isSVG))
            }
        }
        var seen = Set<String>()
        var result: [URL] = []
        for item in found.sorted(by: { lhs, rhs in
            if lhs.isAppleTouch != rhs.isAppleTouch { return lhs.isAppleTouch }
            if lhs.isSVG != rhs.isSVG { return !lhs.isSVG }
            return false
        }) {
            if seen.insert(item.url.absoluteString).inserted {
                result.append(item.url)
            }
        }
        return result
    }

    /// 下载主页 HTML 并解析 favicon 地址（读取上限 maxDownloadBytes，link 标签均在 head 内）
    static func iconURLsFromHomepage(for urlString: String) async -> [URL] {
        guard let domain = domain(from: urlString),
              let baseURL = URL(string: "https://" + domain) else { return [] }
        for host in [domain, "www." + domain] {
            guard let url = URL(string: "https://" + host) else { continue }
            guard let data = await downloadData(from: url), !data.isEmpty else { continue }
            // 超限截断点可能落在多字节字符中间，严格解码失败时退化为容错解码
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let urls = faviconURLs(fromHTML: html, baseURL: baseURL)
            if !urls.isEmpty { return urls }
        }
        return []
    }

    /// 解析 HTML href 为绝对 URL（支持协议相对 //、根相对 /、普通相对路径）
    private static func resolve(href: String, baseURL: URL) -> URL? {
        let h = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        if h.hasPrefix("//") {
            return URL(string: (baseURL.scheme ?? "https") + ":" + h)
        }
        if let url = URL(string: h), url.scheme != nil {
            return url
        }
        return URL(string: h, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - 缓存

    /// 缓存目录：Library/Caches/AppIcons（系统可自动清理，无则重建）
    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppIconsV2", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 由源 URL 生成确定性的缓存文件名（SHA256 十六进制 + .png）
    static func cacheFileName(for urlString: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex + ".png"
    }

    /// 缓存文件完整路径
    static func cacheFileURL(for urlString: String) -> URL {
        cacheDirectory.appendingPathComponent(cacheFileName(for: urlString))
    }

    /// 读取缓存图片（无缓存 / 读取失败返回 nil）
    static func loadImage(for urlString: String) -> UIImage? {
        let url = cacheFileURL(for: urlString)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 保存图片数据到缓存（覆盖同名文件）
    @discardableResult
    static func saveImageData(_ data: Data, for urlString: String) -> Bool {
        let url = cacheFileURL(for: urlString)
        do {
            try data.write(to: url, options: .atomic)
            postCacheDidUpdate(for: urlString)
            return true
        } catch {
            return false
        }
    }

    /// 在主线程广播“某个图源地址的缓存已更新”，供 CachedIconView 订阅刷新
    private static func postCacheDidUpdate(for urlString: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: iconCacheDidUpdateNotification,
                object: nil,
                userInfo: [cacheKeyUserInfoKey: urlString]
            )
        }
    }

    // MARK: - 网络

    /// 单次响应读取上限（2MB）：favicon 通常不足 100KB，主页 HTML 的 link 标签都在头部，
    /// 超出即视为异常响应，直接断开，避免把超大响应读进内存。
    private static let maxDownloadBytes = 2_000_000

    /// 流式下载并限制响应体字节数（超限返回 nil）
    private static func downloadData(from url: URL) async -> Data? {
        await CappedDownloader.shared.data(from: url, limit: maxDownloadBytes)
    }

    // MARK: - 加载

    /// 统一加载图标：缓存 → 主 URL → 同源候选 → 主页 HTML 解析 → Google 兜底。
    /// 任意一步成功即写入主键缓存。
    static func loadIcon(urlString: String) async -> UIImage? {
        if let cached = loadImage(for: urlString) {
            return cached
        }
        // 1) 主 URL 本身（可能是任意图标地址，如历史数据）
        if let result = await downloadImage(urlString) {
            saveImageData(result.data, for: urlString)
            return result.image
        }
        // 2) 同源候选（含 www 变体）
        for candidate in faviconCandidates(for: urlString) {
            guard candidate.absoluteString != urlString else { continue }
            if let result = await downloadImage(candidate.absoluteString) {
                saveImageData(result.data, for: urlString)
                return result.image
            }
        }
        // 3) 主页 HTML 解析（覆盖 CDN 图标、非根路径）
        for iconURL in await iconURLsFromHomepage(for: urlString) {
            if let result = await downloadImage(iconURL.absoluteString) {
                saveImageData(result.data, for: urlString)
                return result.image
            }
        }
        // 4) Google 图标服务兜底（主要海外站点）
        if let fallback = fallbackURL(for: urlString), fallback.absoluteString != urlString {
            if let result = await downloadImage(fallback.absoluteString) {
                saveImageData(result.data, for: urlString)
                return result.image
            }
        }
        return nil
    }

    /// 下载并解码图片（返回可缓存数据 + 图片；HTML 等非图片内容返回 nil）。
    /// SVG 无法被 UIImage 直接解码，净化后交给 SVGKit 离屏渲染。
    private static func downloadImage(_ urlString: String) async -> (data: Data, image: UIImage)? {
        guard let url = URL(string: urlString) else { return nil }
        guard let data = await downloadData(from: url), !data.isEmpty else { return nil }
        if let image = UIImage(data: data) {
            return (data, image)
        }
        if isSVGData(data),
           let sanitized = sanitizedSVGString(from: data),
           let image = await renderSVGData(Data(sanitized.utf8)) {
            // 缓存渲染后的 PNG，保证离线可复用
            return (image.pngData() ?? data, image)
        }
        return nil
    }

    /// 判断数据是否为 SVG（宽松检测：前 1KB 内含 <svg 标签）
    private static func isSVGData(_ data: Data) -> Bool {
        let head = String(data: data.prefix(1024), encoding: .utf8)?.lowercased() ?? ""
        return head.contains("<svg")
    }

    // MARK: - SVG 净化

    /// 解析前的 SVG 净化（纵深防御）。
    ///
    /// SVGKit 不执行 JavaScript，但会为外链发起**同步**网络请求：
    /// `<image href="http(s)://…">`（SVGImageElement）与
    /// `<?xml-stylesheet href="http(s)://…"?>`（SVGKParser）都直接
    /// `NSData.dataWithContentsOfURL`。恶意 favicon 可借此让 App 访问任意外部主机，
    /// 且渲染在 @MainActor 上，会一并阻塞主线程。因此：
    /// - 剥离无视觉影响的构造：DOCTYPE / 内部子集、`<?xml-stylesheet?>`、
    ///   `<script>` 块、`on*` 事件属性
    /// - 只要出现不以 `#` 开头的 href / xlink:href 就整体放弃。除 `<image>` 外还覆盖：
    ///   `<use>` 的非片段引用会触发 SVGKit 的 NSAssert；`data:` 内嵌 SVG 会被递归解析，
    ///   其内部 href 仍可外链，故不能放行
    ///
    /// 通过则返回净化后的 SVG 字符串，否则返回 nil，交由后续候选（PNG / apple-touch-icon / Google）兜底。
    private static func sanitizedSVGString(from data: Data) -> String? {
        guard var svg = String(data: data, encoding: .utf8) else { return nil }
        // 1) 外链引用无法安全改写，整体放弃
        guard !containsExternalReference(svg) else { return nil }
        // 2) 去除脚本与事件处理器（SVGKit 不执行，属纵深防御）
        svg = svg.replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script\s*>"#, with: "", options: .regularExpression)
        svg = svg.replacingOccurrences(of: #"(?is)<script\b[^>]*/>"#, with: "", options: .regularExpression)
        svg = svg.replacingOccurrences(of: #"(?i)\son[a-z]+\s*=\s*("[^"]*"|'[^']*')"#, with: "", options: .regularExpression)
        // 3) 去除 DTD 与外部样式表处理指令，避免依赖 libxml2 的默认解析选项
        //    字符类里的 `[` 必须转义，否则 ICU 会解析异常导致整条正则失配
        svg = svg.replacingOccurrences(of: #"(?is)<!DOCTYPE\b[^>\[]*(\[[^\]]*\]\s*)?[^>]*>"#, with: "", options: .regularExpression)
        svg = svg.replacingOccurrences(of: #"(?is)<\?xml-stylesheet\b.*?\?>"#, with: "", options: .regularExpression)
        return svg
    }

    /// 是否含外部资源引用：href / xlink:href 的值只要不是页内片段（`#…`）即视为外链。
    /// 只匹配「属性值」而不绑定标签，避免属性值内的 `>` 让按标签截断的正则漏检。
    private static func containsExternalReference(_ svg: String) -> Bool {
        let pattern = #"(?i)\b(?:xlink:href|href)\s*=\s*["']\s*([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let ns = svg as NSString
        var external = false
        regex.enumerateMatches(in: svg, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, stop in
            guard let match, match.numberOfRanges > 1 else { return }
            let value = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value.hasPrefix("#") { return }
            external = true
            stop.pointee = true
        }
        return external
    }

    /// SVG 数据 → UIImage（SVGKit 渲染；SVG 默认按固有尺寸渲染，
    /// 部分站点图标仅 16/32/64px，需等比放大到目标尺寸，否则显示过小）
    @MainActor
    private static func renderSVGData(_ data: Data) async -> UIImage? {
        guard let svgImage = SVGKImage(data: data) else { return nil }
        let target = CGSize(width: 128, height: 128)
        if svgImage.size.width < 1 || svgImage.size.height < 1 {
            // 无显式 width/height 的 SVG，直接指定渲染尺寸
            svgImage.size = target
        } else {
            // 等比缩放至目标尺寸（如 64 → 128）
            svgImage.scaleToFit(inside: target)
        }
        return svgImage.uiImage
    }

    /// 异步下载远程图标并写入缓存
    /// - Parameters:
    ///   - urlString: 远程图标地址
    ///   - completion: 完成后回调（主线程），成功返回 true；不传则静默完成
    static func cache(remoteURL urlString: String, completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: urlString) else {
            completion?(false)
            return
        }
        Task.detached {
            guard let data = await downloadData(from: url),
                  !data.isEmpty,
                  UIImage(data: data) != nil else {
                await MainActor.run { completion?(false) }
                return
            }
            let success = saveImageData(data, for: urlString)
            await MainActor.run { completion?(success) }
        }
    }
}

/// 带上限的流式下载器（全局单例，避免每次请求新建 URLSession）。
///
/// 为什么不用 `URLSession.data(from:)` 或 `dataTask(with:completionHandler:)`：
/// 两者都会先把整个响应体缓存进内存，拿到结果后再判断大小已经晚了
/// （`data.prefix(n)` 同理，只能截断已经读进内存的数据，起不到保护作用）。
/// 因此这里实现 `URLSessionDataDelegate`，在流式回调中累计字节，超限立即取消任务。
private final class CappedDownloader: NSObject, URLSessionDataDelegate {
    static let shared = CappedDownloader()

    private let lock = NSLock()
    /// taskIdentifier -> 已接收数据
    private var received: [Int: Data] = [:]
    /// taskIdentifier -> 该任务的字节上限
    private var limits: [Int: Int] = [:]
    /// taskIdentifier -> 等待中的调用方
    private var continuations: [Int: CheckedContinuation<Data?, Never>] = [:]

    /// 图标已有自有缓存目录，无需共享 URL 缓存，也避免与浏览行为共享 cookie，故用 ephemeral
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func data(from url: URL, limit: Int) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let task = session.dataTask(with: url)
            let id = task.taskIdentifier
            lock.lock()
            continuations[id] = continuation
            limits[id] = limit
            received[id] = Data()
            lock.unlock()
            task.resume()
        }
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
