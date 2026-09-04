/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultExportService.swift
/// created on: 29/08/2026
/// ------------------------------------------------------------------
///
/// 明文导出服务：按条目类型勾选范围，把密码 / PIN / 银行卡条目导出为 CSV 或 JSON。
///
/// 与「备份」的区别：
/// - 备份（`VaultBackupService`）产出加密的 .vgbackup 文件，用于整机恢复；
/// - 导出产出**明文**文件，用于迁移到其他密码管理器或做表格分析，
///   因此 UI 必须在导出前明确提示风险。
///
/// 数据范围：
/// - 仅导出未删除（`deletedAt == nil`）的条目，回收站内容不参与导出；
/// - 勾选按条目类型（Password / Pincode / Bankcard）进行，Wifi 暂无数据模型、
///   不参与导出，待实现后接入即可；
/// - CSV 中每种类型各自成块（独立表头），JSON 按类型分组；自定义分类
///   （`CategoryRepository`）作为条目属性仍会输出到文件中。
/// ------------------------------------------------------------------

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 导出格式

/// 导出文件格式
enum VaultExportFormat: String, CaseIterable, Identifiable {
    /// 表格文本：每条一行，兼容 Numbers / Excel 以及多数密码管理器的导入
    case csv
    /// 结构化数据：保留全部字段，适合再导回 VaultCell
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: return String(localized: "CSV")
        case .json: return String(localized: "JSON")
        }
    }

    /// 格式说明，展示在选择器下方
    var detail: String {
        switch self {
        case .csv:
            return String(
                localized: "Each item type is grouped in its own block with matching columns. Opens in Numbers / Excel."
            )
        case .json:
            return String(localized: "Keeps every field. Use this to move data back into VaultCell.")
        }
    }

    /// 文件扩展名（用作 `defaultFilename` 后缀）
    var fileExtension: String { rawValue }

    /// 导出面板使用的统一类型标识
    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }
}

// MARK: - 导出文档

/// 导出文件的 FileDocument 封装，供 `fileExporter` 调起系统保存面板。
/// CSV 与 JSON 复用同一类型，实际 UTI 由 `fileExporter` 的 contentType 参数决定。
struct VaultExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, .text] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 导出快照

/// 导出数据可勾选的条目类型。
///
/// Wifi 类型暂无数据模型，计数恒为 0，仅作为占位选项保留（与新建入口的
/// `PasswordType.wifi` 保持一致，待 Wifi 条目实现后即可参与导出）。
enum VaultExportItemType: String, CaseIterable, Identifiable {
    case password
    case pincode
    case bankcard
    case wifi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: return String(localized: "Password")
        case .pincode: return String(localized: "Pincode")
        case .bankcard: return String(localized: "BankCard")
        case .wifi: return String(localized: "Wifi")
        }
    }

    var icon: String {
        switch self {
        case .password: return "key.horizontal.fill"
        case .pincode: return "lock.fill"
        case .bankcard: return "creditcard.fill"
        case .wifi: return "wifi"
        }
    }
}

/// 一次读取得到的待导出数据快照。
///
/// UI 用它统计每个类型下有多少条目，确认导出时直接复用同一份数据生成文件，
/// 避免勾选后数据变化导致 UI 计数与导出结果不一致。
struct VaultExportSnapshot {
    /// 分类列表（按 sortOrder 升序，末尾可能追加"未分类"）
    ///
    /// 过滤以条目类型为准，但 CSV 的 Category 列与 JSON 的 categories 数组
    /// 仍需要这份分类信息，因此快照中保留它。
    let categories: [PasswordCategory]
    /// 未删除的密码条目
    let passwords: [PasswordEntry]
    /// 未删除的 PIN 条目
    let pincodes: [PincodeEntry]
    /// 未删除的银行卡条目
    let bankcards: [BankcardEntry]

    /// 虚拟分类 ID：条目的 categoryID 在分类列表中找不到时，统一归入该分类，
    /// 避免这部分数据在勾选界面"消失"而被静默遗漏。
    static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!

    /// 全部可选条目类型
    var allItemTypes: [VaultExportItemType] { VaultExportItemType.allCases }

    /// 条目总数（不含回收站）
    var totalCount: Int { passwords.count + pincodes.count + bankcards.count }

    /// 单个条目类型下的条目数（Wifi 暂无数据模型，恒为 0）
    func itemCount(for type: VaultExportItemType) -> Int {
        switch type {
        case .password: return passwords.count
        case .pincode: return pincodes.count
        case .bankcard: return bankcards.count
        case .wifi: return 0
        }
    }

    /// 一组条目类型下的条目总数
    func itemCount(in types: Set<VaultExportItemType>) -> Int {
        types.reduce(0) { $0 + itemCount(for: $1) }
    }

    /// 按勾选的条目类型过滤后的快照
    func filtered(by types: Set<VaultExportItemType>) -> VaultExportSnapshot {
        VaultExportSnapshot(
            categories: categories,
            passwords: types.contains(.password) ? passwords : [],
            pincodes: types.contains(.pincode) ? pincodes : [],
            bankcards: types.contains(.bankcard) ? bankcards : []
        )
    }
}

