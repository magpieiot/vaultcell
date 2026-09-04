/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// EncryptedFileStorage.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import Foundation
import UIKit

protocol EncryptedFileStorageProtocol {
    func saveImage(data: Data, noteID: UUID, assetID: UUID) throws -> String
    func saveThumbnail(data: Data, noteID: UUID, assetID: UUID) throws -> String
    func loadDecryptedData(at relativePath: String) throws -> Data
    func deleteFile(at relativePath: String) throws
    func deleteFiles(for noteID: UUID) throws
    func optimizedImageData(from data: Data, maxDimension: CGFloat) -> Data?
    func thumbnailData(from data: Data, maxDimension: CGFloat) -> Data?
    func imageSize(from data: Data) -> CGSize?
}

final class EncryptedFileStorage: EncryptedFileStorageProtocol {
    private let fileManager: FileManager
    private let encryptionService: EncryptionServiceProtocol
    private let appGroupIdentifier = "group.com.magpie.vaultcell.shared"

    init(
        fileManager: FileManager = .default,
        encryptionService: EncryptionServiceProtocol = EncryptionService.shared
    ) {
        self.fileManager = fileManager
        self.encryptionService = encryptionService
    }

    func saveImage(data: Data, noteID: UUID, assetID: UUID) throws -> String {
        try saveEncrypted(data: data, noteID: noteID, filename: "\(assetID.uuidString).bin")
    }

    func saveThumbnail(data: Data, noteID: UUID, assetID: UUID) throws -> String {
        try saveEncrypted(data: data, noteID: noteID, filename: "\(assetID.uuidString)_thumb.bin")
    }

    func loadDecryptedData(at relativePath: String) throws -> Data {
        let fileURL = containerBaseURL().appendingPathComponent(relativePath, isDirectory: false)
        let encryptedData = try Data(contentsOf: fileURL)
        return try encryptionService.decryptToData(encryptedData)
    }

    func deleteFile(at relativePath: String) throws {
        let fileURL = containerBaseURL().appendingPathComponent(relativePath, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func deleteFiles(for noteID: UUID) throws {
        let noteURL = storageDirectoryURL().appendingPathComponent(noteID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: noteURL.path) else { return }
        try fileManager.removeItem(at: noteURL)
    }

    func optimizedImageData(from data: Data, maxDimension: CGFloat = 2000) -> Data? {
        guard let image = UIImage(data: data),
              let resized = resizedImage(from: image, maxDimension: maxDimension) else {
            return nil
        }
        return encodedData(for: resized, originalImage: image)
    }

    func thumbnailData(from data: Data, maxDimension: CGFloat = 320) -> Data? {
        guard let image = UIImage(data: data),
              let resized = resizedImage(from: image, maxDimension: maxDimension) else {
            return nil
        }
        return encodedData(for: resized, originalImage: image, jpegQuality: 0.72)
    }

    func imageSize(from data: Data) -> CGSize? {
        UIImage(data: data)?.size
    }

    private func saveEncrypted(data: Data, noteID: UUID, filename: String) throws -> String {
        let noteDirectoryURL = storageDirectoryURL().appendingPathComponent(noteID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: noteDirectoryURL, withIntermediateDirectories: true)

        let encrypted = try encryptionService.encrypt(data).combined
        let fileURL = noteDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        try encrypted.write(to: fileURL, options: .atomic)

        return "SafeNotes/\(noteID.uuidString)/\(filename)"
    }

    private func storageDirectoryURL() -> URL {
        containerBaseURL().appendingPathComponent("SafeNotes", isDirectory: true)
    }

    private func containerBaseURL() -> URL {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
        }

        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportURL
    }

    private func resizedImage(from image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func encodedData(
        for image: UIImage,
        originalImage: UIImage,
        jpegQuality: CGFloat = 0.8
    ) -> Data? {
        let hasAlpha = originalImage.cgImage?.alphaInfo == .premultipliedLast ||
            originalImage.cgImage?.alphaInfo == .premultipliedFirst ||
            originalImage.cgImage?.alphaInfo == .last ||
            originalImage.cgImage?.alphaInfo == .first

        if hasAlpha {
            return image.pngData()
        }

        return image.jpegData(compressionQuality: jpegQuality)
    }
}
