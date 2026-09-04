/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultBackupService.swift
/// created on: 28/08/2026
/// ------------------------------------------------------------------

import Foundation
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份文件类型

extension UTType {
    /// VaultCell 加密备份文件（.vgbackup），需在 Info.plist 的
    /// UTExportedTypeDeclarations 中声明同名类型
    static let vaultBackup = UTType(exportedAs: "com.magpie.vaultcell.backup", conformingTo: .data)
}

// MARK: - 备份文件 Document

/// 加密备份文件的 FileDocument 封装，用于 fileExporter 导出系统保存面板
struct VaultBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.vaultBackup, .data] }

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

/// 备份文件错误类型
enum VaultBackupError: Error, LocalizedError {
    /// 文件不是有效的 VaultCell 加密备份（magic 校验失败或内容损坏）
    case invalidFormat
    /// 备份密码错误（AES-GCM 认证失败）
    case wrongPassword
    /// 单条笔记过大，超出单个分段 4GB 的长度上限
    case backupTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return String(localized: "This file is not a valid VaultCell backup.")
        case .wrongPassword:
            return String(localized: "Wrong backup password.")
        case .backupTooLarge:
            return String(localized: "A note is too large to include in the backup.")
        }
    }
}

/// 加密备份服务：将全部条目（密码 / PIN / 银行卡 / 安全笔记）导出为独立加密的
/// 备份文件，或从备份恢复条目。
///
/// 文件格式（v4，分段式，控制附件明文的内存峰值）：
///
/// | magic "VGVAULT2" | salt (32B) | 分段数 (4B) | 分段 × N |
///
/// 每个分段独立加密：
///
/// | 密文长度 (4B, 大端) | nonce (12B) | tag (16B) | ciphertext |
///
/// - 分段 0：元数据（version / exportedAt / passwords / pincodes / bankcards）
/// - 分段 1..N：每段一条安全笔记（含附件图片明文），独立加密
///
/// 历史格式（magic "VGVAULT1"，单块整体加密）：
/// - v1：载荷仅含密码条目（`entries` 字段）；
/// - v2：按类型分组（`passwords` / `pincodes` / `bankcards` 字段）；
/// - v3：新增 `safeNotes`（含笔记附件图片的明文数据）。
///   恢复时兼容读取 v1–v3 旧备份（缺失的类型恒为空）。
///
/// 备份使用与保险库主密钥体系相互独立的密钥：由备份密码经
/// PBKDF2-HMAC-SHA256（600k 迭代）+ 随机盐派生 AES-256 密钥，
/// 以 AES-GCM 认证加密各分段明文（每段独立随机 nonce）。因此恢复备份时
/// 需要输入导出时设置的备份密码，与当前保险库的主密码无关。
struct VaultBackupService {

    /// v4 分段格式文件头魔数
    static let magic = Data("VGVAULT2".utf8)
    /// v1–v3 单块格式文件头魔数（仅用于兼容恢复旧备份）
    static let magicLegacy = Data("VGVAULT1".utf8)

    /// v1–v3 单块格式的载荷结构（仅用于兼容恢复旧备份）
    ///
    /// `entries` 为 v1 备份的旧字段；`passwords` / `pincodes` / `bankcards`
    /// 为 v2 起的新字段；`safeNotes` 为 v3 起的新字段。所有数组字段均为可选，
    /// 以兼容不同版本互相解码。
    private struct Payload: Codable {
        let version: Int
        let exportedAt: Date
        /// v1 备份：仅密码条目
        let entries: [PasswordEntry]?
        /// v2 备份：密码条目
        let passwords: [PasswordEntry]?
        /// v2 备份：PIN 条目
        let pincodes: [PincodeEntry]?
        /// v2 备份：银行卡条目
        let bankcards: [BankcardEntry]?
        /// v3 备份：安全笔记（含附件图片明文数据）
        let safeNotes: [SafeNoteBackup]?

