/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultImportService.swift
/// created on: 30/08/2026
/// ------------------------------------------------------------------
///
/// 统一的导入服务：自动识别导入源（本 app 导出的 JSON / CSV、Chrome CSV），
/// 并产出统一的解析结果，供 ViewModel 去重入库。
/// ------------------------------------------------------------------

import Foundation

// MARK: - 导入源

/// 自动识别出的导入来源
enum VaultImportSource {
    /// 本 app 导出的 JSON（保留全字段）
    case vaultCellJSON
    /// 本 app 导出的 CSV（按类型分块）
    case vaultCellCSV
    /// Chrome 浏览器导出的密码 CSV
    case chromeCSV

    var displayName: String {
        switch self {
        case .vaultCellJSON: return String(localized: "VaultCell JSON")
        case .vaultCellCSV: return String(localized: "VaultCell CSV")
        case .chromeCSV: return String(localized: "Chrome CSV")
        }
    }
}

// MARK: - 解析结果

/// 统一导入解析结果
struct VaultImportParseResult {
    let source: VaultImportSource
    let passwords: [PasswordEntry]
    let pincodes: [PincodeEntry]
    let bankcards: [BankcardEntry]
    /// 条目 id → 原文件中的分类名（入库时按名称映射到本机分类）
    let categoryNames: [UUID: String]
    /// 因缺少必填字段而跳过的行数
    let skippedCount: Int

    var totalCount: Int { passwords.count + pincodes.count + bankcards.count }
}

// MARK: - 错误

/// 导入识别 / 解析错误
enum VaultImportError: LocalizedError {
    case invalidEncoding
    case emptyFile
    case invalidJSON
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return String(localized: "Unable to detect file encoding. Please use a UTF-8 encoded file.")
        case .emptyFile:
            return String(localized: "File is empty.")
        case .invalidJSON:
            return String(localized: "This JSON file is not a valid VaultCell export.")
        case .unrecognizedFormat:
            return String(
                localized: "Unrecognized file format. Please import a VaultCell export (CSV/JSON) or a Chrome passwords CSV.")
        }
    }
}

// MARK: - 导入服务

/// 导入服务：自动识别文件格式并解析为统一的导入结果
enum VaultImportService {

