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

    /// 是否存在名称为空（或仅空白字符）的字段
    var hasUntitledField: Bool {
        customFields.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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