        init(
            version: Int = 3,
            exportedAt: Date = Date(),
            passwords: [PasswordEntry],
            pincodes: [PincodeEntry],
            bankcards: [BankcardEntry],
            safeNotes: [SafeNoteBackup]
        ) {
            self.version = version
            self.exportedAt = exportedAt
            self.entries = nil
            self.passwords = passwords
            self.pincodes = pincodes
            self.bankcards = bankcards
            self.safeNotes = safeNotes
        }

        /// 解码后的密码条目（v2 优先，v1 回退到 entries）
        var resolvedPasswords: [PasswordEntry] { passwords ?? entries ?? [] }
        /// 解码后的 PIN 条目（v1 备份恒为空）
        var resolvedPincodes: [PincodeEntry] { pincodes ?? [] }
        /// 解码后的银行卡条目（v1 备份恒为空）
        var resolvedBankcards: [BankcardEntry] { bankcards ?? [] }
        /// 解码后的安全笔记（v1 / v2 备份恒为空）
        var resolvedSafeNotes: [SafeNoteBackup] { safeNotes ?? [] }
    }

    private let keyDerivationService: KeyDerivationServiceProtocol
    private let encryptionService: EncryptionServiceProtocol
    private let safeNoteRepository: SafeNoteRepositoryProtocol
    private let fileStorage: EncryptedFileStorageProtocol

    init(
        keyDerivationService: KeyDerivationServiceProtocol = KeyDerivationService(),
        encryptionService: EncryptionServiceProtocol = EncryptionService.shared,
        safeNoteRepository: SafeNoteRepositoryProtocol = SafeNoteRepository(),
        fileStorage: EncryptedFileStorageProtocol = EncryptedFileStorage()
    ) {
        self.keyDerivationService = keyDerivationService
        self.encryptionService = encryptionService
        self.safeNoteRepository = safeNoteRepository
        self.fileStorage = fileStorage
    }

    // MARK: - 导出

    /// 将全部条目（密码 / PIN / 银行卡 / 安全笔记）加密为 v4 分段备份文件
    ///
    /// 内存优化：安全笔记逐条处理——仅当前笔记的附件图片解密进内存，
    /// 加密为独立分段后立即释放，避免全部附件明文同时驻留内存，
    /// 导致低内存设备被系统终止。
    ///
    /// - Parameters:
    ///   - passwords: 待备份的密码条目（明文，仅在内存中短暂存在）
    ///   - pincodes: 待备份的 PIN 条目
    ///   - bankcards: 待备份的银行卡条目
    ///   - password: 备份密码，用于派生加密密钥
    /// - Returns: 完整的备份文件内容与条目总数（用于导出结果提示）
    func exportData(
        passwords: [PasswordEntry],
        pincodes: [PincodeEntry],
        bankcards: [BankcardEntry],
        password: String
    ) async throws -> (data: Data, itemCount: Int) {
        // 笔记元数据（含正文文本）体量小，可一次性载入；附件图片逐条解密
        let notes = try await safeNoteRepository.fetchAllFull()

        // 每次导出生成新盐，避免同一密码在不同备份间复用密钥
        let salt = try keyDerivationService.generateSalt()
        let key = try keyDerivationService.deriveMasterKey(from: password, salt: salt)

        var data = Data()
        data.append(Self.magic)
        data.append(salt)
        // 分段数 = 元数据段 1 + 笔记段 N
        appendUInt32(UInt32(1 + notes.count), to: &data)

        // 元数据段：密码 / PIN / 银行卡（体量小，单段加密）
        let meta = MetaPayload(
            passwords: passwords,
            pincodes: pincodes,
            bankcards: bankcards
        )
        try appendSegment(JSONEncoder().encode(meta), key: key, to: &data)

        // 笔记段：每条笔记独立加密，附件明文处理完即释放
        for note in notes {
            let backup = makeSafeNoteBackup(from: note)
            try appendSegment(JSONEncoder().encode(backup), key: key, to: &data)
        }
        return (data, passwords.count + pincodes.count + bankcards.count + notes.count)
    }

