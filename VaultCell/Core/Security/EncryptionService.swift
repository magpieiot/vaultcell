/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// EncryptionService.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import CryptoKit
import Foundation

struct EncryptedData: Codable {
    let ciphertext: Data
    let nonce: Data
    let tag: Data
    let version: String

    init(ciphertext: Data, nonce: AES.GCM.Nonce, tag: Data, version: String = "1.0") {
        self.ciphertext = ciphertext
        self.nonce = nonce.withUnsafeBytes { Data($0) }
        self.tag = tag
        self.version = version
    }

    init(ciphertext: Data, nonce: Data, tag: Data, version: String = "1.0") {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
        self.version = version
    }

    func getAESNonce() throws -> AES.GCM.Nonce {
        return try AES.GCM.Nonce(data: nonce)
    }

    var combined: Data {
        var data = Data()
        // 格式: nonce (12 bytes + tag (16 bytes) + ciphertext
        data.append(nonce)
        data.append(tag)
        data.append(ciphertext)
        return data
    }

    static func fromCombined(_ data: Data) throws -> EncryptedData {
        // nonce(12) + tag(16) + ciphertext(≥0)。明文为空时 ciphertext 为 0 字节，总长度恰好 28 字节，因此使用 >= 28。
        guard data.count >= 28 else {
            throw CryptoError.invalidData
        }
        // 必须基于 startIndex 取绝对索引切片：调用方可能传入 Data slice
        // （如 VaultBackupService 中 data.suffix(from:) 的结果，startIndex 为
        // magic+salt 长度），若仍按 0..<28 切片，会在 subdata(in:) 中越界
        // 触发 precondition failure 导致崩溃。
        let start = data.startIndex
        let end = data.endIndex
        let nonceData = data.subdata(in: start..<(start + 12))
        let tagData = data.subdata(in: (start + 12)..<(start + 28))
        let ciphertextData = data.subdata(in: (start + 28)..<end)
        return EncryptedData(
            ciphertext: ciphertextData,
            nonce: nonceData,
            tag: tagData
        )
    }
}

enum CryptoError: Error, LocalizedError {
    case invalidKeySize
    case invalidData
    case invalidNonce
    case authenticationFailed
    case keyNotFound
    case saltGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .invalidKeySize:
            return "Invalid key size"
        case .invalidData:
            return "Invalid data"
        case .invalidNonce:
            return "Invalid nonce"
        case .authenticationFailed:
            return "Authentication failed"
        case .keyNotFound:
            return "Key not found"
        case .saltGenerationFailed:
            return "Salt generation failed"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidPassword:
            return "Invalid password"
        }
    }
}

protocol EncryptionServiceProtocol {
    func encrypt(_ plaintext: String) throws -> EncryptedData
    func encrypt(_ data: Data) throws -> EncryptedData
    func encrypt(_ plaintext: String, using key: SymmetricKey) throws -> EncryptedData
    func encrypt(_ data: Data, using key: SymmetricKey) throws -> EncryptedData
    func decrypt(_ encrypted: EncryptedData, using key: SymmetricKey) throws -> Data
    func decryptToString(_ encrypted: EncryptedData, using key: SymmetricKey) throws -> String

    func decrypt(_ data: Data) throws -> String
    func decryptToData(_ data: Data) throws -> Data

    /// 清除内存中的数据加密密钥（DEK），在应用锁定/退到后台时调用
    func clearEncryptionKey()
}

class EncryptionService: EncryptionServiceProtocol {
    static let shared = EncryptionService()

    private var currentKey: SymmetricKey?
    private let keyLock = NSLock()

    init() {}

    private func getKey() -> SymmetricKey? {
        keyLock.lock()
        defer { keyLock.unlock() }
        return currentKey
    }

    func setEncryptionKey(_ key: SymmetricKey) {
        keyLock.lock()
        currentKey = key
        keyLock.unlock()
    }

    func clearEncryptionKey() {
        keyLock.lock()
        currentKey = nil
        keyLock.unlock()
    }

