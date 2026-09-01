/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// TagRepository.swift
/// created on: 13/07/2026
/// ------------------------------------------------------------------

import Foundation
@preconcurrency import CoreData

protocol TagRepositoryProtocol {
    func fetchAll() async throws -> [Tag]
    func fetch(by id: UUID) async throws -> Tag?
    func fetchByName(_ name: String) async throws -> Tag?
    func create(_ tag: Tag) async throws
    func update(_ tag: Tag) async throws
    func delete(_ id: UUID) async throws
    func ensureDefaults() async throws
    /// 确保给定名称的标签存在（不存在则创建），返回对应的 Tag
    func ensureTagsExist(names: [String]) async throws -> [Tag]
}

class TagRepository: TagRepositoryProtocol {
    private let dataSource: CoreDataDataSource

    init(dataSource: CoreDataDataSource = CoreDataDataSource(context: CoreDataStack.shared.viewContext)) {
        self.dataSource = dataSource
    }

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchAll() async throws -> [Tag] {
        try await perform {
            let cdTags = try self.dataSource.fetchAllTags()
            return cdTags.map { self.dataSource.convertToTag($0) }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    func fetch(by id: UUID) async throws -> Tag? {
        try await perform {
            guard let cdTag = try self.dataSource.fetchTag(by: id) else { return nil }
            return self.dataSource.convertToTag(cdTag)
        }
    }

    func fetchByName(_ name: String) async throws -> Tag? {
        try await perform {
            guard let cdTag = try self.dataSource.fetchTagByName(name) else { return nil }
            return self.dataSource.convertToTag(cdTag)
        }
    }

    func create(_ tag: Tag) async throws {
        try await perform {
            try self.dataSource.createTag(from: tag)
        }
    }

    func update(_ tag: Tag) async throws {
        try await perform {
            guard let cdTag = try self.dataSource.fetchTag(by: tag.id) else {
                throw NSError(domain: "TagRepository", code: 404)
            }
            try self.dataSource.updateTag(cdTag, from: tag)
        }
    }

    func delete(_ id: UUID) async throws {
        try await perform {
            try self.dataSource.deleteTag(id)
        }
    }

    func ensureDefaults() async throws {
        try await perform {
            try self.dataSource.ensureDefaultTags()
        }
    }

    func ensureTagsExist(names: [String]) async throws -> [Tag] {
        try await perform {
            var result: [Tag] = []
            for name in names {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let cdTag = try self.dataSource.fetchTagByName(trimmed) {
                    result.append(self.dataSource.convertToTag(cdTag))
                } else {
                    let newTag = Tag(name: trimmed,
                                     hexColor: tagColor(for: trimmed),
                                     sortOrder: Int32(try self.dataSource.fetchAllTags().count))
                    try self.dataSource.createTag(from: newTag)
                    result.append(newTag)
                }
            }
            return result
        }
    }
}
