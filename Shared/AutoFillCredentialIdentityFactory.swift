/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AutoFillCredentialIdentityFactory.swift
/// ------------------------------------------------------------------
///
/// 自动填充身份（credential identity）构造的唯一定义，由主 App（全量同步时
/// 注册身份）与 AutoFillProvider 扩展（保存密码后补登身份）共同编译。
///
/// 与 `AutoFillDomainMatcher` 同源的理由一致：注册端推导出的 serviceIdentifier
/// 必须与匹配端能命中的形式保持一致；两端各写一份副本时迟早漂移，表现为
/// "注册了但键盘建议不命中"或"保存后仍没有建议"。

import AuthenticationServices
import Foundation

enum AutoFillCredentialIdentityFactory {

    /// 扩展保存密码时使用的默认分类。
    ///
    /// 必须与主 App `PasswordCategory.systemDefaults` 的第一项（Primary）一致，
    /// 否则扩展写入的条目在主 App 里会落到一个不存在的分类下而无法显示。
    static let defaultCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// 一条条目要注册的全部 serviceIdentifier。
    ///
    /// 真机实测（iOS 26）得到的匹配结论：
    /// - 用户名域的"登录建议 sheet"只认**精确主机**命中（条目存 apex、页面在子域时不弹）；
    /// - 父域（apex）身份仍能覆盖子域页面的**密码域键盘建议**；
    /// - 条目存 apex 时页面常落在 `www.` 主机上，需要保留 www 变体；
    /// - 带 path 的原样 URL 没有必要：host 级即可命中 Safari 深层登录页。
    ///
    /// 因此每条目只登记**两个主机**（各 domain/URL 两型，共 4 条身份）：
    /// 子域条目 = 精确主机 + 父域；apex 条目 = 精确主机 + www 变体；
    /// IP / `.android` 这类无法推导变体的只有自身（2 条）。
    static func serviceIdentifiers(from siteURL: String?) -> [ASCredentialServiceIdentifier] {
        guard let host = AutoFillDomainMatcher.hostname(from: siteURL ?? "") else { return [] }
        // 单标签（如把应用名 "app" 填进 URL 栏）不是可路由站点，注册无意义
        guard host.contains(".") else { return [] }

        var hosts: [String] = [host]
        if AutoFillDomainMatcher.isIPv4(host) {
            // IP 地址没有 www 变体，也不能按域名推导父域（会产出 "0.37" 这类垃圾标识）
        } else if host.hasSuffix(".android") {
            // Android 包名（如 com.instagram.android）被误填进 URL：保留原样但不做变体
        } else if let parent = AutoFillDomainMatcher.registrableDomain(of: host) {
            // 子域条目：补父域，让同站其它子域的页面至少还能拿到密码域建议
            hosts.append(parent)
        } else if !host.hasPrefix("www.") {
            // apex 条目：hostname 已把 www 剥掉，这里补回来覆盖"页面在 www"的常见场景
            hosts.append("www." + host)
        }

        var result: [ASCredentialServiceIdentifier] = []
        var seen = Set<String>()

        func append(identifier: String, type: ASCredentialServiceIdentifier.IdentifierType) {
            let key = "\(type == .domain ? "d" : "u")|\(identifier)"
            guard seen.insert(key).inserted else { return }
            result.append(ASCredentialServiceIdentifier(identifier: identifier, type: type))
        }

        for candidate in hosts {
            // domain 型覆盖 App 侧，URL 型覆盖 Safari 侧（只留 scheme + 主机，不带路径）
            append(identifier: candidate, type: .domain)
            append(identifier: "https://\(candidate)", type: .URL)
        }

        return result
    }

    /// 一个条目对应的全部身份。
    ///
    /// 同一条目注册多条身份时 `recordIdentifier` 必须唯一：系统按它标识"一条凭据"，
    /// 重复会导致部分身份被丢弃。首条用裸条目 ID，其余加 "#序号" 后缀；
    /// 扩展侧取 "#" 前的部分即可还原条目 ID（见 CredentialProviderViewController）。
    static func identities(entryID: UUID, username: String, siteURL: String?) -> [ASPasswordCredentialIdentity] {
        let identifiers = serviceIdentifiers(from: siteURL)
        return identifiers.enumerated().map { index, identifier in
            ASPasswordCredentialIdentity(
                serviceIdentifier: identifier,
                user: username,
                recordIdentifier: index == 0
                    ? entryID.uuidString
                    : "\(entryID.uuidString)#\(index)"
            )
        }
    }
}
