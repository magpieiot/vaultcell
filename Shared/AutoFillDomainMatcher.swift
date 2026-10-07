/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AutoFillDomainMatcher.swift
/// ------------------------------------------------------------------
////
/// AutoFill 域名匹配的唯一定义，由主 App（注册 credential identity）与
/// AutoFillProvider 扩展（按系统请求匹配条目）共同编译。
///
/// 两端必须使用同一份实现：注册侧和匹配侧对"同一 URL 推导出什么域名"
/// 判定不一致时，会出现"注册了但键盘建议不命中"（或反之）的错位问题。
/// 历史上这里是两份手抄副本，且公共后缀表已经漂移（一侧少 "or"/"ne"）。

import Foundation

enum AutoFillDomainMatcher {

    /// 两段式公共后缀的第二段标签（co.uk / com.cn / or.jp / ne.jp 等）。
    /// 倒数第二段命中该集合时，可注册域名应取三段而非两段。
    private static let twoLevelSuffixLabels: Set<String> =
        ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne"]

    // MARK: - 文本解析

    /// 从任意 URL/域名文本中提取 hostname（小写、剥离 www. / m. 前缀）。
    /// 剥离后为空（如文本只有 "www."）时返回 nil，视为不可匹配。
    static func hostname(from text: String) -> String? {
        let candidate: String
        if text.contains("://"), let url = URL(string: text), let host = url.host {
            candidate = host
        } else {
            // 去掉 scheme 与路径后取第一段
            let withoutScheme = text.replacingOccurrences(of: ".*://", with: "", options: .regularExpression)
            candidate = withoutScheme.split(separator: "/").first.map(String.init) ?? withoutScheme
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        for prefix in ["www.", "m."] where trimmed.hasPrefix(prefix) {
            let stripped = String(trimmed.dropFirst(prefix.count))
            return stripped.isEmpty ? nil : stripped
        }
        return trimmed
    }

    /// 是否为点分十进制 IPv4 地址（IP 无父域概念，避免推导出 "0.37" 这类垃圾标识）
    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty
                && part.count <= 3
                && part.allSatisfy(\.isNumber)
                && (Int(part) ?? 256) < 256
        }
    }

    // MARK: - 域名层级判定

    /// host 的可注册父域：`accounts.ctrip.com` / `m.ctrip.com` -> `ctrip.com`；
    /// 两段式公共后缀（co.uk / com.cn / or.jp）取三段。
    /// host 自身已是父域、公共后缀或无法推导时返回 nil。
    static func registrableDomain(of host: String) -> String? {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return nil }
        let take = twoLevelSuffixLabels.contains(parts[parts.count - 2].lowercased()) ? 3 : 2
        guard parts.count > take else { return nil }
        let domain = parts.suffix(take).joined(separator: ".")
        return domain == host ? nil : domain
    }

    /// host 本身是否为可注册域名（而非 "com"、"co.uk" 这类公共后缀）。
    /// 用途：子域互匹配时，作为父域的一侧必须是可注册域名，
    /// 避免 serviceIdentifier 退化成公共后缀时把所有条目都判为命中
    /// （会把不相关站点的密码填到别人的输入框里）。
    static func isRegistrableDomain(_ host: String) -> Bool {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2, host.count >= 4 else { return false }
        guard let tld = parts.last, tld.count >= 2 else { return false }

        // 两段式公共后缀（co.uk / com.cn / or.jp 等）：末段为国别码、
        // 倒数第二段是通用类型标识时，整个 host 只是后缀而非可注册域名
        if parts.count == 2, twoLevelSuffixLabels.contains(parts[0].lowercased()) {
            return false
        }
        return true
    }

    // MARK: - 匹配

    /// 判断系统传入的 serviceIdentifier（域名或 URL）与条目站点 URL 是否匹配。
    ///
    /// 规则：同域或互为子域，且作为父域的一侧必须是可注册域名；
    /// 无法解析 host 时退化为子串包含匹配（过短的串一律不匹配）。
    /// 供扩展侧按系统请求定位条目使用。
    static func matches(service: String, siteURL: String) -> Bool {
        let serviceTrimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteTrimmed = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serviceTrimmed.isEmpty, !siteTrimmed.isEmpty else {
            return false
        }

        let serviceHost = hostname(from: serviceTrimmed)
        let siteHost = hostname(from: siteTrimmed)

        if let serviceHost, let siteHost {
            if serviceHost == siteHost {
                return true
            }
            if serviceHost.hasSuffix("." + siteHost), isRegistrableDomain(siteHost) {
                return true
            }
            if siteHost.hasSuffix("." + serviceHost), isRegistrableDomain(serviceHost) {
                return true
            }
            return false
        }

        // 无法解析 host 时退化为子串包含匹配；过短的串一律不匹配
        guard serviceTrimmed.count >= 4, siteTrimmed.count >= 4 else {
            return false
        }
        return siteTrimmed.localizedCaseInsensitiveContains(serviceTrimmed)
            || serviceTrimmed.localizedCaseInsensitiveContains(siteTrimmed)
    }
}