    func encrypt(_ plaintext: String) throws -> EncryptedData {
        guard let key = getKey() else {
            throw CryptoError.keyNotFound
        }
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidData
        }
        return try encrypt(data, using: key)
    }

    func encrypt(_ data: Data) throws -> EncryptedData {
        guard let key = getKey() else {
            throw CryptoError.keyNotFound
        }
        return try encrypt(data, using: key)
    }

    func encrypt(_ plaintext: String, using key: SymmetricKey) throws -> EncryptedData {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidData
        }
        return try encrypt(data, using: key)
    }

    func encrypt(_ data: Data, using key: SymmetricKey) throws -> EncryptedData {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        return EncryptedData(
            ciphertext: sealedBox.ciphertext,
            nonce: nonce,
            tag: sealedBox.tag
        )
    }

    func decrypt(_ encrypted: EncryptedData, using key: SymmetricKey) throws -> Data {
        let nonce = try encrypted.getAESNonce()
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encrypted.ciphertext,
            tag: encrypted.tag
        )
        return try AES.GCM.open(sealedBox, using: key)
    }

    func decryptToString(_ encrypted: EncryptedData, using key: SymmetricKey) throws -> String {
        let data = try decrypt(encrypted, using: key)
        guard let result = String(data: data, encoding: .utf8) else {
            throw CryptoError.invalidData
        }
        return result
    }

    func decrypt(_ data: Data) throws -> String {
        guard let key = getKey() else {
            throw CryptoError.keyNotFound
        }
        let encrypted = try EncryptedData.fromCombined(data)
        return try decryptToString(encrypted, using: key)
    }

    func decryptToData(_ data: Data) throws -> Data {
        guard let key = getKey() else {
            throw CryptoError.keyNotFound
        }
        let encrypted = try EncryptedData.fromCombined(data)
        return try decrypt(encrypted, using: key)
    }
}

protocol KeyDerivationServiceProtocol {
    func deriveMasterKey(from password: String, salt: Data) throws -> SymmetricKey
    func deriveSubKeys(from masterKey: SymmetricKey) throws -> KeySet
    func generateSalt() throws -> Data
}

struct KeySet {
    let dataEncryptionKey: SymmetricKey
    let keyEncryptionKey: SymmetricKey
    let hmacKey: SymmetricKey
}

class KeyDerivationService: KeyDerivationServiceProtocol {
    static let pbkdf2Iterations = 600_000
    static let saltSize = 32
    static let masterKeySize = 32

    func generateSalt() throws -> Data {
        var salt = Data(count: Self.saltSize)
        let result = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, Self.saltSize, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw CryptoError.saltGenerationFailed
        }
        return salt
    }

    func deriveMasterKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.precomposedStringWithCanonicalMapping.data(using: .utf8)
        else {
            throw CryptoError.invalidPassword
        }

        let masterKeyData = try PKCS5.PBKDF2SHA256(
            password: passwordData,
            salt: salt,
            iterations: Self.pbkdf2Iterations,
            keyByteCount: Self.masterKeySize
        )
        return SymmetricKey(data: masterKeyData)
    }

    func deriveSubKeys(from masterKey: SymmetricKey) throws -> KeySet {
        let dataEncryptionKey = try masterKey.deriveSubKey(
            info: "VaultCell_DEK_v1",
            outputLength: 32
        )

        let keyEncryptionKey = try masterKey.deriveSubKey(
            info: "VaultCell_KEK_v1",
            outputLength: 32
        )

        let hmacKey = try masterKey.deriveSubKey(
            info: "VaultCell_HMAC_v1",
            outputLength: 32
        )

        return KeySet(
            dataEncryptionKey: dataEncryptionKey,
            keyEncryptionKey: keyEncryptionKey,
            hmacKey: hmacKey
        )
    }
}

extension SymmetricKey {
    func deriveSubKey(info: String, outputLength: Int) throws -> SymmetricKey {
        let salt = "VaultCell_HKDF_Salt_v1".data(using: .utf8)!
        let infoData = info.data(using: .utf8)!

        var hkdf = HKDF<SHA512>(
            inputKeyMaterial: self,
            salt: salt,
            info: infoData,
            outputByteCount: outputLength
        )

        var derivedKey = Data()
        while derivedKey.count < outputLength {
            try derivedKey.append(hkdf.read())
        }

        return SymmetricKey(data: derivedKey)
    }
}

extension Data {
    func constantTimeCompare(_ other: Data) -> Bool {
        guard self.count == other.count else {
            return false
        }
        var result = 0
        for (a, b) in zip(self, other) {
            result |= Int(a ^ b)
        }
        return result == 0
    }
}
