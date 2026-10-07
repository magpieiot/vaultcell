import CoreData
import Foundation

protocol PincodeRepositoryProtocol {
    func fetchAll() async throws -> [PincodeEntry]
    func fetch(by id: UUID) async throws -> PincodeEntry?
    func search(query: String) async throws -> [PincodeEntry]
    func save(_ entry: PincodeEntry) async throws
    func update(_ entry: PincodeEntry) async throws
    func delete(_ id: UUID) async throws
    func softDelete(_ id: UUID) async throws
    func fetchTrashed() async throws -> [PincodeEntry]
    func purgeExpired(retentionDays: Int) async throws -> [UUID]
}

class PincodeRepository: PincodeRepositoryProtocol {
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
    
    func fetchAll() async throws -> [PincodeEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllPincodes()
            var entries: [PincodeEntry] = []
            entries.reserveCapacity(cdEntries.count)

            var firstError: Error?
            for cdEntry in cdEntries {
                guard cdEntry.deletedAt == nil else { continue }
                do {
                    entries.append(try self.dataSource.convertToPincodeEntry(cdEntry))
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
    
    func fetch(by id: UUID) async throws -> PincodeEntry? {
        try await perform {
            if let cdEntry = try self.dataSource.fetchPincode(by: id) {
                return try self.dataSource.convertToPincodeEntry(cdEntry)
            }
            return nil
        }
    }
    
    func search(query: String) async throws -> [PincodeEntry] {
        try await perform {
            let cdEntries = try self.dataSource.searchPincodes(query: query)
            var entries: [PincodeEntry] = []
            entries.reserveCapacity(cdEntries.count)
            
            var firstError: Error?
            for cdEntry in cdEntries {
                do {
                    entries.append(try self.dataSource.convertToPincodeEntry(cdEntry))
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
    
    func save(_ entry: PincodeEntry) async throws {
        try await perform {
            try self.dataSource.savePincodeEntry(entry)
        }
    }
    
    func update(_ entry: PincodeEntry) async throws {
        try await perform {
            try self.dataSource.savePincodeEntry(entry)
        }
    }
    
    func delete(_ id: UUID) async throws {
        try await perform {
            try self.dataSource.deletePincodeEntry(id)
        }
    }

    func softDelete(_ id: UUID) async throws {
        try await perform {
            guard let cdEntry = try self.dataSource.fetchPincode(by: id) else { return }
            cdEntry.deletedAt = Date()
            try self.dataSource.saveIfPossible()
        }
    }

    func fetchTrashed() async throws -> [PincodeEntry] {
        try await perform {
            let cdEntries = try self.dataSource.fetchAllPincodes()
            var entries: [PincodeEntry] = []
            var firstError: Error?
            for cdEntry in cdEntries {
                guard cdEntry.deletedAt != nil else { continue }
                do {
                    entries.append(try self.dataSource.convertToPincodeEntry(cdEntry))
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
            let cdEntries = try self.dataSource.fetchAllPincodes()
            var purgedIDs: [UUID] = []
            for cdEntry in cdEntries {
                if let deletedAt = cdEntry.deletedAt, deletedAt < cutoff {
                    let id = cdEntry.id
                    self.dataSource.context.delete(cdEntry)
                    purgedIDs.append(id)
                }
            }
            if !purgedIDs.isEmpty {
                try self.dataSource.saveIfPossible()
            }
            return purgedIDs
        }
    }
}

