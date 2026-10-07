/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
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

    /// 当前页是否处于放大状态；放大时禁用外层分页滑动，让单指拖动用于平移图片
    @State private var isZoomed: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $viewModel.currentFullImageIndex) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    fullImagePage(for: asset, at: index)
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
        .onChange(of: viewModel.currentFullImageIndex) { _, _ in
            // 翻页后清除缩放状态，保证新页面从原始比例开始展示
            isZoomed = false
        }
    }

    /// 单页大图：支持捏合缩放与双击放大/还原。
    /// 放大时通过 PagingScrollViewBridge 关闭外层分页滑动，避免单指拖动平移与翻页抢手势。
    private func fullImagePage(for asset: SafeNoteAsset, at index: Int) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = viewModel.decryptedFullImages[asset.id] {
                ZoomableImageView(
                    image: image,
                    isActive: index == viewModel.currentFullImageIndex,
                    onZoomChanged: { isZoomed = $0 }
                )
            } else {
                ProgressView()
            }
        }
        .background(PagingScrollViewBridge(isPagingEnabled: !isZoomed))
    }
}


/// 可缩放大图：基于 UIScrollView 实现捏合缩放与拖动平移，双击在原始比例与放大比例之间切换。
private struct ZoomableImageView: UIViewRepresentable {
    /// 原始比例下双击放大的目标倍数（受 maximumZoomScale 约束）
    private static let doubleTapZoomScale: CGFloat = 2.5
    private static let maximumZoomScale: CGFloat = 5

    let image: UIImage
    /// 是否为当前展示页；离开当前页时重置缩放
    let isActive: Bool
    /// 缩放状态变化回调，供外层控制分页滚动
    let onZoomChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
        scrollView.maximumZoomScale = Self.maximumZoomScale
        scrollView.imageView.image = image
        scrollView.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        context.coordinator.onZoomChanged = onZoomChanged
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.setNeedsLayout()
        }
        context.coordinator.setActive(isActive, in: scrollView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: isActive, onZoomChanged: onZoomChanged)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private var isActive: Bool
        var onZoomChanged: (Bool) -> Void

        init(isActive: Bool, onZoomChanged: @escaping (Bool) -> Void) {
            self.isActive = isActive
            self.onZoomChanged = onZoomChanged
        }

        /// 更新当前页状态；离开当前页时异步重置缩放，避免在视图更新期间写入状态
        func setActive(_ active: Bool, in scrollView: ZoomingScrollView) {
            guard active != isActive else { return }
            isActive = active
            guard !active else { return }
            DispatchQueue.main.async { [weak scrollView] in
                scrollView?.resetZoom()
            }
        }

        /// 指定参与缩放的子视图。
        /// UIScrollView 的缩放完全依赖该回调，缺少实现时捏合与 zoom(to:) 都不会生效。
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomingScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let zoomingScrollView = scrollView as? ZoomingScrollView else { return }
            zoomingScrollView.centerContent()
            // 仅当前页上报，避免离屏页面覆盖缩放状态
            guard isActive else { return }
            onZoomChanged(zoomingScrollView.zoomScale > zoomingScrollView.minimumZoomScale + 0.01)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? ZoomingScrollView else { return }

            // 已放大则还原
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            // 以双击位置为中心放大
            let targetScale = min(scrollView.maximumZoomScale, ZoomableImageView.doubleTapZoomScale)
            let location = gesture.location(in: scrollView.imageView)
            let size = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            let rect = CGRect(
                x: location.x - size.width / 2,
                y: location.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }
}

/// 可缩放的图片容器：图片按 aspect-fit 尺寸放入 content，缩放上限内允许自由平移。
private final class ZoomingScrollView: UIScrollView {
    let imageView = UIImageView()
    private var lastLayoutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let imageSize = imageView.image?.size,
              imageSize.width > 0,
              imageSize.height > 0 else { return }

        // 尺寸变化（首次布局 / 旋转）时重算内容尺寸并重置缩放
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            resetContentLayout(for: imageSize)
        }
        centerContent()
    }

    /// 还原到原始比例
    func resetZoom() {
        setZoomScale(minimumZoomScale, animated: false)
        centerContent()
    }

    /// contentSize 小于可视区域时，通过对称 contentInset 让内容保持居中
    func centerContent() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        let insets = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
        guard contentInset != insets else { return }
        contentInset = insets
    }

    private func resetContentLayout(for imageSize: CGSize) {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        contentSize = fittedSize
        zoomScale = minimumZoomScale
        contentOffset = .zero
    }
}

/// 分页滚动控制桥接：向上查找所在的分页 UIScrollView，
/// 在图片放大时关闭分页滑动，避免单指拖动平移与翻页手势冲突。
private struct PagingScrollViewBridge: UIViewRepresentable {
    let isPagingEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let enabled = isPagingEnabled
        DispatchQueue.main.async {
            Self.enclosingScrollView(of: uiView)?.isScrollEnabled = enabled
        }
    }

    /// 向上遍历视图层级，返回承载分页逻辑的最近一层 UIScrollView
    private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var current: UIView? = view.superview
        while let ancestor = current {
            if let scrollView = ancestor as? UIScrollView {
                return scrollView
            }
            current = ancestor.superview
        }
        return nil
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
