//
//  IconCacheService.swift
//  VaultGo
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

    /// 下载主页 HTML 并解析 favicon 地址（限取头部 2MB，link 标签均在 head 内）
    static func iconURLsFromHomepage(for urlString: String) async -> [URL] {
        guard let domain = domain(from: urlString),
              let baseURL = URL(string: "https://" + domain) else { return [] }
        for host in [domain, "www." + domain] {
            guard let url = URL(string: "https://" + host) else { continue }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let html = String(data: data.prefix(2_000_000), encoding: .utf8) else { continue }
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
            return true
        } catch {
            return false
        }
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
    /// SVG 无法被 UIImage 直接解码，走 WKWebView 离屏渲染。
    private static func downloadImage(_ urlString: String) async -> (data: Data, image: UIImage)? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              !data.isEmpty else { return nil }
        if let image = UIImage(data: data) {
            return (data, image)
        }
        if isSVGData(data), let image = await renderSVGData(data) {
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
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data, !data.isEmpty, UIImage(data: data) != nil else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            let success = saveImageData(data, for: urlString)
            DispatchQueue.main.async { completion?(success) }
        }.resume()
    }
}
