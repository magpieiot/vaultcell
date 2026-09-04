/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TOTPService.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import CryptoKit
import Foundation

/// TOTP 哈希算法（RFC 6238 §1.2）
enum TOTPAlgorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    /// CryptoKit 对应的 HMAC 类型
    var hmacName: String {
        switch self {
        case .sha1: return "SHA1"
        case .sha256: return "SHA256"
        case .sha512: return "SHA512"
        }
    }
}

/// TOTP 配置：描述生成一次性密码所需的全部参数。
struct TOTPConfig {
    /// 共享密钥（Base32 编码字符串，例如 "JBSWY3DPEHPK3PXP"）
    let secret: String
    /// 哈希算法，默认 SHA1（兼容 Google Authenticator）
    var algorithm: TOTPAlgorithm = .sha1
    /// 验证码位数，默认 6（部分服务支持 8 位）
    var digits: Int = 6
    /// 时间步长（秒），默认 30
    var period: Int = 30

    init(secret: String, algorithm: TOTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
}

/// TOTP 生成结果
struct TOTPResult {
    /// 当前生成的验证码（字符串形式，保留前导零）
    let code: String
    /// 当前时间步内剩余秒数
    let remainingSeconds: Int
    /// 当前时间步进度（0.0 ~ 1.0），可用于环形进度条动画
    let progress: Double
}

/// RFC 6238 TOTP 生成服务
/// 标准实现，兼容 Google Authenticator / Microsoft Authenticator 等。
final class TOTPService {

    static let shared = TOTPService()

    private init() {}

    // MARK: - 公开接口

    /// 根据配置生成当前 TOTP 验证码
    /// - Parameter config: TOTP 配置
    /// - Returns: 验证码 + 剩余时间 + 进度
    func generate(config: TOTPConfig) -> TOTPResult {
        let now = Int(Date().timeIntervalSince1970)
        let counter = now / config.period
        let code = generate(at: UInt64(counter), config: config)
        let elapsed = now % config.period
        let remaining = config.period - elapsed
        let progress = Double(elapsed) / Double(config.period)
        return TOTPResult(code: code, remainingSeconds: remaining, progress: progress)
    }

    /// 生成指定时间步的 TOTP 验证码
    /// - Parameters:
    ///   - counter: 时间步计数器（T = floor(timestamp / period)）
    ///   - config: TOTP 配置
    /// - Returns: 验证码字符串
    func generate(at counter: UInt64, config: TOTPConfig) -> String {
        let key = decodeBase32(config.secret)
        let hmac = computeHMAC(key: key, counter: counter, algorithm: config.algorithm)
        let code = dynamicTruncate(hmac: hmac, digits: config.digits)
        return String(format: "%0\(config.digits)d", code)
    }

    /// 验证用户输入的 TOTP 验证码是否正确
    /// - Parameters:
    ///   - code: 用户输入的验证码
    ///   - config: TOTP 配置
    ///   - window: 允许的时间窗口偏移（默认 1，即前后各 1 步容忍）
    /// - Returns: 是否验证通过
    func validate(code: String, config: TOTPConfig, window: Int = 1) -> Bool {
        let now = UInt64(Date().timeIntervalSince1970)
        let currentCounter = now / UInt64(config.period)

        for offset in -window...window {
            let counter: UInt64
            if offset >= 0 {
                counter = currentCounter &+ UInt64(offset)
            } else {
                counter = currentCounter &- UInt64(-offset)
            }
            let expected = generate(at: counter, config: config)
            if constantTimeCompare(expected, code) {
                return true
            }
        }
        return false
    }

    // MARK: - otpauth:// URI 解析

    /// 解析 otpauth:// URI（Google Authenticator 导出格式）
    /// - Parameter uri: otpauth URI 字符串
    /// - Returns: 解析出的 TOTP 配置 + issuer + account（失败返回 nil）
    func parseOTPAuthURI(_ uri: String) -> (config: TOTPConfig, issuer: String?, account: String?)? {
        guard let url = URL(string: uri),
              url.scheme == "otpauth",
              url.host == "totp" else {
            return nil
        }

        let label = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let labelComponents = label.split(separator: ":", maxSplits: 1).map(String.init)
        let issuerFromLabel = labelComponents.count == 2 ? labelComponents[0] : nil
        let account = labelComponents.count == 2 ? labelComponents[1] : label

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        let secret = queryItems.first { $0.name == "secret" }?.value ?? ""
        guard !secret.isEmpty else { return nil }

        let algorithmStr = queryItems.first { $0.name == "algorithm" }?.value?.uppercased()
        let algorithm = TOTPAlgorithm(rawValue: algorithmStr ?? "SHA1") ?? .sha1

        let digits = Int(queryItems.first { $0.name == "digits" }?.value ?? "6") ?? 6
        let period = Int(queryItems.first { $0.name == "period" }?.value ?? "30") ?? 30

        let issuerParam = queryItems.first { $0.name == "issuer" }?.value
        let issuer = issuerParam ?? issuerFromLabel

        return (TOTPConfig(secret: secret, algorithm: algorithm, digits: digits, period: period), issuer, account)
    }

    // MARK: - 内部算法实现

    /// Base32 解码（RFC 4648）
    private func decodeBase32(_ input: String) -> Data {
        let cleaned = input
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "=", with: "")
            .uppercased()

        let base32Chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0
        var value = 0
        var output = Data()

        for char in cleaned {
            guard let index = base32Chars.firstIndex(of: char) else { continue }
            value = (value << 5) | index
            bits += 5

            if bits >= 8 {
                bits -= 8
                let byte = UInt8((value >> UInt(bits)) & 0xFF)
                output.append(byte)
            }
        }

        return output
    }

    /// 计算 HMAC
    /// - Parameters:
    ///   - key: 原始密钥字节
    ///   - counter: 时间步计数器
    ///   - algorithm: 哈希算法
    /// - Returns: HMAC 结果
    private func computeHMAC(key: Data, counter: UInt64, algorithm: TOTPAlgorithm) -> Data {
        var counterBigEndian = counter.bigEndian
        let counterData = Data(bytes: &counterBigEndian, count: 8)
        let symmetricKey = SymmetricKey(data: key)

        switch algorithm {
        case .sha1:
            var mac = HMAC<Insecure.SHA1>(key: symmetricKey)
            mac.update(data: counterData)
            return Data(mac.finalize())
        case .sha256:
            var mac = HMAC<SHA256>(key: symmetricKey)
            mac.update(data: counterData)
            return Data(mac.finalize())
        case .sha512:
            var mac = HMAC<SHA512>(key: symmetricKey)
            mac.update(data: counterData)
            return Data(mac.finalize())
        }
    }

    /// 动态截取（Dynamic Truncation, RFC 4226 §5.3）
    /// - Parameters:
    ///   - hmac: HMAC 结果
    ///   - digits: 验证码位数
    /// - Returns: 截取后的数字
    private func dynamicTruncate(hmac: Data, digits: Int) -> Int {
        let offset = Int(hmac[hmac.count - 1] & 0x0F)
        guard hmac.count >= offset + 4 else { return 0 }

        let truncated = (Int(hmac[offset] & 0x7F) << 24)
                      | (Int(hmac[offset + 1] & 0xFF) << 16)
                      | (Int(hmac[offset + 2] & 0xFF) << 8)
                      |  Int(hmac[offset + 3] & 0xFF)

        let modulus = Int(pow(10.0, Double(digits)))
        return truncated % modulus
    }

    /// 恒时比较，防止时序攻击
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a.utf8, b.utf8) {
            result |= x ^ y
        }
        return result == 0
    }
}
