import SwiftUI
import UIKit

struct SafeNotesListView: View {
    @StateObject private var viewModel: SafeNotesListViewModel
    @State private var isPresentingEditor: Bool = false

    /// 默认初始化：创建新的 ViewModel 并自动加载真实数据
    init() {
        _viewModel = StateObject(wrappedValue: SafeNotesListViewModel())
    }

    /// 注入 ViewModel，主要用于 Preview 和单元测试
    init(viewModel: SafeNotesListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// 注入共享的 SafeNoteVaultService，用于与外部编辑器共享同一数据源
    init(service: SafeNoteVaultService) {
        _viewModel = StateObject(wrappedValue: SafeNotesListViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notes.isEmpty {
                    ProgressView("Loading Notes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.notes.isEmpty {
                    ContentUnavailableView(
                        "No Safe Notes",
                        systemImage: "note.text.badge.plus",
                        description: Text("Your encrypted notes will appear here.")
                    )
                } else {
                    List {
                        ForEach(sortedNotes) { note in
                            noteRow(for: note)
                        }
                    }
                    .listRowSpacing(0)
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Safe Note")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadNotes()
            }
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task {
                    await viewModel.searchNotes()
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                EditSafeNoteView(
                    viewModel: SafeNoteEditorViewModel(
                        service: viewModel.service
                    )
                )
            }
            .onChange(of: isPresentingEditor) { _, isPresented in
                // 编辑页关闭后（回到列表）刷新数据
                if !isPresented {
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        //
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                    }
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
    }

    /// 排序后的笔记列表：收藏的排在前面，其次按更新时间降序
    private var sortedNotes: [SafeNote] {
        viewModel.notes.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    @ViewBuilder
    private func noteRow(for note: SafeNote) -> some View {
        ZStack {
            SafeNoteRow(
                note: note,
                toggleFavorite: {
                    Task {
                        await viewModel.toggleFavorite(note.id)
                    }
                }
            )

            // 使用透明 NavigationLink 覆盖整行，避免 List 自动显示右侧披露箭头 `>`
            NavigationLink(
                destination: SafeNoteDetailView(
                    noteID: note.id,
                    service: viewModel.service
                )
            ) {
                Color.clear
            }
            .opacity(0)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task {
                    await viewModel.toggleFavorite(note.id)
                }
            } label: {
                Label(
                    note.isFavorite ? "Remove Favorite" : "Add Favorite",
                    systemImage: note.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(note.isFavorite ? .secondary : .yellow)
        }
    }
}

// MARK: - Previews

/// 用于 Preview 的 Mock 仓库，返回静态 SafeNote 列表，不访问真实 Core Data
private final class MockSafeNoteListRepository: SafeNoteRepositoryProtocol {
    let notes: [SafeNote]

    init(notes: [SafeNote]) {
        self.notes = notes
    }

    func fetchAll() async throws -> [SafeNote] { notes }
    func fetchAllFull() async throws -> [SafeNote] { notes }
    func fetch(by id: UUID) async throws -> SafeNote? { notes.first { $0.id == id } }
    func search(title query: String) async throws -> [SafeNote] {
        notes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    func save(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {}
    func update(_ note: SafeNote, draftAssets: [SafeNoteDraftAsset]) async throws {}
    func delete(_ id: UUID) async throws {}
    func softDelete(_ id: UUID) async throws {}
    func fetchTrashed() async throws -> [SafeNote] { [] }
    func purgeExpired(retentionDays: Int) async throws -> [UUID] { [] }
}

/// 构造测试用 SafeNote 数组
private func makePreviewNotes() -> [SafeNote] {
    [
        SafeNote(
            title: "旅行备忘",
            content: "记得带上护照、充电宝和转换插头。",
            assets: [],
            coverAssetID: nil,
            isFavorite: true,
            createdAt: Date().addingTimeInterval(-86400 * 5),
            updatedAt: Date().addingTimeInterval(-3600 * 2)
        ),
        SafeNote(
            title: "Project Ideas",
            content: "1. AI coding assistant\n2. Personal finance tracker\n3. Encrypted journal",
            assets: [],
            coverAssetID: nil,
            isFavorite: false,
            createdAt: Date().addingTimeInterval(-86400 * 2),
            updatedAt: Date().addingTimeInterval(-3600 * 5)
        ),
        SafeNote(
            title: "家庭保险单",
            content: "保单编号：2026-XXXX-1234\n到期日：2027-03-15",
            assets: [],
            coverAssetID: nil,
            isFavorite: false,
            createdAt: Date().addingTimeInterval(-86400 * 10),
            updatedAt: Date().addingTimeInterval(-86400)
        ),
        SafeNote(
            title: "会议记录",
            content: "Q3 规划讨论：\n- 安全审计\n- iOS 18 适配\n- 性能优化",
            assets: [],
            coverAssetID: nil,
            isFavorite: true,
            createdAt: Date().addingTimeInterval(-86400 * 1),
            updatedAt: Date().addingTimeInterval(-1800)
        )
    ]
}

#Preview("Safe Notes 列表") {
    let service = SafeNoteVaultService(
        repository: MockSafeNoteListRepository(notes: makePreviewNotes())
    )
    SafeNotesListView(viewModel: SafeNotesListViewModel(service: service))
}

#Preview("空列表") {
    let service = SafeNoteVaultService(
        repository: MockSafeNoteListRepository(notes: [])
    )
    SafeNotesListView(viewModel: SafeNotesListViewModel(service: service))
}

private struct SafeNoteRow: View {
    let note: SafeNote
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SafeNoteThumbnailView(relativePath: note.coverAsset?.encryptedThumbnailPath)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    /*
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }
                    */
                }

                HStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("\(note.imageCount)")
                        .padding(.horizontal, 4)
                    Image(systemName: "clock")
                        .padding(.horizontal, 4)
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        //.padding(.horizontal, 8)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            if note.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
        }
        //.padding(.vertical, 6)
    }
}

private struct SafeNoteThumbnailView: View {
    let relativePath: String?

    @State private var image: UIImage?
    private let fileStorage = EncryptedFileStorage()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "note.text")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: relativePath) {
            guard let relativePath else {
                image = nil
                return
            }

            do {
                let data = try fileStorage.loadDecryptedData(at: relativePath)
                image = UIImage(data: data)
            } catch {
                image = nil
            }
        }
    }
}
