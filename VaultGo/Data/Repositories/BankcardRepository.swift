import CoreData
import Foundation

protocol BankcardRepositoryProtocol {
    func fetchAll() async throws -> [BankcardEntry]
    func fetch(by id: UUID) async throws -> BankcardEntry?
    func search(query: String) async throws -> [BankcardEntry]
    func save(_ entry: BankcardEntry) async throws
    func update(_ entry: BankcardEntry) async throws
    func delete(_ id: UUID) async throws
    func softDelete(_ id: UUID) async throws
    func fetchTrashed() async throws -> [BankcardEntry]
    func purgeExpired(retentionDays: Int) async throws -> [UUID]
}

class BankcardRepository: BankcardRepositoryProtocol {
    private let dataSource: CoreDataDataSource
    
    init(dataSource: CoreDataDataSource = CoreDataDataSource(context: CoreDataStack.shared.newBackgroundContext())) {
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
    
    func fetchAll() async throws -> [BankcardEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllBankcards()
            var entries: [BankcardEntry] = []
            entries.reserveCapacity(cdEntries.count)

            var firstError: Error?
            for cdEntry in cdEntries {
                guard cdEntry.deletedAt == nil else { continue }
                do {
                    entries.append(try self.dataSource.convertToBankcardEntry(cdEntry))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if entries.isEmpty, let firstError {
                throw firstError
            }
            return entries
        }
    }
    
    func fetch(by id: UUID) async throws -> BankcardEntry? {
        try await perform {
            if let cdEntry = try self.dataSource.fetchBankcard(by: id) {
                return try self.dataSource.convertToBankcardEntry(cdEntry)
            }
            return nil
        }
    }
    
    func search(query: String) async throws -> [BankcardEntry] {
        try await perform {
            let cdEntries = try self.dataSource.searchBankcards(query: query)
            var entries: [BankcardEntry] = []
            entries.reserveCapacity(cdEntries.count)
            
            var firstError: Error?
            for cdEntry in cdEntries {
                do {
                    entries.append(try self.dataSource.convertToBankcardEntry(cdEntry))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            
            if entries.isEmpty, let firstError {
                throw firstError
            }
            return entries
        }
    }
    
    func save(_ entry: BankcardEntry) async throws {
        try await perform {
            try self.dataSource.saveBankcardEntry(entry)
        }
    }
    
    func update(_ entry: BankcardEntry) async throws {
        try await perform {
            try self.dataSource.saveBankcardEntry(entry)
        }
    }
    
    func delete(_ id: UUID) async throws {
        try await perform {
            try self.dataSource.deleteBankcardEntry(id)
        }
    }

    func softDelete(_ id: UUID) async throws {
        try await perform {
            guard let cdEntry = try self.dataSource.fetchBankcard(by: id) else { return }
            cdEntry.deletedAt = Date()
            try self.dataSource.context.save()
        }
    }

    func fetchTrashed() async throws -> [BankcardEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllBankcards()
            var entries: [BankcardEntry] = []
            var firstError: Error?
            for cdEntry in cdEntries {
                guard cdEntry.deletedAt != nil else { continue }
                do {
                    entries.append(try self.dataSource.convertToBankcardEntry(cdEntry))
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if entries.isEmpty, let firstError { throw firstError }
            return entries
        }
    }

    func purgeExpired(retentionDays: Int) async throws -> [UUID] {
        try await perform {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
            let cdEntries = try self.dataSource.fetchAllBankcards()
            var purgedIDs: [UUID] = []
            for cdEntry in cdEntries {
                if let deletedAt = cdEntry.deletedAt, deletedAt < cutoff {
                    let id = cdEntry.id
                    self.dataSource.context.delete(cdEntry)
                    purgedIDs.append(id)
                }
            }
            if !purgedIDs.isEmpty {
                try self.dataSource.context.save()
            }
            return purgedIDs
        }
    }
}

