/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// PBKDF2.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import CommonCrypto
import CryptoKit
import Foundation

enum PKCS5 {}

extension PKCS5 {
    static func PBKDF2SHA256(
        password: Data,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> Data {
        var derivedKeyData = Data(repeating: 0, count: keyByteCount)
        
        try derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            try password.withUnsafeBytes { passwordBytes in
                try salt.withUnsafeBytes { saltBytes in
                    let status = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                    
                    guard status == kCCSuccess else {
                        throw CryptoError.keyNotFound
                    }
                }
            }
        }
        
        return derivedKeyData
    }
}

struct HKDF<H: HashFunction> {
    private let salt: Data
    private let info: Data
    private let inputKeyMaterial: SymmetricKey
    private var outputByteCount: Int
    
    private var prk: SymmetricKey
    private var infoWithCounter: Data
    private var counter: UInt8
    private var remainingOutput: Data
    
    init(inputKeyMaterial: SymmetricKey, salt: Data, info: Data, outputByteCount: Int) {
        self.inputKeyMaterial = inputKeyMaterial
        self.salt = salt
        self.info = info
        self.outputByteCount = outputByteCount
        
        let prk = HMAC<H>.authenticationCode(for: inputKeyMaterial.withUnsafeBytes { Data($0) }, using: SymmetricKey(data: salt))
        let prkData = prk.withUnsafeBytes { Data($0) }
        self.prk = SymmetricKey(data: prkData)
        
        self.infoWithCounter = info
        self.counter = 1
        self.remainingOutput = Data()
    }
    
    mutating func read() throws -> Data {
        while remainingOutput.count < outputByteCount {
            var data = Data()
            if !remainingOutput.isEmpty {
                data.append(remainingOutput)
            }
            data.append(infoWithCounter)
            data.append(counter)
            
            let mac = HMAC<H>.authenticationCode(for: data, using: prk)
            let macData = mac.withUnsafeBytes { Data($0) }
            
            remainingOutput.append(macData)
            counter += 1
        }
        
        let output = remainingOutput.prefix(outputByteCount)
        remainingOutput = remainingOutput.dropFirst(outputByteCount)
        return Data(output)
    }
}
