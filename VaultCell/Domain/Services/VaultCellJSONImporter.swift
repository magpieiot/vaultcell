/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultCellJSONImporter.swift
/// created on: 30/08/2026
/// ------------------------------------------------------------------
///
/// 解析 VaultCell 自身导出的明文 JSON 文件（`VaultExportService` 产出格式）：
/// 顶层结构 `{app, formatVersion, exportedAt, categories, passwords, pincodes, bankcards}`。
/// 与导出端使用相同的 ISO8601 日期编码策略。
/// ------------------------------------------------------------------

import Foundation

// MARK: - JSON 载荷

/// VaultCell 明文导出 JSON 的顶层结构（与 `VaultExportService` 的导出端保持一致）
struct VaultCellJSONPayload: Codable {
    let app: String
    let formatVersion: Int
    let exportedAt: Date
    let categories: [PasswordCategory]
    let passwords: [PasswordEntry]
    let pincodes: [PincodeEntry]
    let bankcards: [BankcardEntry]
}

// MARK: - 解析结果

/// VaultCell 明文导出 JSON 的解析结果
struct VaultCellJSONImportResult {
    let payload: VaultCellJSONPayload
    /// 原分类 id → 分类名（入库时按名称映射到本机分类）
    var categoryNames: [UUID: String] {
        Dictionary(
            payload.categories.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

// MARK: - 解析器

/// VaultCell 明文导出 JSON 导入器
enum VaultCellJSONImporter {

    /// 解析 JSON 文件数据
    static func parse(data: Data) throws -> VaultCellJSONImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload: VaultCellJSONPayload
        do {
            payload = try decoder.decode(VaultCellJSONPayload.self, from: data)
        } catch {
            throw VaultImportError.invalidJSON
        }

        guard payload.app == "VaultCell" else {
            throw VaultImportError.invalidJSON
        }
        return VaultCellJSONImportResult(payload: payload)
    }
}
