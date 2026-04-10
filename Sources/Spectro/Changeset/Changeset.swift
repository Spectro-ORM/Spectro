import Foundation

/// An Ecto-inspired changeset for tracking, casting, and validating changes to a `Schema`.
///
/// `Changeset` is a **value type** — every validation method returns a new changeset,
/// enabling an immutable pipeline style identical to `Query<T>`:
///
/// ```swift
/// let cs = Changeset.cast(nil, params: params, permitted: ["name", "email"])
///     .validateRequired(["name", "email"])
///     .validateLength("name", min: 2, max: 100)
///     .validateFormat("email", pattern: "^.+@.+\\..+$")
///
/// let user = try await repo.insert(cs)
/// ```
///
/// For updates, pass the existing record as `data`:
///
/// ```swift
/// let cs = Changeset.cast(existingUser, params: ["name": "Alice"], permitted: ["name"])
///     .validateRequired(["name"])
/// ```
public struct Changeset<T: Schema>: Sendable {

    // MARK: - Properties

    /// The original schema instance. `nil` for insert changesets.
    public let data: T?

    /// Pending changes that passed casting (field name → value).
    public private(set) var changes: [String: any Sendable]

    /// Accumulated validation errors (field name → error messages).
    public private(set) var errors: [String: [String]]

    /// The set of field names that were permitted during `cast`.
    public let permitted: Set<String>

    /// Whether the changeset has no validation errors.
    public var isValid: Bool { errors.isEmpty }

    /// The action this changeset represents — useful for conditional validation.
    public let action: Action?

    // MARK: - Action

    public enum Action: String, Sendable {
        case insert
        case update
    }

    // MARK: - Initialization

    /// Create a changeset directly. Prefer `Changeset.cast(...)` for most use cases.
    public init(
        data: T? = nil,
        changes: [String: any Sendable] = [:],
        errors: [String: [String]] = [:],
        permitted: Set<String> = [],
        action: Action? = nil
    ) {
        self.data = data
        self.changes = changes
        self.errors = errors
        self.permitted = permitted
        self.action = action
    }

    // MARK: - Cast

    /// Cast external parameters into a changeset, filtering to only permitted fields.
    ///
    /// This is the primary entry point for creating changesets. Unknown or
    /// non-permitted fields are silently dropped (not treated as errors),
    /// matching Ecto's strong-params approach.
    public static func cast(
        _ data: T?,
        params: [String: any Sendable],
        permitted: [String]
    ) -> Changeset<T> {
        let permittedSet = Set(permitted)
        var changes: [String: any Sendable] = [:]

        for (key, value) in params where permittedSet.contains(key) {
            changes[key] = value
        }

        let action: Action? = data == nil ? .insert : .update

        return Changeset(
            data: data,
            changes: changes,
            errors: [:],
            permitted: permittedSet,
            action: action
        )
    }

    // MARK: - Field Access

    /// Get the pending change for a field, if any.
    public func getChange(_ field: String) -> (any Sendable)? {
        changes[field]
    }

    /// Get the effective value for a field: the pending change if present,
    /// otherwise the original value from `data` via Mirror reflection.
    ///
    /// Returns `Any?` rather than `(any Sendable)?` because Mirror erases
    /// types to `Any`, and Swift 6 disallows conditional casts to `Sendable`.
    public func getField(_ field: String) -> Any? {
        if let change = changes[field] {
            return change
        }
        guard let data = data else { return nil }
        return extractFieldValue(from: data, named: field)
    }

    /// Replace or add a change programmatically (outside of cast).
    public func putChange(_ field: String, value: any Sendable) -> Changeset<T> {
        var copy = self
        copy.changes[field] = value
        return copy
    }

    /// Remove a change for a field.
    public func deleteChange(_ field: String) -> Changeset<T> {
        var copy = self
        copy.changes.removeValue(forKey: field)
        return copy
    }

    // MARK: - Error Management

    /// Add a validation error for a field.
    public func addError(_ field: String, message: String) -> Changeset<T> {
        var copy = self
        copy.errors[field, default: []].append(message)
        return copy
    }

    // MARK: - Validation

