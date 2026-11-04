import Foundation

/// 云端只接收可重包裹的密钥材料，绝不包含主密码、KEK 或原始 DEK 的 Keychain 备份项。
struct CloudVaultKeyMaterial: Codable, Equatable, Sendable {
    let vaultID: UUID
    let salt: Data
    let wrappedDEK: Data
    let kdfAlgorithm: String
    let kdfIterations: Int
    let wrapAlgorithm: String
    let revision: Int64

    static let currentKDF = "PBKDF2-HMAC-SHA256"
    static let currentWrap = "AES-256-GCM/combined-v1"
}
