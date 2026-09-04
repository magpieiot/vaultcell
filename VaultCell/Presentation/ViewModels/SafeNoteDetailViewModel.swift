/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SafeNoteDetailViewModel.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 安全笔记详情页视图模型
/// 负责加载完整笔记（含正文与图片元数据），并管理缩略图/原图的解密缓存。
@MainActor
final class SafeNoteDetailViewModel: ObservableObject {
    @Published var note: SafeNote?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var decryptedThumbnails: [UUID: UIImage] = [:]
    /// 当前大图浏览器中正在查看的资产索引
    @Published var currentFullImageIndex: Int = 0
    /// 已解密原图缓存，key 为资产 ID
    @Published var decryptedFullImages: [UUID: UIImage] = [:]
    @Published var isShowingFullImage: Bool = false

    private let noteID: UUID
    private let service: SafeNoteVaultService
    private let fileStorage: EncryptedFileStorageProtocol

    init(
        noteID: UUID,
        service: SafeNoteVaultService,
        fileStorage: EncryptedFileStorageProtocol = EncryptedFileStorage()
    ) {
        self.noteID = noteID
        self.service = service
        self.fileStorage = fileStorage
    }

    func loadNote() async {
        isLoading = true
        defer { isLoading = false }
        note = await service.loadNote(by: noteID)
        if note != nil {
            await service.updateLastViewed(noteID)
        }
    }

    /// 加载并缓存缩略图
    func loadThumbnail(for asset: SafeNoteAsset) async {
        guard decryptedThumbnails[asset.id] == nil else { return }
        do {
            let data = try fileStorage.loadDecryptedData(at: asset.encryptedThumbnailPath)
            if let image = UIImage(data: data) {
                decryptedThumbnails[asset.id] = image
            }
        } catch {
            errorMessage = "Failed to load thumbnail"
        }
    }

    /// 打开大图浏览器并定位到指定索引
    func showFullImage(at index: Int) {
        currentFullImageIndex = index
        isShowingFullImage = true
    }

    /// 加载指定资产的原图并缓存
    func loadFullImage(for asset: SafeNoteAsset) async {
        guard decryptedFullImages[asset.id] == nil else { return }
        do {
            let data = try fileStorage.loadDecryptedData(at: asset.encryptedFilePath)
            if let image = UIImage(data: data) {
                decryptedFullImages[asset.id] = image
            }
        } catch {
            errorMessage = "Failed to load full image"
        }
    }

    func dismissFullImage() {
        isShowingFullImage = false
        decryptedFullImages.removeAll()
        currentFullImageIndex = 0
    }
}