    /// 组装单条笔记的备份载荷（附件图片解密为明文；调用方加密后应立即释放）
    private func makeSafeNoteBackup(from note: SafeNote) -> SafeNoteBackup {
        var imageDataByAssetID: [UUID: Data] = [:]
        var thumbnailDataByAssetID: [UUID: Data] = [:]
        for asset in note.assets {
            // 单张图片解密失败时跳过该附件（保留笔记正文），避免整份备份失败
            if let data = try? fileStorage.loadDecryptedData(at: asset.encryptedFilePath) {
                imageDataByAssetID[asset.id] = data
            }
            if let data = try? fileStorage.loadDecryptedData(at: asset.encryptedThumbnailPath) {
                thumbnailDataByAssetID[asset.id] = data
            }
        }
        return SafeNoteBackup(
            note: note,
            imageDataByAssetID: imageDataByAssetID,
            thumbnailDataByAssetID: thumbnailDataByAssetID
        )
    }

    /// 追加一个加密分段：4 字节大端长度前缀 + combined（nonce + tag + 密文）
    private func appendSegment(_ plaintext: Data, key: SymmetricKey, to data: inout Data) throws {
        let combined = try encryptionService.encrypt(plaintext, using: key).combined
        // 分段长度以 4 字节无符号整数写入；整数转换构造器越界会直接 trap
        // （闪退），因此用可失败构造显式校验后抛错
        guard let length = UInt32(exactly: combined.count) else {
            throw VaultBackupError.backupTooLarge
        }
        appendUInt32(length, to: &data)
        data.append(combined)
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(Data($0)) }
    }

    // MARK: - 恢复

    /// 解析备份文件并验证备份密码，返回可流式读取的备份读取器
    ///
    /// 兼容历史格式：
    /// - v4（magic "VGVAULT2"）：分段格式，安全笔记逐段惰性解密，附件明文不常驻内存；
    /// - v1–v3（magic "VGVAULT1"）：旧单块格式，内容一次性解码。
    ///
    /// - Throws: `VaultBackupError.invalidFormat`（文件损坏）、
    ///           `VaultBackupError.wrongPassword`（密码错误）
    func makeBackupReader(from data: Data, password: String) throws -> BackupReader {
        if data.starts(with: Self.magic) {
            return try makeSegmentedReader(from: data, password: password)
        }
        if data.starts(with: Self.magicLegacy) {
            return try makeLegacyReader(from: data, password: password)
        }
        throw VaultBackupError.invalidFormat
    }

    /// v4 分段格式：magic + salt + 分段数 + [长度前缀 + combined] × N
    private func makeSegmentedReader(from data: Data, password: String) throws -> BackupReader {
        let saltLength = KeyDerivationService.saltSize
        // 固定头 + 最小分段（4B 长度前缀 + nonce 12 + tag 16）
        let fixedHeaderLength = Self.magic.count + saltLength + 4
        guard data.count >= fixedHeaderLength + 4 + 28 else {
            throw VaultBackupError.invalidFormat
        }

        let saltStart = Self.magic.count
        let saltEnd = saltStart + saltLength
        let salt = data.subdata(in: saltStart..<saltEnd)
        let key = try keyDerivationService.deriveMasterKey(from: password, salt: salt)

        let countBytes = [UInt8](data.subdata(in: saltEnd..<(saltEnd + 4)))
        let segmentCount = (Int(countBytes[0]) << 24)
            | (Int(countBytes[1]) << 16)
            | (Int(countBytes[2]) << 8)
            | Int(countBytes[3])

        // 构造时即解码并验证元数据段（密码错误在此暴露）
        return try BackupReader(
            rawData: data,
            key: key,
            encryptionService: encryptionService,
            segmentCount: segmentCount,
            readOffset: saltEnd + 4
        )
    }

    /// v1–v3 单块格式：magic + salt + combined（整体 JSON 载荷）
    private func makeLegacyReader(from data: Data, password: String) throws -> BackupReader {
        let saltLength = KeyDerivationService.saltSize
        // magic + salt + (nonce 12 + tag 16 + 至少 1 字节密文)
        let headerLength = Self.magicLegacy.count + saltLength + 28
        guard data.count > headerLength,
              data.prefix(Self.magicLegacy.count) == Self.magicLegacy
        else {
            throw VaultBackupError.invalidFormat
        }

        let saltStart = Self.magicLegacy.count
        let saltEnd = saltStart + saltLength
        let salt = data.subdata(in: saltStart..<saltEnd)

        let encrypted: EncryptedData
        do {
            encrypted = try EncryptedData.fromCombined(data.suffix(from: saltEnd))
        } catch {
            throw VaultBackupError.invalidFormat
        }

        let key = try keyDerivationService.deriveMasterKey(from: password, salt: salt)

        let plaintext: Data
        do {
            plaintext = try encryptionService.decrypt(encrypted, using: key)
        } catch CryptoKitError.authenticationFailure {
            // 认证失败意味着密码错误或密文被篡改，统一按密码错误提示
            throw VaultBackupError.wrongPassword
        } catch {
            throw VaultBackupError.invalidFormat
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: plaintext)
            return BackupReader(
                passwords: payload.resolvedPasswords,
                pincodes: payload.resolvedPincodes,
                bankcards: payload.resolvedBankcards,
                legacyNotes: payload.resolvedSafeNotes
            )
        } catch {
            throw VaultBackupError.invalidFormat
        }
    }
}

