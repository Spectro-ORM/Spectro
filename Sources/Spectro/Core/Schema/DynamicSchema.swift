import Foundation

/// Base class for dynamic schemas with ActiveRecord-style attribute access.
///
/// Marked `@unchecked Sendable` because the mutable `attributes` dictionary
/// is not thread-safe on its own. Callers are responsible for ensuring that
/// instances are not accessed concurrently from multiple tasks.
@dynamicMemberLookup
open class DynamicSchema: Schema {
    private var attributes: [String: Any] = [:]
    private var propertyWrappers: [String: Any] = [:]

    open class var tableName: String {
        fatalError("Subclasses must override tableName")
    }

    public required init() {
        initializePropertyWrappers()
    }

    public subscript(dynamicMember member: String) -> Any? {
        get { attributes[member] }
        set {
            attributes[member] = newValue
            updatePropertyWrapper(member, value: newValue)
        }
    }

    internal func setAttribute(_ name: String, value: Any?) {
        attributes[name] = value
        updatePropertyWrapper(name, value: value)
    }

    internal func getAttribute(_ name: String) -> Any? { attributes[name] }
    internal func getAllAttributes() -> [String: Any] { attributes }

    private func initializePropertyWrappers() {
        for child in Mirror(reflecting: self).children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            propertyWrappers[fieldName] = child.value
            if let value = extractPropertyWrapperValue(child.value) {
                attributes[fieldName] = value
            }
        }
    }

    private func updatePropertyWrapper(_ name: String, value: Any?) {}

    private func extractPropertyWrapperValue(_ wrapper: Any) -> Any? {
        for child in Mirror(reflecting: wrapper).children {
            if child.label == "wrappedValue" { return child.value }
        }
        return wrapper
    }
}

// MARK: - Sendable Conformance
//
// DynamicSchema has mutable state (`attributes: [String: Any]`) that is not
// inherently thread-safe. We mark it `@unchecked Sendable` with the following
// safety contract:
//
// 1. DynamicSchema instances are typically created, populated, and consumed
//    within a single task/thread during row mapping.
// 2. Callers MUST NOT access the same DynamicSchema instance concurrently
//    from multiple tasks without external synchronization.
// 3. Once a DynamicSchema is fully populated, it should be treated as
//    effectively immutable for the remainder of its use.
//
// Violating these invariants may cause data races. If concurrent access is
// needed, wrap the instance in an actor or use locks.
extension DynamicSchema: @unchecked Sendable {}

// MARK: - Schema Extension

extension Schema {
    public mutating func applyValues(_ values: [String: Any]) {
        if var dynamic = self as? DynamicSchema {
            for (key, value) in values { dynamic.setAttribute(key, value: value) }
            if let result = dynamic as? Self {
                self = result
            }
        }
    }
}
