/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// SafeNoteDetailView.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import SwiftUI
import UIKit

/// 安全笔记详情页
/// 展示单条笔记的标题、正文以及图片网格。图片以缩略图形式加载，点击后进入全屏大图浏览器，可左右滑动浏览并查看页码指示器。
struct SafeNoteDetailView: View {
    @StateObject private var viewModel: SafeNoteDetailViewModel
    @State private var isPresentingEditor: Bool = false
    @State private var navigationBarWidth: CGFloat = 0
    private let service: SafeNoteVaultService

    init(noteID: UUID, service: SafeNoteVaultService) {
        self.service = service
        _viewModel = StateObject(
            wrappedValue: SafeNoteDetailViewModel(noteID: noteID, service: service)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.note == nil {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let note = viewModel.note {
                    headerSection(note: note)
                    imageGridSection(note: note)
                    contentSection(note: note)
                } else {
                    ContentUnavailableView(
                        "Failed to load notes",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Please try again later.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.note?.title ?? String(localized: "Note Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: TabBarVisibilityKey.self, value: true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { navigationBarWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        navigationBarWidth = newWidth
                    }
            }
        )
        .task {
            await viewModel.loadNote()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isPresentingEditor = true
                }
                .disabled(viewModel.note == nil)
            }
        }
        .sheet(
            isPresented: $isPresentingEditor,
            onDismiss: {
                Task {
                    await viewModel.loadNote()
                }
            }
        ) {
            if let note = viewModel.note {
                EditSafeNoteView(
                    viewModel: SafeNoteEditorViewModel(
                        service: service,
                        editingNote: note
                    )
                )
            }
        }
        .fullScreenCover(isPresented: $viewModel.isShowingFullImage) {
            if let assets = viewModel.note?.assets, !assets.isEmpty {
                FullImageSheet(
                    viewModel: viewModel,
                    assets: assets,
                    onDismiss: viewModel.dismissFullImage
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private func headerSection(note: SafeNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 当导航栏标题被截断时，在正文顶部显示完整标题
            if isTitleTruncated(note.title) {
                Text(note.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Label(note.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    /// 判断标题在导航栏 inline 模式下是否会被截断。
    /// 导航栏 inline 标题可用宽度约为屏幕宽度减去左右按钮区域（约 160pt），
    /// 通过 NSString.boundingRect 计算标题在 17pt 系统字体下的固有宽度进行比较。
    private func isTitleTruncated(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }

        // 导航栏左右按钮约占用的宽度（返回按钮 + 编辑按钮 + 间距）
        let navigationBarReservedWidth: CGFloat = 160
        let availableWidth = navigationBarWidth > 0
            ? max(navigationBarWidth - navigationBarReservedWidth, 80)
            : UIScreen.main.bounds.width - navigationBarReservedWidth

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        let bounds = (title as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
        return bounds.width > availableWidth
    }

    private func contentSection(note: SafeNote) -> some View {
        Group {
            if note.content.isEmpty {
                Text("No content")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(note.content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func imageGridSection(note: SafeNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            
            let sortedAssets = note.assets.sorted(by: { $0.sortOrder < $1.sortOrder })
            let columnCount = columnCount(for: sortedAssets.count)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount),
                spacing: 4
            ) {
                ForEach(Array(sortedAssets.enumerated()), id: \.element.id) { index, asset in
                    AssetThumbnailCell(
                        asset: asset,
                        thumbnail: viewModel.decryptedThumbnails[asset.id],
                        cornerRadius: 4
                    )
                    .onTapGesture {
                        viewModel.showFullImage(at: index)
                    }
                    .task {
                        await viewModel.loadThumbnail(for: asset)
                    }
                }
            }
        }
    }

    /// 根据图片数量决定列数：
    /// - 0~2 张：2 列
    /// - 3 张：3 列
    /// - 4 张及以上：4 列
    private func columnCount(for imageCount: Int) -> Int {
        switch imageCount {
        case 0...2: return 2
        case 3: return 3
        default: return 4
        }
    }
}

private struct AssetThumbnailCell: View {
    let asset: SafeNoteAsset
    let thumbnail: UIImage?
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(.systemGray5))
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct FullImageSheet: View {
    @ObservedObject var viewModel: SafeNoteDetailViewModel
    let assets: [SafeNoteAsset]
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $viewModel.currentFullImageIndex) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    fullImagePage(for: asset)
                        .tag(index)
                        .task {
                            await viewModel.loadFullImage(for: asset)
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea()

            // 右上角关闭按钮
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        
            // 底部页码指示
            VStack {
                Spacer()
                Text("\(viewModel.currentFullImageIndex + 1) / \(assets.count)")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 40)
            }
        }
    }

    private func fullImagePage(for asset: SafeNoteAsset) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = viewModel.decryptedFullImages[asset.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
    }
}


// MARK: - Previews

/// Mock 仓库：在 Preview 中提供静态 SafeNote 数据，避免访问真实 Core Data
private final class MockSafeNoteRepository: SafeNoteRepositoryProtocol {
    let note: SafeNote

    init(note: SafeNote) {
        self.note = note
    }

    func fetchAll() async throws -> [SafeNote] { [note] }
    func fetchAllFull() async throws -> [SafeNote] { [note] }
    func fetch(by id: UUID) async throws -> SafeNote? { note.id == id ? note : nil }
    func search(title query: String) async throws -> [SafeNote] { [note] }
    func save(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {}
    func update(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {}
    func delete(_ id: UUID) async throws {}
    func softDelete(_ id: UUID) async throws {}
    func fetchTrashed() async throws -> [SafeNote] { [] }
    func purgeExpired(retentionDays: Int) async throws -> [UUID] { [] }
}

/// Mock 加密文件存储：Preview 中生成纯色占位图，避免真实加解密
private final class MockEncryptedFileStorage: EncryptedFileStorageProtocol {
    func saveImage(data: Data, noteID: UUID, assetID: UUID) throws -> String { "mock/\(assetID).enc" }
    func saveThumbnail(data: Data, noteID: UUID, assetID: UUID) throws -> String { "mock/\(assetID)_thumb.enc" }
    func loadDecryptedData(at relativePath: String) throws -> Data {
        // 生成 100x100 的纯色 JPEG 作为占位图
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
    func deleteFile(at relativePath: String) throws {}
    func deleteFiles(for noteID: UUID) throws {}
    func optimizedImageData(from data: Data, maxDimension: CGFloat) -> Data? { data }
    func thumbnailData(from data: Data, maxDimension: CGFloat) -> Data? { data }
    func imageSize(from data: Data) -> CGSize? { CGSize(width: 100, height: 100) }
}

/// 构造测试用 SafeNote
private func makePreviewNote() -> SafeNote {
    let noteID = UUID()
    let assets = (0..<6).map { index in
        SafeNoteAsset(
            noteID: noteID,
            sortOrder: index,
            mimeType: "image/jpeg",
            pixelWidth: 1080,
            pixelHeight: 1920,
            byteSize: 1024,
            encryptedFilePath: "mock/asset\(index).enc",
            encryptedThumbnailPath: "mock/asset\(index)_thumb.enc"
        )
    }
    return SafeNote(
        id: noteID,
        title: "旅行备忘",
        content: "记得带上护照、充电宝和转换插头。\n航班：CA1234  09:30 起飞\n酒店：Grand Hotel，已确认预订。",
        assets: assets,
        coverAssetID: assets.first?.id,
        isFavorite: true,
        createdAt: Date().addingTimeInterval(-86400 * 3),
        updatedAt: Date().addingTimeInterval(-3600)
    )
}

#Preview("有图笔记") {
    let note = makePreviewNote()
    let service = SafeNoteVaultService(repository: MockSafeNoteRepository(note: note))
    return NavigationStack {
        SafeNoteDetailView(noteID: note.id, service: service)
    }
}

#Preview("空笔记") {
    let note = SafeNote(
        title: "空白笔记",
        content: "",
        assets: []
    )
    let service = SafeNoteVaultService(repository: MockSafeNoteRepository(note: note))
    return NavigationStack {
        SafeNoteDetailView(noteID: note.id, service: service)
    }
}
