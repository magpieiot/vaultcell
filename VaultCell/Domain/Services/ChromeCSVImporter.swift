/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ChromeCSVImporter.swift
/// created on: 04/07/2026
/// ------------------------------------------------------------------

import Foundation

/// Chrome 浏览器导出的密码 CSV 文件解析结果
struct ChromeCSVImportResult {
    /// 解析出的密码条目
    let entries: [PasswordEntry]
    /// 因缺少必填字段（如用户名/密码为空）而跳过的行数
    let skippedCount: Int
}

/// Chrome 浏览器密码 CSV 导入器
/// Chrome 导出的 CSV 文件表头为：name,url,username,password,note
enum ChromeCSVImporter {

    /// Chrome CSV 的标准表头字段
    private static let chromeHeaders = ["name", "url", "username", "password", "note"]

    /// 解析 CSV 文件数据，返回可导入的 PasswordEntry 数组
    /// - Parameter data: CSV 文件的原始数据（UTF-8 编码）
    /// - Returns: 解析结果，包含条目和跳过行数
    static func parse(data: Data) throws -> ChromeCSVImportResult {
        guard let csv = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidEncoding
        }
        return try parse(csv: csv)
    }

    /// 解析 CSV 字符串
    static func parse(csv: String) throws -> ChromeCSVImportResult {
        let rows = parseCSVRows(csv)

        guard !rows.isEmpty else {
            throw ImportError.emptyFile
        }

        // 用第一行做表头映射，支持大小写不敏感
        let headerMap = buildHeaderMap(headerRow: rows[0])
        guard !headerMap.isEmpty else {
            throw ImportError.invalidHeader
        }

        var entries: [PasswordEntry] = []
        var skipped = 0

        for row in rows.dropFirst() {
            // 跳过空行
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            let name = value(for: "name", in: row, using: headerMap)
            let url = value(for: "url", in: row, using: headerMap)
            let username = value(for: "username", in: row, using: headerMap)
            let password = value(for: "password", in: row, using: headerMap)
            let note = value(for: "note", in: row, using: headerMap)

            // 必填字段校验：用户名和密码不能同时为空
            let hasUsername = !(username?.isEmpty ?? true)
            let hasPassword = !(password?.isEmpty ?? true)
            if !hasUsername && !hasPassword {
                skipped += 1
                continue
            }

            let siteName: String
            if let name = name, !name.isEmpty {
                let extracted = extractMainKeyword(from: name)
                siteName = extracted.isEmpty ? deriveSiteName(from: url) : extracted
            } else {
                siteName = deriveSiteName(from: url)
            }

            let entry = PasswordEntry(
                siteName: siteName,
                siteURL: url?.isEmpty == false ? url : nil,
                username: username ?? "",
                password: password ?? "",
                notes: note?.isEmpty == false ? note : nil,
                passwordStrength: PasswordStrength.calculate(for: password ?? ""),
                dataSource: .chromeImport
            )
            entries.append(entry)
        }

        return ChromeCSVImportResult(entries: entries, skippedCount: skipped)
    }

    // MARK: - CSV 解析（支持引号包裹、引号内逗号、引号内换行、双引号转义）

    /// 将 CSV 文本解析为二维字符串数组（每行一个字段数组）
    private static func parseCSVRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentField = ""
        var currentRow: [String] = []
        var inQuotes = false
        var fieldStarted = false

        let characters = Array(csv)
        var i = 0

        while i < characters.count {
            let ch = characters[i]

            if inQuotes {
                if ch == "\"" {
                    // 检查是否为转义的双引号 ""
                    if i + 1 < characters.count && characters[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    currentField.append(ch)
                    i += 1
                    continue
                }
            }

            // 不在引号内
            if ch == "\"" && !fieldStarted {
                inQuotes = true
                fieldStarted = true
                i += 1
                continue
            } else if ch == "\"" {
                inQuotes = true
                i += 1
                continue
            } else if ch == "," {
                currentRow.append(currentField)
                currentField = ""
                fieldStarted = false
                i += 1
                continue
            } else if ch == "\r" {
                // 回车符：处理 \r\n 或单独 \r
                currentRow.append(currentField)
                currentField = ""
                fieldStarted = false
                rows.append(currentRow)
                currentRow = []
                // 跳过可能跟随的 \n
                if i + 1 < characters.count && characters[i + 1] == "\n" {
                    i += 2
                } else {
                    i += 1
                }
                continue
            } else if ch == "\n" {
                currentRow.append(currentField)
                currentField = ""
                fieldStarted = false
                rows.append(currentRow)
                currentRow = []
                i += 1
                continue
            } else {
                currentField.append(ch)
                fieldStarted = true
                i += 1
                continue
            }
        }

        // 处理最后一行/最后一个字段
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    /// 构建表头字段名 -> 列索引 的映射（大小写不敏感）
    private static func buildHeaderMap(headerRow: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, field) in headerRow.enumerated() {
            let key = field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if chromeHeaders.contains(key) {
                map[key] = index
            }
        }
        return map
    }

    /// 根据表头映射从行中取值
    private static func value(for field: String, in row: [String], using map: [String: Int]) -> String? {
        guard let index = map[field], index < row.count else { return nil }
        let value = row[index]
        // 空字符串视为 nil
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    /// 当 name 为空时，从 URL 提取站点名
    private static func deriveSiteName(from url: String?) -> String {
        guard let url = url, !url.isEmpty else { return "Unknown site" }
        // 尝试用 URL 解析提取 host
        if let host = URL(string: url)?.host {
            // 去掉 www. 前缀
            if host.hasPrefix("www.") {
                return String(host.dropFirst(4))
            }
            return host
        }
        // 退化方案：截取 :// 之后到第一个 / 之前
        if let range = url.range(of: "://") {
            let rest = url[range.upperBound...]
            let end = rest.firstIndex(of: "/") ?? rest.endIndex
            return String(rest[..<end])
        }
        return url
    }

    /// 从 Chrome 导出的 name 字段中提取主要关键字作为标题
    ///
    /// Chrome 的 name 通常是网页标题，常带有"登录/Sign in/账号"等冗余信息。
    /// 本方法提取其中的品牌/站点名作为简洁标题。
    ///
    /// 示例：
    /// - "GitHub - Sign in" → "GitHub"
    /// - "Google Accounts" → "Google"
    /// - "百度 - 登录" → "百度"
    /// - "Amazon.com. Spend less." → "Amazon"
    /// - "Sign in - Google Accounts" → "Google"
    private static func extractMainKeyword(from name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // 1. 若整体是 URL，直接提取域名
        if result.contains("://") || result.hasPrefix("www.") {
            return deriveSiteName(from: result)
        }

        // 2. 按常见分隔符切分为多段
        //    仅匹配两侧带空格的分隔符，避免误伤 "Coca-Cola" / "T-Mobile" 等品牌名
        let separators = [" - ", " — ", " – ", " | ", " · ", " : ", " ｜ ", " ： "]
        let marker = "\u{0001}"
        var normalized = result
        for sep in separators {
            normalized = normalized.replacingOccurrences(of: sep, with: marker)
        }
        let segments = normalized.components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 3. 选取第一个非"登录类关键词"的段作为品牌候选
        //    例如 "Sign in - Google" 中第一段 "Sign in" 会被跳过，取 "Google"
        let loginKeywords: Set<String> = [
            "登录", "登陆", "登录页", "登陆页",
            "sign in", "log in", "login", "signin",
            "account", "accounts", "账号", "账户"
        ]
        var candidate = segments.first(where: { !loginKeywords.contains($0.lowercased()) })
            ?? segments.first
            ?? result

        // 4. 按 ". " 切分取首段（处理 "Amazon.com. Spend less. Smile more." 这类）
        if let range = candidate.range(of: ". ") {
            let first = String(candidate[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !first.isEmpty {
                candidate = first
            }
        }

        // 5. 去除尾部的登录/账户类后缀关键词
        let suffixesToRemove = [
            " - 登录", " 登录", "-登录",
            " - 登陆", " 登陆",
            " - Sign in", " Sign in", "-Sign in",
            " - Log in", " Log in", "-Log in",
            " Login", " - Login",
            " Account", " Accounts",
            " 账号", " 账户"
        ]
        for suffix in suffixesToRemove {
            if candidate.lowercased().hasSuffix(suffix.lowercased()) {
                candidate = String(candidate.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 6. 去除尾部的顶级域名后缀（如 "Amazon.com" → "Amazon"）
        let tldSuffixes = [".com", ".cn", ".net", ".org", ".io", ".co", ".cc",
                           ".tv", ".info", ".biz", ".me", ".dev", ".app"]
        let candidateLower = candidate.lowercased()
        for tld in tldSuffixes {
            if candidateLower.hasSuffix(tld) {
                let stripped = String(candidate.dropLast(tld.count))
                if !stripped.isEmpty {
                    candidate = stripped
                }
                break
            }
        }

        result = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

/// 导入相关错误
enum ImportError: LocalizedError {
    case invalidEncoding
    case emptyFile
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Unable to detect file encoding. Please use a UTF-8 encoded CSV file."
        case .emptyFile:
            return "File is empty."
        case .invalidHeader:
            return "Unrecognized CSV header. Please confirm the file was exported from Chrome (should contain name,url,username,password,note)."
        }
    }
}