// MARK: - 导出服务

enum VaultExportError: LocalizedError {
    /// 未勾选任何条目类型
    case nothingSelected
    /// 勾选的条目类型里没有任何条目
    case noItemsInSelection

    var errorDescription: String? {
        switch self {
        case .nothingSelected:
            return String(localized: "Select at least one item type to export.")
        case .noItemsInSelection:
            return String(localized: "The selected item types contain no items.")
        }
    }
}

/// 明文导出服务：读取全库数据并按分类范围生成 CSV / JSON 文件。
struct VaultExportService {

    private let categoryRepository: CategoryRepositoryProtocol
    private let passwordRepository: PasswordRepositoryProtocol
    private let pincodeRepository: PincodeRepositoryProtocol
    private let bankcardRepository: BankcardRepositoryProtocol

    init(
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        passwordRepository: PasswordRepositoryProtocol = PasswordRepository(),
        pincodeRepository: PincodeRepositoryProtocol = PincodeRepository(),
        bankcardRepository: BankcardRepositoryProtocol = BankcardRepository()
    ) {
        self.categoryRepository = categoryRepository
        self.passwordRepository = passwordRepository
        self.pincodeRepository = pincodeRepository
        self.bankcardRepository = bankcardRepository
    }

    // MARK: 读取

    /// 读取全部可导出数据。
    ///
    /// 各仓库的 `fetchAll()` 已过滤软删除条目，因此回收站内容不会包含在快照中。
    func loadSnapshot() async throws -> VaultExportSnapshot {
        try await categoryRepository.ensureDefaults()
        let categories = try await categoryRepository.fetchAll()
            .sorted { $0.sortOrder < $1.sortOrder }

        let passwords = try await passwordRepository.fetchAll()
        let pincodes = try await pincodeRepository.fetchAll()
        let bankcards = try await bankcardRepository.fetchAll()

        let knownIDs = Set(categories.map(\.id))
        // 分类被删除后残留的孤儿条目统一归入"未分类"
        let orphanCount =
            passwords.filter { !knownIDs.contains($0.categoryID) }.count
            + pincodes.filter { !knownIDs.contains($0.categoryID) }.count
            + bankcards.filter { !knownIDs.contains($0.categoryID) }.count

        var snapshotCategories = categories
        if orphanCount > 0 {
            snapshotCategories.append(
                PasswordCategory(
                    id: VaultExportSnapshot.uncategorizedID,
                    name: String(localized: "Uncategorized"),
                    icon: "folder.fill",
                    hexColor: "#8E8E93",
                    isSystem: true,
                    sortOrder: .max
                )
            )
        }

        return VaultExportSnapshot(
            categories: snapshotCategories,
            passwords: Self.remappingOrphans(passwords, knownIDs: knownIDs, keyPath: \.categoryID),
            pincodes: Self.remappingOrphans(pincodes, knownIDs: knownIDs, keyPath: \.categoryID),
            bankcards: Self.remappingOrphans(bankcards, knownIDs: knownIDs, keyPath: \.categoryID)
        )
    }

    /// 将分类 ID 已失效的条目重定向到"未分类"。
    private static func remappingOrphans<T>(
        _ entries: [T],
        knownIDs: Set<UUID>,
        keyPath: WritableKeyPath<T, UUID>
    ) -> [T] {
        var result = entries
        for index in result.indices where !knownIDs.contains(result[index][keyPath: keyPath]) {
            result[index][keyPath: keyPath] = VaultExportSnapshot.uncategorizedID
        }
        return result
    }

    // MARK: 生成文件

    /// 生成导出文件内容（同步、可在后台线程执行）。
    ///
    /// - Parameters:
    ///   - snapshot: `loadSnapshot()` 得到的全量快照
    ///   - format: 目标文件格式
    ///   - itemTypes: 用户勾选的条目类型集合
    /// - Returns: 待写入文件的数据
    func makeExportData(
        snapshot: VaultExportSnapshot,
        format: VaultExportFormat,
        itemTypes: Set<VaultExportItemType>
    ) throws -> Data {
        guard !itemTypes.isEmpty else { throw VaultExportError.nothingSelected }

        let selection = snapshot.filtered(by: itemTypes)
        guard selection.totalCount > 0 else { throw VaultExportError.noItemsInSelection }

        switch format {
        case .csv:
            return try makeCSV(snapshot: selection)
        case .json:
            return try makeJSON(snapshot: selection)
        }
    }

    /// 导出文件的默认文件名（VaultCell-Export-年月日-时分.后缀）
    static func defaultFilename(for format: VaultExportFormat, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "VaultCell-Export-\(formatter.string(from: date)).\(format.fileExtension)"
    }

    // MARK: CSV

    /// 密码区块表头（顺序与 `passwordRow` 一致）
    private static let passwordHeader = [
        "Type", "Title", "Category", "Username", "Secret", "Site URL",
        "Notes", "Tags", "Favorite", "Updated At"
    ]