    /// 识别并解析导入文件
    ///
    /// 识别顺序：
    /// 1. VaultCell JSON（顶层 `app == "VaultCell"` 且结构可解码）；
    /// 2. Chrome CSV（表头含 name,url,username,password）；
    /// 3. VaultCell CSV（表头含 Type 列，按块解析）。
    static func parse(data: Data) throws -> VaultImportParseResult {
        var data = data
        // 去掉 UTF-8 BOM（本 app CSV 导出带 BOM）
        if data.starts(with: Data("\u{FEFF}".utf8)) {
            data = data.dropFirst(3)
        }

        // 1. VaultCell JSON
        if let json = try? VaultCellJSONImporter.parse(data: data) {
            var categoryNames: [UUID: String] = [:]
            let nameByID = json.categoryNames
            for entry in json.payload.passwords {
                categoryNames[entry.id] = nameByID[entry.categoryID]
            }
            for entry in json.payload.pincodes {
                categoryNames[entry.id] = nameByID[entry.categoryID]
            }
            for entry in json.payload.bankcards {
                categoryNames[entry.id] = nameByID[entry.categoryID]
            }
            return VaultImportParseResult(
                source: .vaultCellJSON,
                passwords: json.payload.passwords,
                pincodes: json.payload.pincodes,
                bankcards: json.payload.bankcards,
                categoryNames: categoryNames,
                skippedCount: 0
            )
        }

        // 2 / 3. CSV
        guard let text = String(data: data, encoding: .utf8) else {
            throw VaultImportError.invalidEncoding
        }
        let rows = CSVLineParser.parse(text)
        guard let headerRow = rows.first, !headerRow.isEmpty else {
            throw VaultImportError.emptyFile
        }

        let headerSet = Set(
            headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        // Chrome CSV：name,url,username,password 均出现即判定
        let chromeFields = ["name", "url", "username", "password"]
        if chromeFields.allSatisfy({ headerSet.contains($0) }) {
            let result = try ChromeCSVImporter.parse(csv: text)
            return VaultImportParseResult(
                source: .chromeCSV,
                passwords: result.entries,
                pincodes: [],
                bankcards: [],
                categoryNames: [:],
                skippedCount: result.skippedCount
            )
        }

        // VaultCell CSV：首列表头为 Type
        if headerSet.contains("type") {
            let result = try VaultCellCSVImporter.parse(csv: text)
            return VaultImportParseResult(
                source: .vaultCellCSV,
                passwords: result.passwords,
                pincodes: result.pincodes,
                bankcards: result.bankcards,
                categoryNames: result.categoryNames,
                skippedCount: result.skippedCount
            )
        }

        throw VaultImportError.unrecognizedFormat
    }

    // MARK: - 入库

    /// 将统一解析结果去重入库，返回新增条数（设置页与首次引导页共用）。
    ///
    /// 去重规则：
    /// - 密码：按站点名 + 用户名（忽略大小写）；
    /// - PIN：按标题 + 码值；
    /// - 银行卡：按卡号（纯数字）。
    /// 分类映射：本机存在同 ID 分类则保留，否则按名称匹配本机分类，兜底到默认分类。
    static func persist(
        parseResult result: VaultImportParseResult,
        existingPasswords: [PasswordEntry],
        existingPincodes: [PincodeEntry],
        existingBankcards: [BankcardEntry],
        categories: [PasswordCategory],
        passwordRepository: PasswordRepositoryProtocol = PasswordRepository(),
        pincodeRepository: PincodeRepositoryProtocol = PincodeRepository(),
        bankcardRepository: BankcardRepositoryProtocol = BankcardRepository()
    ) async throws -> Int {
        // 分类兜底：首次引导时 referenceData 可能尚未加载完成
        let resolvedCategories = categories.isEmpty ? PasswordCategory.systemDefaults : categories
        let knownCategoryIDs = Set(resolvedCategories.map(\.id))
        let nameToCategoryID = Dictionary(
            resolvedCategories.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        func mappedCategoryID(for entryID: UUID, originalID: UUID) -> UUID {
            if knownCategoryIDs.contains(originalID) { return originalID }
            if let name = result.categoryNames[entryID],
                let id = nameToCategoryID[name.lowercased()]
            {
                return id
            }
            return PasswordCategory.defaultCategoryID
        }

        var inserted = 0

        // 密码条目
        var seenPasswordKeys = Set(
            existingPasswords.map { seedIdentity(siteName: $0.siteName, username: $0.username) }
        )
        for var entry in result.passwords {
            let key = seedIdentity(siteName: entry.siteName, username: entry.username)
            if seenPasswordKeys.contains(key) { continue }
            entry.categoryID = mappedCategoryID(for: entry.id, originalID: entry.categoryID)
            try await passwordRepository.save(entry)
            seenPasswordKeys.insert(key)
            inserted += 1
        }

        // PIN 条目
        var seenPincodeKeys = Set(
            existingPincodes.map { "\($0.title.lowercased())|\($0.pincode)" }
        )
        for var entry in result.pincodes {
            let key = "\(entry.title.lowercased())|\(entry.pincode)"
            if seenPincodeKeys.contains(key) { continue }
            entry.categoryID = mappedCategoryID(for: entry.id, originalID: entry.categoryID)
            try await pincodeRepository.save(entry)
            seenPincodeKeys.insert(key)
            inserted += 1
        }

        // 银行卡条目
        let normalizeCard: (String) -> String = { $0.filter(\.isNumber) }
        var seenCardKeys = Set(existingBankcards.map { normalizeCard($0.cardNumber) })
        for var entry in result.bankcards {
            let key = normalizeCard(entry.cardNumber)
            if key.isEmpty || seenCardKeys.contains(key) { continue }
            entry.categoryID = mappedCategoryID(for: entry.id, originalID: entry.categoryID)
            try await bankcardRepository.save(entry)
            seenCardKeys.insert(key)
            inserted += 1
        }

        return inserted
    }

    /// 密码条目去重标识（站点名 + 用户名，忽略大小写）。
    /// 与 `SettingsViewModel.seedIdentity` 保持等价，避免跨页面导入口径不一致。
    private static func seedIdentity(siteName: String, username: String) -> String {
        "\(siteName.lowercased())|\(username.lowercased())"
    }
}
