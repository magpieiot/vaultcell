import Foundation
import Combine

@MainActor
final class CustomFieldModel: ObservableObject {
    @Published var customFields: [CustomField]

    init(customFields: [CustomField] = []) {
        self.customFields = customFields
    }

    var isEmpty: Bool {
        customFields.isEmpty
    }

    @discardableResult
    func addField(
        name: String = "",
        value: String = "",
        isSensitive: Bool = false
    ) -> CustomField {
        let field = CustomField(
            name: name,
            value: value,
            isSensitive: isSensitive
        )
        customFields.append(field)
        return field
    }

    func deleteField(id: UUID) {
        customFields.removeAll { $0.id == id }
    }

    func deleteFields(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard customFields.indices.contains(index) else { continue }
            customFields.remove(at: index)
        }
    }

    func replaceAll(with customFields: [CustomField]) {
        self.customFields = customFields
    }

    func clear() {
        customFields.removeAll()
    }
}