import CoreData
import Foundation
import Testing

@Suite("共享 Core Data 双写入方 PoC")
struct SharedStoreTests {
    @Test("两个容器写入同一数据库且持久化历史保留作者")
    func independentWritersShareStoreAndHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultCellSharedStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("VaultCell.sqlite")
        let model = Self.makeModel()
        let host = NSPersistentContainer(name: "Host", managedObjectModel: model)
        let autoFill = NSPersistentContainer(name: "AutoFill", managedObjectModel: model)

        do {
            try Self.load(host, storeURL: storeURL)
            try Self.load(autoFill, storeURL: storeURL)
            let itemID = UUID()

            let hostContext = host.newBackgroundContext()
            hostContext.transactionAuthor = VaultCoreDataStoreConfiguration.hostAuthor
            try hostContext.performAndWait {
                let item = NSManagedObject(entity: model.entities[0], insertInto: hostContext)
                item.setValue(itemID, forKey: "id")
                item.setValue("host", forKey: "value")
                item.setValue(VaultSyncRevision.initial, forKey: "version")
                try hostContext.save()
            }

            let autoFillContext = autoFill.newBackgroundContext()
            autoFillContext.transactionAuthor = VaultCoreDataStoreConfiguration.autoFillAuthor
            try autoFillContext.performAndWait {
                let request = NSFetchRequest<NSManagedObject>(entityName: "SyncProbe")
                request.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
                let item = try #require(autoFillContext.fetch(request).first)
                item.setValue("autofill", forKey: "value")
                let current = item.value(forKey: "version") as? Int64 ?? 0
                item.setValue(VaultSyncRevision.next(current: current, proposed: current), forKey: "version")
                try autoFillContext.save()
            }

            try hostContext.performAndWait {
                hostContext.refreshAllObjects()
                let request = NSFetchRequest<NSManagedObject>(entityName: "SyncProbe")
                let item = try #require(hostContext.fetch(request).first)
                #expect(item.value(forKey: "value") as? String == "autofill")
                #expect(item.value(forKey: "version") as? Int64 == 2)
            }

            try hostContext.performAndWait {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(
                    after: Optional<NSPersistentHistoryToken>.none
                )
                let result = try #require(hostContext.execute(request) as? NSPersistentHistoryResult)
                let transactions = try #require(result.result as? [NSPersistentHistoryTransaction])
                let authors = Set(transactions.compactMap(\.author))
                #expect(authors.contains(VaultCoreDataStoreConfiguration.hostAuthor))
                #expect(authors.contains(VaultCoreDataStoreConfiguration.autoFillAuthor))
            }
        } catch {
            Self.removeStores(from: [host, autoFill])
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        Self.removeStores(from: [host, autoFill])
        try FileManager.default.removeItem(at: directory)
    }

    private static func makeModel() -> NSManagedObjectModel {
        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        let value = NSAttributeDescription()
        value.name = "value"
        value.attributeType = .stringAttributeType
        let version = NSAttributeDescription()
        version.name = "version"
        version.attributeType = .integer64AttributeType

        let entity = NSEntityDescription()
        entity.name = "SyncProbe"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [id, value, version]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private static func load(
        _ container: NSPersistentContainer,
        storeURL: URL
    ) throws {
        let description = NSPersistentStoreDescription(url: storeURL)
        VaultCoreDataStoreConfiguration.configure(description)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    private static func removeStores(from containers: [NSPersistentContainer]) {
        for container in containers {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
    }
}
