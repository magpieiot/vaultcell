/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// SafeNotesListViewModel.swift
/// created on: 31/07/2026
/// ------------------------------------------------------------------

import Foundation
import Combine

@MainActor
final class SafeNotesListViewModel: ObservableObject {
    @Published var notes: [SafeNote] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let service: SafeNoteVaultService
    private var cancellables = Set<AnyCancellable>()

    init(service: SafeNoteVaultService) {
        self.service = service
        // 订阅 service 的变化，外部刷新 service.notes 时自动同步到 ViewModel
        service.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncFromService()
                }
            }
            .store(in: &cancellables)
    }

    init() {
        self.service = SafeNoteVaultService()
        service.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncFromService()
                }
            }
            .store(in: &cancellables)
    }

    func loadNotes() async {
        await service.loadNotes()
        syncFromService()
    }

    func refresh() async {
        await loadNotes()
    }

    func searchNotes() async {
        await service.searchNotes(searchQuery)
        syncFromService()
    }

    func deleteNote(_ id: UUID) async {
        await service.deleteNote(id)
        syncFromService()
    }

    func toggleFavorite(_ id: UUID) async {
        await service.toggleFavorite(id)
        syncFromService()
    }

    private func syncFromService() {
        notes = service.notes
        isLoading = service.isLoading
        errorMessage = service.errorMessage
    }
}
