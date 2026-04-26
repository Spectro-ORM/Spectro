import Foundation

/// Mirror-based primary key extraction shared by `GenericDatabaseRepo` and `TransactionRepo`.
///
/// Handles both property-wrapper fields (`@ID`) and plain stored properties.
func extractPrimaryKey<T: Schema>(from instance: T, fieldName: String) -> (any PrimaryKeyType)? {
    let mirror = Mirror(reflecting: instance)
    for child in mirror.children {
        guard let label = child.label else { continue }
        let name = label.hasPrefix("_") ? String(label.dropFirst()) : label
        guard name == fieldName else { continue }

        let wrapperMirror = Mirror(reflecting: child.value)
        for wrapperChild in wrapperMirror.children {
            if wrapperChild.label == "wrappedValue" {
                return wrapperChild.value as? (any PrimaryKeyType)
            }
        }
        return child.value as? (any PrimaryKeyType)
    }
    return nil
}
