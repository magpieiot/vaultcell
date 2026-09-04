/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultCellCSVImporter.swift
/// created on: 30/08/2026
/// ------------------------------------------------------------------
///
/// 解析 VaultCell 自身导出的明文 CSV 文件（`VaultExportService` 产出格式）：
/// - 按条目类型分块（Password / Pincode / Bankcard），每块独立表头，块间空行分隔；
/// - 文件以 UTF-8 BOM 开头，用于 Excel / Numbers 正确识别中文；
/// - CSV 中仅含基础字段，条目入库时的分类按名称映射到本机分类。
/// ------------------------------------------------------------------

import Foundation

// MARK: - 通用 CSV 行解析

/// 无依赖的 CSV 行解析器：支持引号包裹、引号内逗号、引号内换行、双引号转义。
/// 与 `ChromeCSVImporter` 内部的解析逻辑等价，供 VaultCell 自身 CSV 导入复用。
enum CSVLineParser {

    /// 将 CSV 文本解析为二维字符串数组（每行一个字段数组）
    static func parse(_ csv: String) -> [[String]] {
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
                    // 转义的双引号 ""
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
                currentRow.append(currentField)
                currentField = ""
                fieldStarted = false
                rows.append(currentRow)
                currentRow = []
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

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}

// MARK: - VaultCell CSV 解析结果

/// VaultCell 明文导出 CSV 的解析结果
struct VaultCellCSVImportResult {
    let passwords: [PasswordEntry]
    let pincodes: [PincodeEntry]
    let bankcards: [BankcardEntry]
    /// 条目 id → 原 CSV 中的分类名（入库时按名称映射到本机分类）
    let categoryNames: [UUID: String]
    /// 因缺少必填字段而跳过的行数
    let skippedCount: Int

    var totalCount: Int { passwords.count + pincodes.count + bankcards.count }
}

// MARK: - 解析器

/// VaultCell 明文导出 CSV 导入器
enum VaultCellCSVImporter {

    /// 解析 CSV 文件数据
    static func parse(data: Data) throws -> VaultCellCSVImportResult {
        var data = data
        // 去掉 UTF-8 BOM（导出时写入以保证 Excel / Numbers 识别中文）
        if data.starts(with: Data("\u{FEFF}".utf8)) {
            data = data.dropFirst(3)
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidEncoding
        }
        return try parse(csv: csv)
    }

    /// 解析 CSV 字符串
    static func parse(csv: String) throws -> VaultCellCSVImportResult {
        let rows = CSVLineParser.parse(csv)
        guard !rows.isEmpty else { throw ImportError.emptyFile }

        var passwords: [PasswordEntry] = []
        var pincodes: [PincodeEntry] = []
        var bankcards: [BankcardEntry] = []
        var categoryNames: [UUID: String] = [:]
        var skipped = 0

        // 当前块的表头映射（遇到新的 "Type" 表头行时更新）
        var headerMap: [String: Int] = [:]

        for row in rows {
            guard let first = row.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !first.isEmpty
            else { continue }

            // 表头行：本 app 各块表头均以 "Type" 开头
            if first.caseInsensitiveCompare("Type") == .orderedSame {
                headerMap = buildHeaderMap(headerRow: row)
                continue
            }
            guard !headerMap.isEmpty else { continue }

            let type = value(for: "Type", in: row, using: headerMap)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch type {
            case "password":
                if let entry = makePasswordEntry(row: row, using: headerMap) {
                    passwords.append(entry.entry)
                    if let name = entry.categoryName {
                        categoryNames[entry.entry.id] = name
                    }
                } else {
                    skipped += 1
                }
            case "pincode":
                if let entry = makePincodeEntry(row: row, using: headerMap) {
                    pincodes.append(entry.entry)
                    if let name = entry.categoryName {
                        categoryNames[entry.entry.id] = name
                    }
                } else {
                    skipped += 1
                }
            case "bankcard":
                if let entry = makeBankcardEntry(row: row, using: headerMap) {
                    bankcards.append(entry.entry)
                    if let name = entry.categoryName {
                        categoryNames[entry.entry.id] = name
                    }
                } else {
                    skipped += 1
                }
            default:
                // 非本 app 数据行（空行等）跳过
                skipped += 1
            }
        }

        return VaultCellCSVImportResult(
            passwords: passwords,
            pincodes: pincodes,
            bankcards: bankcards,
            categoryNames: categoryNames,
            skippedCount: skipped
        )
    }