/// v4 备份元数据段载荷（不含安全笔记，笔记独立分段加密）
private struct MetaPayload: Codable {
    let version: Int
    let exportedAt: Date
    let passwords: [PasswordEntry]
    let pincodes: [PincodeEntry]
    let bankcards: [BankcardEntry]

    init(passwords: [PasswordEntry], pincodes: [PincodeEntry], bankcards: [BankcardEntry]) {
        self.version = 4
        self.exportedAt = Date()
        self.passwords = passwords
        self.pincodes = pincodes
        self.bankcards = bankcards
    }
}

/// 备份读取器：元数据（密码 / PIN / 银行卡）已解码，
/// 安全笔记按段惰性解密——每次只解密一条，附件明文在调用方处理完即释放，
/// 避免全部附件同时驻留内存导致低内存设备被系统终止。
final class BackupReader: @unchecked Sendable {
    let passwords: [PasswordEntry]
    let pincodes: [PincodeEntry]
    let bankcards: [BankcardEntry]
    /// 备份中的安全笔记数量（v1 / v2 备份恒为 0）
    let noteCount: Int

    // v4 分段读取状态
    private let rawData: Data?
    private let key: SymmetricKey?
    private let encryptionService: EncryptionServiceProtocol?
    private let segmentCount: Int
    /// 下一个待读取笔记分段的索引（元数据段为 0，从 1 开始）
    private var nextSegmentIndex: Int
    /// 下一个分段在 rawData 中的起始偏移
    private var readOffset: Int

    // v1–v3 旧格式：笔记随元数据一次性解码，顺序迭代返回
    private let legacyNotes: [SafeNoteBackup]
    private var legacyIndex = 0

    /// v4 分段格式构造：构造时即解码并验证元数据段（密码错误在此暴露）
    init(
        rawData: Data,
        key: SymmetricKey,
        encryptionService: EncryptionServiceProtocol,
        segmentCount: Int,
        readOffset: Int
    ) throws {
        self.rawData = rawData
        self.key = key
        self.encryptionService = encryptionService
        self.segmentCount = segmentCount
        self.readOffset = readOffset
        self.nextSegmentIndex = 1
        self.legacyNotes = []

        var offset = readOffset
        let plaintext = try Self.decryptSegment(
            at: &offset,
            in: rawData,
            key: key,
            encryptionService: encryptionService,
            authFailureError: .wrongPassword
        )
        self.readOffset = offset

        guard let meta = try? JSONDecoder().decode(MetaPayload.self, from: plaintext) else {
            throw VaultBackupError.invalidFormat
        }
        self.passwords = meta.passwords
        self.pincodes = meta.pincodes
        self.bankcards = meta.bankcards
        self.noteCount = max(segmentCount - 1, 0)
    }

