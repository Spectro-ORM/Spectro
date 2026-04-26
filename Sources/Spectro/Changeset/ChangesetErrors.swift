import Foundation

/// Encodable wrapper around a Changeset's validation errors for JSON API responses.
///
/// ```swift
/// let cs = Changeset.cast(nil, params: params, permitted: ["name", "email"])
///     .validateRequired(["name", "email"])
///
/// if !cs.isValid {
///     let body = try JSONEncoder().encode(cs.errorPayload)
///     // {"errors":{"name":["can't be blank"]}}
/// }
/// ```
public struct ChangesetErrors: Encodable, Sendable {
    public let errors: [String: [String]]

    public init<T: Schema>(_ changeset: Changeset<T>) {
        self.errors = changeset.errors
    }
}