    // MARK: - 各类型行解析

    private static func makePasswordEntry(row: [String], using headerMap: [String: Int])
        -> (entry: PasswordEntry, categoryName: String?)?
    {
        let title = value(for: "Title", in: row, using: headerMap)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = value(for: "Secret", in: row, using: headerMap)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !title.isEmpty, !secret.isEmpty else { return nil }

        let entry = PasswordEntry(
            siteName: title,
            siteURL: cleaned(value(for: "Site URL", in: row, using: headerMap)),
            username: cleaned(value(for: "Username", in: row, using: headerMap)) ?? "",
            password: secret,
            notes: cleaned(value(for: "Notes", in: row, using: headerMap)),
            tags: parseTags(value(for: "Tags", in: row, using: headerMap)),
            isFavorite: isFavorite(value(for: "Favorite", in: row, using: headerMap)),
            createdAt: parseDate(value(for: "Updated At", in: row, using: headerMap)) ?? Date(),
            updatedAt: parseDate(value(for: "Updated At", in: row, using: headerMap)) ?? Date(),
            dataSource: .manual
        )
        return (entry, cleaned(value(for: "Category", in: row, using: headerMap)))
    }

    private static func makePincodeEntry(row: [String], using headerMap: [String: Int])
        -> (entry: PincodeEntry, categoryName: String?)?
    {
        let title = value(for: "Title", in: row, using: headerMap)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pincode = value(for: "Pincode", in: row, using: headerMap)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !title.isEmpty, !pincode.isEmpty else { return nil }

        let entry = PincodeEntry(
            title: title,
            pincode: pincode,
            notes: cleaned(value(for: "Notes", in: row, using: headerMap)),
            tags: parseTags(value(for: "Tags", in: row, using: headerMap)),
            isFavorite: isFavorite(value(for: "Favorite", in: row, using: headerMap)),
            createdAt: parseDate(value(for: "Updated At", in: row, using: headerMap)) ?? Date(),
            updatedAt: parseDate(value(for: "Updated At", in: row, using: headerMap)) ?? Date(),
            dataSource: .manual
        )
        return (entry, cleaned(value(for: "Category", in: row, using: headerMap)))
    }

    private static func makeBankcardEntry(row: [String], using headerMap: [String: Int])
        -> (entry: BankcardEntry, categoryName: String?)?
    {
        let title = value(for: "Title", in: row, using: headerMap)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cardNumber = value(for: "Card Number", in: row, using: headerMap)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !title.isEmpty, !cardNumber.isEmpty else { return nil }

        let entry = BankcardEntry(
            bankName: title,
            cardNumber: cardNumber,
            cvv: cleaned(value(for: "CVV", in: row, using: headerMap)),
            cardholder: cleaned(value(for: "Cardholder", in: row, using: headerMap)) ?? "",
            expiryDate: cleaned(value(for: "Expiry Date", in: row, using: headerMap)) ?? "",
            pin: cleaned(value(for: "Card PIN", in: row, using: headerMap)),
            notes: cleaned(value(for: "Notes", in: row, using: headerMap)),
            tags: parseTags(value(for: "Tags", in: row, using: headerMap)),
            isFavorite: isFavorite(value(for: "Favorite", in: row, using: headerMap)),
            createdAt: parseDate(value(for: "Updated At", in: row, using: headerMap)) ?? Date(),
            updatedAt: parseDate(value(for: "Updated At", in: row, using: headerMap)) ?? Date(),
            dataSource: .manual
        )
        return (entry, cleaned(value(for: "Category", in: row, using: headerMap)))
    }

    // MARK: - 字段辅助

    /// 构建表头字段名 -> 列索引 映射（大小写不敏感）
    private static func buildHeaderMap(headerRow: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, field) in headerRow.enumerated() {
            let key = field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            map[key] = index
        }
        return map
    }

    /// 根据表头映射从行中取值
    private static func value(for field: String, in row: [String], using map: [String: Int]) -> String? {
        guard let index = map[field.lowercased()], index < row.count else { return nil }
        let value = row[index]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    /// 去除首尾空白；空串视为 nil
    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 解析标签列（"; " 分隔）
    private static func parseTags(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Favorite 列：Yes / true 视为收藏
    private static func isFavorite(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "yes" || normalized == "true"
    }

    /// 解析 ISO8601 时间（导出格式为带时区的 InternetDateTime）
    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