    /// v1–v3 旧格式构造：全部内容已解码
    init(
        passwords: [PasswordEntry],
        pincodes: [PincodeEntry],
        bankcards: [BankcardEntry],
        legacyNotes: [SafeNoteBackup]
    ) {
        self.passwords = passwords
        self.pincodes = pincodes
        self.bankcards = bankcards
        self.noteCount = legacyNotes.count
        self.rawData = nil
        self.key = nil
        self.encryptionService = nil
        self.segmentCount = 0
        self.readOffset = 0
        self.nextSegmentIndex = 0
        self.legacyNotes = legacyNotes
    }

    var isEmpty: Bool {
        passwords.isEmpty && pincodes.isEmpty && bankcards.isEmpty && noteCount == 0
    }

    var totalCount: Int {
        passwords.count + pincodes.count + bankcards.count + noteCount
    }

    /// 在后台解密并返回下一条安全笔记；迭代完毕返回 nil。
    /// 每次仅解密一个分段，附件明文随返回值交给调用方，处理完即释放。
    func nextNoteInBackground() async throws -> SafeNoteBackup? {
        try await Task.detached(priority: .userInitiated) { [self] in
            try nextNote()
        }.value
    }

    private func nextNote() throws -> SafeNoteBackup? {
        if !legacyNotes.isEmpty {
            guard legacyIndex < legacyNotes.count else { return nil }
            defer { legacyIndex += 1 }
            return legacyNotes[legacyIndex]
        }

        guard nextSegmentIndex < segmentCount,
              let rawData,
              let key,
              let encryptionService
        else {
            return nil
        }

        var offset = readOffset
        let plaintext = try Self.decryptSegment(
            at: &offset,
            in: rawData,
            key: key,
            encryptionService: encryptionService,
            // 密码已在元数据段验证通过，此处认证失败说明文件损坏
            authFailureError: .invalidFormat
        )
        readOffset = offset
        nextSegmentIndex += 1

        guard let note = try? JSONDecoder().decode(SafeNoteBackup.self, from: plaintext) else {
            throw VaultBackupError.invalidFormat
        }
        return note
    }

    /// 读取 offset 处的一个分段（4 字节大端长度前缀 + combined），解密并推进 offset
    private static func decryptSegment(
        at offset: inout Int,
        in data: Data,
        key: SymmetricKey,
        encryptionService: EncryptionServiceProtocol,
        authFailureError: VaultBackupError
    ) throws -> Data {
        guard offset + 4 <= data.count else {
            throw VaultBackupError.invalidFormat
        }
        let lengthBytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        let length = (Int(lengthBytes[0]) << 24)
            | (Int(lengthBytes[1]) << 16)
            | (Int(lengthBytes[2]) << 8)
            | Int(lengthBytes[3])
        let combinedStart = offset + 4
        let combinedEnd = combinedStart + length
        guard combinedEnd <= data.count else {
            throw VaultBackupError.invalidFormat
        }
        offset = combinedEnd

        let encrypted: EncryptedData
        do {
            encrypted = try EncryptedData.fromCombined(data.subdata(in: combinedStart..<combinedEnd))
        } catch {
            // 分段长度不足一个 GCM 头（nonce + tag）时由 fromCombined 抛出
            throw VaultBackupError.invalidFormat
        }

        do {
            return try encryptionService.decrypt(encrypted, using: key)
        } catch CryptoKitError.authenticationFailure {
            throw authFailureError
        } catch {
            throw VaultBackupError.invalidFormat
        }
    }
}

/// 备份中的安全笔记：笔记元数据 + 附件图片的明文数据。
///
/// 导出时由本机 DEK 解密图片得到明文，整条笔记加密为独立分段写入备份；
/// 恢复时由备份密钥逐段解密后，通过 `SafeNoteRepository.save(_:draftAssets:)`
/// 用目标设备的 DEK 重新加密存储。
struct SafeNoteBackup: Codable {
    /// 笔记元数据（`assets` 中的加密路径仅用于恢复时的顺序与封面信息）
    var note: SafeNote
    /// assetID → 原图明文数据
    var imageDataByAssetID: [UUID: Data]
    /// assetID → 缩略图明文数据（可选，缺失时恢复会自动重新生成）
    var thumbnailDataByAssetID: [UUID: Data]
}
