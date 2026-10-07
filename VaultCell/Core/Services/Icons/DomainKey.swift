/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// DomainKey.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 域名规范化（纯逻辑：Foundation + CryptoKit，不依赖 UIKit，可进单测 target）。
///
/// 内置图标查表 key、图标缓存文件名、失败集合 key 三者全部由本类型产出，保证同源：
/// 同一个站点无论用户填的是 `www.example.com`、`https://example.com/login` 还是
/// `Example.COM:443`，都会归一到同一个 key。
///
/// 规范化规则：
/// 1. 缺 scheme 时补 `https://`（只用于解析，不用于请求）
/// 2. 只保留 host：丢掉路径、查询、片段、端口、userinfo
/// 3. 小写
/// 4. 去掉 `www.` 前缀
///
/// ⚠️ 规范化只服务「查表与缓存键」；实际网络抓取仍要尝试 www 主机（见 `fetchHosts(_:)`），
/// 因为部分站点只在 www 子域提供 favicon（如 www.meituan.com）。

import Foundation
import CryptoKit

enum DomainKey {
    // MARK: - 规范化

    /// 规范化域名：`https://www.Example.com:443/login` -> `example.com`
    /// - Returns: 输入为空或解析不出 host 时返回 nil
    static func normalize(_ raw: String) -> String? {
        guard var host = rawHost(raw) else { return nil }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host.isEmpty ? nil : host
    }

    /// 原始 host：小写、去端口、**保留** `www.` 前缀（供抓取时生成 www 变体）
    static func rawHost(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        let withScheme =
            lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
            ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: withScheme)?.host else { return nil }
        let normalized = host.lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    /// 抓取用主机列表：`[规范化域, www.规范化域]`
    ///
    /// 顺序稳定、已去重：站点本身就叫 `www.x.com` 时不会重复尝试；
    /// 规范化域为空或已带 `www.` 时也只返回一项。
    static func fetchHosts(_ raw: String) -> [String] {
        guard let domain = normalize(raw) else { return [] }
        var hosts = [domain]
        if let host = rawHost(raw), host.hasPrefix("www.") {
            // 用户填的就是 www 主机，规范化已把它剥掉，这里补回原样
            hosts = [host, domain]
        } else {
            hosts.append("www." + domain)
        }
        return hosts
    }

    // MARK: - 键

    /// 缓存键 / 失败集合键：`sha256(规范化域名)`
    ///
    /// 只落哈希不落明文域名：缓存目录与失败集合被 dump 时看不出用户访问过哪些站点。
    static func cacheKey(_ raw: String) -> String? {
        guard let domain = normalize(raw) else { return nil }
        return hash(domain)
    }

    /// 任意字符串的 sha256 十六进制摘要（手动图源按完整 URL 取键）
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