    /// Validate that the given fields have non-nil, non-empty values (either in changes or data).
    ///
    /// Like Ecto's `validate_required`, this rejects both nil values and empty/whitespace-only strings.
    public func validateRequired(_ fields: [String]) -> Changeset<T> {
        var copy = self
        for field in fields {
            let value = copy.getField(field)
            if value == nil || isNilAny(value!) {
                copy.errors[field, default: []].append("can't be blank")
            } else if let str = value as? String, str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.errors[field, default: []].append("can't be blank")
            }
        }
        return copy
    }

    /// Validate string length constraints on a field.
    public func validateLength(
        _ field: String,
        min: Int? = nil,
        max: Int? = nil,
        is exact: Int? = nil
    ) -> Changeset<T> {
        guard let value = getField(field) else { return self }
        guard let str = value as? String else { return self }

        var copy = self
        if let min = min, str.count < min {
            copy.errors[field, default: []].append(
                "should be at least \(min) character(s)"
            )
        }
        if let max = max, str.count > max {
            copy.errors[field, default: []].append(
                "should be at most \(max) character(s)"
            )
        }
        if let exact = exact, str.count != exact {
            copy.errors[field, default: []].append(
                "should be \(exact) character(s)"
            )
        }
        return copy
    }

    /// Validate that a string field matches a regex pattern.
    public func validateFormat(_ field: String, pattern: String, message: String? = nil) -> Changeset<T> {
        guard let value = getField(field) else { return self }
        guard let str = value as? String else { return self }

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(str.startIndex..., in: str)
        if regex.firstMatch(in: str, range: range) == nil {
            var copy = self
            copy.errors[field, default: []].append(message ?? "has invalid format")
            return copy
        }
        return self
    }

    /// Validate that a field's value is one of the allowed values.
    public func validateInclusion(_ field: String, in allowed: [any Sendable], message: String? = nil) -> Changeset<T> {
        guard let value = getField(field) else { return self }
        let valueStr = String(describing: value)
        let allowedStrs = allowed.map { String(describing: $0) }
        if !allowedStrs.contains(valueStr) {
            var copy = self
            copy.errors[field, default: []].append(message ?? "is invalid")
            return copy
        }
        return self
    }

    /// Validate that a field's value is NOT one of the disallowed values.
    public func validateExclusion(_ field: String, in disallowed: [any Sendable], message: String? = nil) -> Changeset<T> {
        guard let value = getField(field) else { return self }
        let valueStr = String(describing: value)
        let disallowedStrs = disallowed.map { String(describing: $0) }
        if disallowedStrs.contains(valueStr) {
            var copy = self
            copy.errors[field, default: []].append(message ?? "is reserved")
            return copy
        }
        return self
    }

    /// Validate a numeric field against comparison constraints.
    public func validateNumber(
        _ field: String,
        greaterThan: Double? = nil,
        greaterThanOrEqualTo: Double? = nil,
        lessThan: Double? = nil,
        lessThanOrEqualTo: Double? = nil,
        equalTo: Double? = nil
    ) -> Changeset<T> {
        guard let value = getField(field) else { return self }
        guard let num = toDouble(value) else { return self }

        var copy = self
        if let gt = greaterThan, !(num > gt) {
            copy.errors[field, default: []].append("must be greater than \(gt)")
        }
        if let gte = greaterThanOrEqualTo, !(num >= gte) {
            copy.errors[field, default: []].append("must be greater than or equal to \(gte)")
        }
        if let lt = lessThan, !(num < lt) {
            copy.errors[field, default: []].append("must be less than \(lt)")
        }
        if let lte = lessThanOrEqualTo, !(num <= lte) {
            copy.errors[field, default: []].append("must be less than or equal to \(lte)")
        }
        if let eq = equalTo, num != eq {
            copy.errors[field, default: []].append("must be equal to \(eq)")
        }
        return copy
    }

    /// Run a custom validation closure on a field.
    ///
    /// Return `nil` from the closure if valid, or an error message string if invalid.
    public func validateCustom(_ field: String, _ check: @Sendable (Any) -> String?) -> Changeset<T> {
        guard let value = getField(field) else { return self }
        if let message = check(value) {
            var copy = self
            copy.errors[field, default: []].append(message)
            return copy
        }
        return self
    }

    // MARK: - Apply

    /// Return the changes dict, suitable for passing to `Repo.update`.
    ///
    /// Throws `SpectroError.validationError` if the changeset is invalid.
    public func applyChanges() throws -> [String: any Sendable] {
        guard isValid else {
            let allErrors = errors.flatMap { field, msgs in
                msgs.map { "\(field) \($0)" }
            }
            throw SpectroError.validationError(
                field: errors.keys.first ?? "unknown",
                errors: allErrors
            )
        }
        return changes
    }

    /// Apply changes to an existing or new instance using `MutableSchema`.
    /// For insert changesets (data == nil), creates a fresh `T()` and applies changes.
    ///
    /// Throws `SpectroError.validationError` if the changeset is invalid.
    public func applyToInstance() throws -> T {
        guard isValid else {
            let allErrors = errors.flatMap { field, msgs in
                msgs.map { "\(field) \($0)" }
            }
            throw SpectroError.validationError(
                field: errors.keys.first ?? "unknown",
                errors: allErrors
            )
        }

        let instance = data ?? T()
        if var mutable = instance as? MutableSchema {
            var anyChanges: [String: Any] = [:]
            for (key, value) in changes {
                anyChanges[key] = value
            }
            mutable.apply(values: anyChanges)
            if let result = mutable as? T {
                return result
            }
        }

        // For non-MutableSchema types, return instance as-is.
        // Changes will be applied at the SQL level via the changes dict.
        return instance
    }

    // MARK: - Private Helpers

    /// Extract a field value from a schema instance by property name using Mirror.
    private func extractFieldValue(from instance: T, named field: String) -> Any? {
        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard fieldName == field else { continue }

            // Unwrap property wrapper to get wrappedValue
            let wrapperMirror = Mirror(reflecting: child.value)
            for wrapperChild in wrapperMirror.children {
                if wrapperChild.label == "wrappedValue" {
                    return wrapperChild.value
                }
            }
            // Not a property wrapper — return raw value
            return child.value
        }
        return nil
    }

    /// Check if a value is nil (handles Optional<T> erased to Any).
    private func isNilAny(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    /// Convert a value to Double for numeric validation.
    private func toDouble(_ value: Any) -> Double? {
        switch value {
        case let v as Int:    return Double(v)
        case let v as Double: return v
        case let v as Float:  return Double(v)
        default: return nil
        }
    }
}
