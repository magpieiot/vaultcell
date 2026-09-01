/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// EditSafeNoteView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import PhotosUI

/// 安全笔记编辑页
/// 支持输入标题、正文，并从相册选择图片。保存后写入加密数据库和文件系统。
struct EditSafeNoteView: View {
    @StateObject private var viewModel: SafeNoteEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isShowingImagePicker: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var savedNote: SafeNote?

    private let maxImageCount: Int = 4
    private let maxTitleLength: Int = 40
    private let maxContentLength: Int = 5000

    init(viewModel: SafeNoteEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: titleBinding)
                } header: {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Title")
                            Text("*")
                                .foregroundColor(.red)
                        }

                        Spacer()

                        Text("\(viewModel.draft.title.count)/\(maxTitleLength)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    picturesGrid
                        .padding(.horizontal, 16)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                } header: {
                    HStack {
                        Text("Pictures")
                        Spacer()
                        Text("\(viewModel.draft.assets.count)/\(maxImageCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    TextEditor(text: contentBinding)
                        .frame(minHeight: 200, maxHeight: .infinity)
                } header: {
                    HStack {
                        Text("Content")
                        Spacer()
                        Text("\(viewModel.draft.content.count)/\(maxContentLength)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
                    .listRowBackground(Color.clear)

                if viewModel.editingNote != nil {
                    Section {
                        Button(
                            action: {
                                //
                                showDeleteAlert = true
                            }
                        ) {
                            Label("Delete", systemImage: "trash")
                                .font(.body.weight(.medium))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                
                

            }
            .navigationTitle(viewModel.editingNote == nil ? "Create" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            if let note = await viewModel.save() {
                                savedNote = note
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isTitleValid || viewModel.isSaving)
                }
            }
            .photosPicker(
                isPresented: $isShowingImagePicker,
                selection: $selectedPhotos,
                maxSelectionCount: max(0, maxImageCount - viewModel.draft.assets.count),
                matching: .images
            )
            .onChange(of: selectedPhotos) { _, newSelections in
                let remaining = maxImageCount - viewModel.draft.assets.count
                let toAdd = Array(newSelections.prefix(remaining))
                guard !toAdd.isEmpty else {
                    selectedPhotos.removeAll()
                    return
                }
                Task {
                    await viewModel.addImages(from: toAdd)
                    selectedPhotos.removeAll()
                }
            }
            .alert(
                "Are you sure to DELETE?", 
                isPresented: $showDeleteAlert
            ) {
                Button("Delete", role: .destructive) { 
                    performDelete() 
                }
                Button("Cancel", role: .cancel) { 
                    //
                }
            } message: { 
                Text("Deleted items are kept for 30 days, then permanently deleted.")
                    .foregroundColor(.red)
            }
            .alert("Alert", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func performDelete() {
        Task {
            let success = await viewModel.delete()
            if success {
                dismiss()
            }
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { viewModel.draft.title },
            set: {
                let trimmed = String($0.prefix(maxTitleLength))
                viewModel.updateTitle(trimmed)
            }
        )
    }

    /// 标题是否有效（非空且不只包含空白字符）
    private var isTitleValid: Bool {
        !viewModel.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { viewModel.draft.content },
            set: {
                let trimmed = String($0.prefix(maxContentLength))
                viewModel.updateContent(trimmed)
            }
        )
    }

    /// 图片网格区域
    @ViewBuilder
    private var picturesGrid: some View {
        if viewModel.draft.assets.isEmpty {
            addPictureButton(iconSize: 24)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(viewModel.draft.assets) { asset in
                    draftAssetThumbnail(asset)
                }
                if viewModel.draft.assets.count < maxImageCount {
                    addPictureButton(iconSize: 24)
                }
            }
        }
    }

    /// 添加图片按钮（尺寸固定为 80x80，与 draftAssetThumbnail 一致）
    private func addPictureButton(iconSize: CGFloat) -> some View {
        Button(action: { isShowingImagePicker = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .frame(width: 80, height: 80)

                Image(systemName: "photo.badge.plus")
                    .font(.system(size: iconSize))
                    .foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private func draftAssetThumbnail(_ asset: SafeNoteDraftAsset) -> some View {
        DraftAssetThumbnailView(
            asset: asset,
            onDelete: { viewModel.removeAsset(asset.id) }
        )
    }
}

// MARK: - Draft Asset Thumbnail

/// 草稿图片缩略图单元
///
/// 拆分为独立 View 是为了保证 SwiftUI 视图身份稳定：
/// ForEach 中直接使用 @ViewBuilder 辅助函数包裹 Button 时，
/// 闭包捕获的参数在视图复用阶段可能绑定到错误的数据，导致删除按钮影响非目标 asset。
/// 独立 View 配合显式 id 可消除该隐患。
private struct DraftAssetThumbnailView: View {
    let asset: SafeNoteDraftAsset
    let onDelete: () -> Void

    /// 从磁盘解密加载后的缩略图数据（用于已存在的加密图片）
    @State private var decryptedThumbnailData: Data?
    private let fileStorage: EncryptedFileStorageProtocol

    init(
        asset: SafeNoteDraftAsset,
        onDelete: @escaping () -> Void,
        fileStorage: EncryptedFileStorageProtocol = EncryptedFileStorage()
    ) {
        self.asset = asset
        self.onDelete = onDelete
        self.fileStorage = fileStorage
    }

    /// 优先显示顺序：
    /// 1. 新选择图片的完整 imageData
    /// 2. 已生成的缩略图数据
    /// 3. 从磁盘解密加载的缩略图数据（用于编辑已有 Note 时）
    private var displayImageData: Data? {
        asset.imageData ?? asset.thumbnailData ?? decryptedThumbnailData
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let displayImageData, let uiImage = UIImage(data: displayImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .background(Color.white.clipShape(Circle()))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .offset(x: -8, y: 8)
        }
        .id(asset.id)
        .task {
            await loadExistingThumbnail()
        }
    }

    /// 对于编辑已有 Note 的场景，existingAsset 有加密缩略图路径，
    /// 但 draft 创建时未加载图片数据，因此需要在此异步解密加载。
    private func loadExistingThumbnail() async {
        // 已经有可显示数据时无需加载
        guard asset.imageData == nil, asset.thumbnailData == nil else { return }
        // 仅对已持久化资产尝试解密缩略图
        guard let thumbnailPath = asset.existingAsset?.encryptedThumbnailPath else { return }

        do {
            decryptedThumbnailData = try fileStorage.loadDecryptedData(at: thumbnailPath)
        } catch {
            // 缩略图加载失败时保持占位图，不阻断编辑流程
        }
    }
}

// MARK: - Previews

/// 用于 Preview 的 Mock 仓库，不访问真实 Core Data
private final class MockSafeNoteEditorRepository: SafeNoteRepositoryProtocol {
    func fetchAll() async throws -> [SafeNote] { [] }
    func fetchAllFull() async throws -> [SafeNote] { [] }
    func fetch(by id: UUID) async throws -> SafeNote? { nil }
    func search(title query: String) async throws -> [SafeNote] { [] }
    func save(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {}
    func update(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {}
    func delete(_ id: UUID) async throws {}
    func softDelete(_ id: UUID) async throws {}
    func fetchTrashed() async throws -> [SafeNote] { [] }
    func purgeExpired(retentionDays: Int) async throws -> [UUID] { [] }
}

/// 生成纯色 JPEG 占位图数据
private func makePlaceholderImageData(color: UIColor) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80))
    let image = renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
    }
    return image.jpegData(compressionQuality: 0.8) ?? Data()
}

/// 生成带图片草稿的 SafeNoteEditorViewModel（新建模式）
@MainActor
private func makeNewNoteViewModel() -> SafeNoteEditorViewModel {
    let service = SafeNoteVaultService(repository: MockSafeNoteEditorRepository())
    let vm = SafeNoteEditorViewModel(service: service)
    // 预填两张占位图片草稿
    vm.draft.assets = [
        SafeNoteDraftAsset(
            imageData: makePlaceholderImageData(color: .systemTeal),
            sortOrder: 0
        ),
        SafeNoteDraftAsset(
            imageData: makePlaceholderImageData(color: .systemPink),
            sortOrder: 1
        )
    ]
    vm.draft.coverAssetID = vm.draft.assets.first?.id
    return vm
}

/// 生成编辑已有 Note 的 SafeNoteEditorViewModel
@MainActor
private func makeEditNoteViewModel() -> SafeNoteEditorViewModel {
    let service = SafeNoteVaultService(repository: MockSafeNoteEditorRepository())
    let note = SafeNote(
        title: "旅行备忘",
        content: "记得带上护照、充电宝和转换插头。\n航班：CA1234 09:30 起飞",
        isFavorite: true,
        createdAt: Date().addingTimeInterval(-86400 * 3),
        updatedAt: Date().addingTimeInterval(-3600)
    )
    return SafeNoteEditorViewModel(service: service, editingNote: note)
}

#Preview("新建笔记") {
    EditSafeNoteView(viewModel: makeNewNoteViewModel())
}

#Preview("编辑已有笔记") {
    EditSafeNoteView(viewModel: makeEditNoteViewModel())
}
