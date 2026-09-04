/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CategoryRepository.swift
/// created on: 21/06/2026
/// ------------------------------------------------------------------

import Foundation
@preconcurrency import CoreData

protocol CategoryRepositoryProtocol {
    func fetchAll() async throws -> [PasswordCategory]
    func fetch(by id: UUID) async throws -> PasswordCategory?
    func create(_ category: PasswordCategory) async throws
    func update(_ category: PasswordCategory) async throws
    func delete(_ id: UUID) async throws
    func ensureDefaults() async throws
}

class CategoryRepository: CategoryRepositoryProtocol {
    private let dataSource: CoreDataDataSource

    init(dataSource: CoreDataDataSource = CoreDataDataSource(context: CoreDataStack.shared.viewContext)) {
        self.dataSource = dataSource
    }

    func fetchAll() async throws -> [PasswordCategory] {
        let dataSource = self.dataSource
        return try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    let cdCategories = try dataSource.fetchAllCategories()
                    let categories = cdCategories.map { dataSource.convertToPasswordCategory($0) }
                    continuation.resume(returning: categories)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetch(by id: UUID) async throws -> PasswordCategory? {
        let dataSource = self.dataSource
        return try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    if let cdCategory = try dataSource.fetchCategory(by: id) {
                        continuation.resume(returning: dataSource.convertToPasswordCategory(cdCategory))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func create(_ category: PasswordCategory) async throws {
        let dataSource = self.dataSource
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    try dataSource.createCategory(from: category)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func update(_ category: PasswordCategory) async throws {
        let dataSource = self.dataSource
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    if let cdCategory = try dataSource.fetchCategory(by: category.id) {
                        try dataSource.updateCategory(cdCategory, from: category)
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "CategoryRepository", code: 404))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func delete(_ id: UUID) async throws {
        let dataSource = self.dataSource
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    try dataSource.deleteCategory(id)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func ensureDefaults() async throws {
        let dataSource = self.dataSource
        try await withCheckedThrowingContinuation { continuation in
            dataSource.context.perform {
                do {
                    try dataSource.ensureDefaultCategories()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