    /// PIN 区块表头（顺序与 `pincodeRow` 一致）
    private static let pincodeHeader = [
        "Type", "Title", "Category", "Pincode",
        "Notes", "Tags", "Favorite", "Updated At"
    ]

    /// 银行卡区块表头（顺序与 `bankcardRow` 一致）
    private static let bankcardHeader = [
        "Type", "Title", "Category", "Cardholder", "Card Number",
        "CVV", "Expiry Date", "Card PIN",
        "Notes", "Tags", "Favorite", "Updated At"
    ]

    /// 生成 CSV：每种条目类型各自成块（独立表头 + 行），块间以空行分隔。
    ///
    /// 不同类型的字段集不同，因此不再共用一个宽表头；只有被勾选且存在数据的
    /// 类型才会出现在文件中（`selection.totalCount > 0` 保证至少有一个区块）。
    private func makeCSV(snapshot: VaultExportSnapshot) throws -> Data {
        let categoryNames = Dictionary(
            uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) }
        )

        var blocks: [String] = []
        blocks.reserveCapacity(3)

        if !snapshot.passwords.isEmpty {
            var lines: [String] = [Self.csvRow(Self.passwordHeader)]
            lines.reserveCapacity(snapshot.passwords.count + 1)
            for entry in snapshot.passwords.sorted(by: Self.byTitle({ $0.siteName })) {
                lines.append(
                    Self.csvRow([
                        "Password", entry.siteName, categoryNames[entry.categoryID] ?? "",
                        entry.username, entry.password, entry.siteURL ?? "",
                        entry.notes ?? "", (entry.tags ?? []).joined(separator: "; "),
                        entry.isFavorite ? "Yes" : "No",
                        Self.isoString(entry.updatedAt ?? entry.createdAt)
                    ])
                )
            }
            blocks.append(lines.joined(separator: "\r\n"))
        }

        if !snapshot.pincodes.isEmpty {
            var lines: [String] = [Self.csvRow(Self.pincodeHeader)]
            lines.reserveCapacity(snapshot.pincodes.count + 1)
            for entry in snapshot.pincodes.sorted(by: Self.byTitle({ $0.title })) {
                lines.append(
                    Self.csvRow([
                        "Pincode", entry.title, categoryNames[entry.categoryID] ?? "",
                        entry.pincode,
                        entry.notes ?? "", (entry.tags ?? []).joined(separator: "; "),
                        entry.isFavorite ? "Yes" : "No",
                        Self.isoString(entry.updatedAt ?? entry.createdAt)
                    ])
                )
            }
            blocks.append(lines.joined(separator: "\r\n"))
        }

        if !snapshot.bankcards.isEmpty {
            var lines: [String] = [Self.csvRow(Self.bankcardHeader)]
            lines.reserveCapacity(snapshot.bankcards.count + 1)
            for entry in snapshot.bankcards.sorted(by: Self.byTitle({ $0.bankName })) {
                lines.append(
                    Self.csvRow([
                        "Bankcard", entry.bankName, categoryNames[entry.categoryID] ?? "",
                        entry.cardholder, entry.cardNumber,
                        entry.cvv ?? "", entry.expiryDate, entry.pin ?? "",
                        entry.notes ?? "", (entry.tags ?? []).joined(separator: "; "),
                        entry.isFavorite ? "Yes" : "No",
                        Self.isoString(entry.updatedAt ?? entry.createdAt)
                    ])
                )
            }
            blocks.append(lines.joined(separator: "\r\n"))
        }

        // UTF-8 BOM：保证 Excel / Numbers 正确识别中文
        return Data("\u{FEFF}".utf8) + Data(blocks.joined(separator: "\r\n\r\n").utf8)
    }

    /// 按标题升序的比较器（用于 CSV 输出稳定排序）
    private static func byTitle<T>(_ title: @escaping (T) -> String) -> (T, T) -> Bool {
        { title($0).localizedCaseInsensitiveCompare(title($1)) == .orderedAscending }
    }

    /// 拼一行 CSV：字段中含分隔符 / 引号 / 换行时用双引号包裹并转义内部引号
    private static func csvRow(_ fields: [String]) -> String {
        fields.map { field -> String in
            let needsQuoting =
                field.contains(",") || field.contains("\"")
                || field.contains("\n") || field.contains("\r")
            guard needsQuoting else { return field }
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        .joined(separator: ",")
    }

    // MARK: JSON

    private struct JSONPayload: Codable {
        let app: String
        let formatVersion: Int
        let exportedAt: Date
        let categories: [PasswordCategory]
        let passwords: [PasswordEntry]
        let pincodes: [PincodeEntry]
        let bankcards: [BankcardEntry]
    }

    private func makeJSON(snapshot: VaultExportSnapshot) throws -> Data {
        let payload = JSONPayload(
            app: "VaultCell",
            formatVersion: 1,
            exportedAt: Date(),
            categories: snapshot.categories,
            passwords: snapshot.passwords,
            pincodes: snapshot.pincodes,
            bankcards: snapshot.bankcards
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private static func isoString(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter.string(
            from: date, timeZone: .current, formatOptions: [.withInternetDateTime]
        )
    }
}
